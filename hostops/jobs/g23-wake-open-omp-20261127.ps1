# Explicitly owner-authorized: wake the enrolled Redmi and open existing OMP Debug.
# No power toggle, force-stop, install, pairing, playback or config changes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G23_WRONG_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
$devices=@(& $adb devices 2>$null)
$auth=@($devices | Where-Object {$_ -match '^\S+\s+device(\s|$)'})
$other=@($devices | Where-Object {$_ -match '^\S+\s+(offline|unauthorized)(\s|$)'})
if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or $other.Count -gt 0){throw 'G23_SINGLE_DEVICE_REQUIRED'}
$serial=($auth[0] -split '\s+')[0]
$model=((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim()
if($model -cne 'MiTV-ASTR0'){throw 'G23_WRONG_MODEL'}
$pm=@(& $adb -s $serial shell pm path $pkg 2>$null)
if($LASTEXITCODE -ne 0 -or -not @($pm | Where-Object {$_ -match '^package:.*base\.apk$'}).Count){throw 'G23_APK_ABSENT'}
Write-Host 'G23_DEVICE=EXPECTED_REDMi'
& $adb -s $serial shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
if($LASTEXITCODE -ne 0){throw 'G23_WAKE_COMMAND_FAILED'}
Write-Host 'G23_WAKE=COMMAND_ACCEPTED'
Start-Sleep -Seconds 2
$start=((& $adb -s $serial shell am start -W -n ($pkg+'/com.spacesarmat.omp.MainActivity') 2>$null)|Out-String)
if($LASTEXITCODE -ne 0 -or $start -match '(Error|Exception|Status:\s*timeout)'){throw 'G23_OMP_LAUNCH_FAILED'}
Write-Host 'G23_LAUNCH=COMMAND_ACCEPTED'
Start-Sleep -Seconds 3
$power=((& $adb -s $serial shell dumpsys power 2>$null)|Out-String)
Write-Host ('G23_AWAKE='+[bool]($power -match 'mWakefulness=Awake'))
$display= [regex]::Match($power,'Display Power:\s*state=(ON|OFF|DOZE(?:_SUSPEND)?|UNKNOWN)')
if($display.Success){Write-Host ('G23_DISPLAY='+$display.Groups[1].Value)}else{Write-Host 'G23_DISPLAY=UNKNOWN'}
$act=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
$lines=@($act -split '\r?\n' | Where-Object {$_ -match '(mResumedActivity|topResumedActivity)'})
Write-Host ('G23_OMP_RESUMED='+[bool](@($lines|Where-Object{$_ -match [regex]::Escape($pkg+'/')}).Count))
$ss=((& $adb -s $serial shell ss -ltn 2>$null)|Out-String)
$ports=@(8095..8099 | Where-Object{$ss -match (':'+$_+'(\s|$)')})
if(-not $ports.Count){$ports=@(8095..8099)}
function Probe([string]$url){
 try{
  $r=Invoke-WebRequest -Uri $url -TimeoutSec 4 -MaximumRedirection 0 -NoProxy -SkipHttpErrorCheck
  $valid=$false
  $fg='UNKNOWN'
  if($r.StatusCode -eq 200){
   try{$o=$r.Content|ConvertFrom-Json
    $valid=$null -ne $o.PSObject.Properties['version'] -and $null -ne $o.PSObject.Properties['foreground'] -and $null -ne $o.PSObject.Properties['paired']
    if($valid){$fg=[string]$o.foreground}
   }catch{}
  }
  return ([string]$r.StatusCode+';schema='+$valid+';foreground='+$fg)
 }catch{return ('TRANSPORT_'+$_.Exception.GetType().Name)}
}
$ip=$null
if($serial -match '^((?:\d{1,3}\.){3}\d{1,3}):\d+$'){$ip=$Matches[1]}
foreach($p in $ports){
 if($ip -and $ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'){
  Write-Host ('G23_LAN_'+$p+'='+(Probe ('http://'+$ip+':'+$p+'/omp/info')))
 }
 $local=((& $adb -s $serial forward 'tcp:0' ('tcp:'+$p) 2>$null)|Out-String).Trim()
 if($LASTEXITCODE -ne 0 -or $local -notmatch '^\d{1,5}$'){Write-Host ('G23_FORWARD_'+$p+'=FAILED');continue}
 try{Write-Host ('G23_LOCAL_'+$p+'='+(Probe ('http://127.0.0.1:'+$local+'/omp/info')))}
 finally{& $adb -s $serial forward --remove ('tcp:'+$local) 2>$null|Out-Null;if($LASTEXITCODE -ne 0){throw 'G23_FORWARD_CLEANUP_FAILED'}}
}
Write-Host 'G23_PAIR_PLAY=NOT_ATTEMPTED'
exit 0
