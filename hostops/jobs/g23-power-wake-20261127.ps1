# Owner-approved wake and OMP open. Use exactly one power toggle only on confirmed sleeping/off Redmi.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'WRONG_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
$dev=@(& $adb devices 2>$null)
$auth=@($dev|Where-Object{$_ -match '^\S+\s+device(\s|$)'})
$other=@($dev|Where-Object{$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'})
if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or $other.Count -gt 0){throw 'SINGLE_DEVICE_REQUIRED'}
$serial=($auth[0] -split '\s+')[0]
if(((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim() -cne 'MiTV-ASTR0'){throw 'WRONG_MODEL'}
$pm=@(& $adb -s $serial shell pm path $pkg 2>$null)
if($LASTEXITCODE -ne 0 -or -not @($pm|Where-Object{$_ -match '^package:.*base\.apk$'}).Count){throw 'APK_ABSENT'}
function State{
 $t=((& $adb -s $serial shell dumpsys power 2>$null)|Out-String)
 if($LASTEXITCODE -ne 0){throw 'POWER_STATE_READ_FAILED'}
 $w=[regex]::Match($t,'mWakefulness=(Awake|Asleep|Dozing|Dreaming)')
 $d=[regex]::Match($t,'Display Power:\s*state=(ON|OFF|DOZE(?:_SUSPEND)?|UNKNOWN)')
 return @{wake=$(if($w.Success){$w.Groups[1].Value}else{'UNKNOWN'});display=$(if($d.Success){$d.Groups[1].Value}else{'UNKNOWN'})}
}
$s=State
Write-Host ('G23_PRE_WAKE='+$s.wake+';display='+$s.display)
if($s.display -eq 'OFF' -and $s.wake -in @('Asleep','Dozing')){
 & $adb -s $serial shell input keyevent KEYCODE_POWER 2>$null|Out-Null
 if($LASTEXITCODE -ne 0){throw 'POWER_COMMAND_FAILED'}
 Write-Host 'G23_POWER=ONE_COMMAND_ACCEPTED'
 for($i=0;$i -lt 5;$i++){Start-Sleep -Seconds 2;$s=State;if($s.display -eq 'ON' -and $s.wake -eq 'Awake'){break}}
}else{Write-Host 'G23_POWER=NOT_SENT'}
Write-Host ('G23_POST_WAKE='+$s.wake+';display='+$s.display)
if($s.display -ne 'ON' -or $s.wake -ne 'Awake'){Write-Host 'G23_OUTCOME=HOLD_DISPLAY_NOT_AWAKE';exit 0}
$a=((& $adb -s $serial shell am start -W -n ($pkg+'/com.spacesarmat.omp.MainActivity') 2>$null)|Out-String)
if($LASTEXITCODE -ne 0 -or $a -match '(Error|Exception|Status:\s*timeout)'){throw 'OMP_START_FAILED'}
Start-Sleep -Seconds 3
$act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
$fg=[bool](@($act -split '\r?\n'|Where-Object{$_ -match '(mResumedActivity|topResumedActivity)' -and $_ -match [regex]::Escape($pkg+'/')}).Count)
Write-Host ('G23_OMP_RESUMED='+$fg)
$ss=((& $adb -s $serial shell ss -ltn 2>$null)|Out-String)
$ports=@(8095..8099|Where-Object{$ss -match (':'+$_+'(\s|$)')})
if(-not $ports.Count){$ports=@(8095..8099)}
function Probe([string]$url){try{$r=Invoke-WebRequest -Uri $url -TimeoutSec 4 -MaximumRedirection 0 -NoProxy -SkipHttpErrorCheck;$v=$false;if($r.StatusCode -eq 200){try{$o=$r.Content|ConvertFrom-Json;$v=$null -ne $o.PSObject.Properties['foreground'] -and $null -ne $o.PSObject.Properties['version'] -and $null -ne $o.PSObject.Properties['paired']}catch{}};return ([string]$r.StatusCode+';schema='+$v)}catch{return ('TRANSPORT_'+$_.Exception.GetType().Name)}}
$ip=$null
if($serial -match '^((?:\d{1,3}\.){3}\d{1,3}):\d+$'){$ip=$Matches[1]}
foreach($p in $ports){
 if($ip -and $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){Write-Host ('G23_LAN_'+$p+'='+(Probe ('http://'+$ip+':'+$p+'/omp/info')))}
 $local=((& $adb -s $serial forward 'tcp:0' ('tcp:'+$p) 2>$null)|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $local -notmatch '^\d{1,5}$'){continue}
 try{Write-Host ('G23_LOCAL_'+$p+'='+(Probe ('http://127.0.0.1:'+$local+'/omp/info')))}finally{& $adb -s $serial forward --remove ('tcp:'+$local) 2>$null|Out-Null;if($LASTEXITCODE -ne 0){throw 'FORWARD_CLEANUP_FAILED'}}
}
Write-Host 'G23_PAIR_PLAY=NOT_ATTEMPTED'
