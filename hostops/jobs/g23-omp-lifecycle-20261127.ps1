# G2.3: compare OMP foreground/lifecycle with native HTTP status.
# No force-stop, TV power change, pairing, playback, install, credentials, or restart.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G23_WRONG_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
$devices=@(& $adb devices 2>$null)
$auth=@($devices | Where-Object {$_ -match '^\S+\s+device(\s|$)'})
$other=@($devices | Where-Object {$_ -match '^\S+\s+(unauthorized|offline)(\s|$)'})
if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or $other.Count -gt 0){throw 'G23_SINGLE_DEVICE_REQUIRED'}
$serial=($auth[0] -split '\s+')[0]
$model=((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim()
if($model -cne 'MiTV-ASTR0'){throw 'G23_WRONG_MODEL'}
$pm=@(& $adb -s $serial shell pm path $pkg 2>$null)
if($LASTEXITCODE -ne 0 -or -not @($pm | Where-Object {$_ -match '^package:.*base\.apk$'}).Count){throw 'G23_APK_ABSENT'}
function Get-Foreground {
  $w=((& $adb -s $serial shell dumpsys window windows 2>$null)|Out-String)
  $a=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
  $l=@($w -split "\r?\n" | Where-Object {$_ -match 'mCurrentFocus='})
  if(-not $l.Count){$l=@($a -split "\r?\n" | Where-Object {$_ -match 'mResumedActivity|topResumedActivity'})}
  $match=[regex]::Match(($l -join ' '),'(?:\b)([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)/[A-Za-z0-9_.$]+')
  if($match.Success){return $match.Groups[1].Value}
  return ''
}
function Test-Http([string]$url){
  # Return status separately from schema; never emit response body or address.
  try{
    $r=Invoke-WebRequest -Uri $url -TimeoutSec 3 -MaximumRedirection 0 -NoProxy -SkipHttpErrorCheck
    $valid=$false
    if($r.StatusCode -eq 200){
      try{$obj=$r.Content|ConvertFrom-Json
        $valid=$null -ne $obj.PSObject.Properties['version'] -and $null -ne $obj.PSObject.Properties['foreground'] -and $null -ne $obj.PSObject.Properties['paired']
      }catch{}
    }
    return @{status=[string]$r.StatusCode;schema=$valid}
  }catch{
    return @{status='TRANSPORT_'+$_.Exception.GetType().Name;schema=$false}
  }
}
function Probe([string]$phase){
  $pidText=((& $adb -s $serial shell pidof $pkg 2>$null)|Out-String).Trim()
  $fg=Get-Foreground
  Write-Host ("G23_"+$phase+"_PROCESS="+[bool]($pidText -match '^\d+(\s+\d+)*$'))
  Write-Host ("G23_"+$phase+"_FOREGROUND="+[bool]($fg -ceq $pkg))
  $ss=((& $adb -s $serial shell ss -ltn 2>$null)|Out-String)
  $ports=@(8095..8099|Where-Object{$ss -match (':'+$_+'(\s|$)')})
  if(-not $ports.Count){$ports=@(8095..8099)}
  foreach($p in $ports){
    $local=((& $adb -s $serial forward 'tcp:0' ('tcp:'+$p) 2>$null)|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $local -notmatch '^\d{1,5}$'){Write-Host ("G23_"+$phase+"_FORWARD_"+$p+"=FAILED");continue}
    try{
      $r=Test-Http ("http://127.0.0.1:"+$local+"/omp/info")
      Write-Host ("G23_"+$phase+"_PORT_"+$p+"="+$r.status+";schema="+$r.schema)
    }finally{
      & $adb -s $serial forward --remove ('tcp:'+$local) 2>$null|Out-Null
      if($LASTEXITCODE -ne 0){throw 'G23_FORWARD_CLEANUP_FAILED'}
    }
  }
}
Probe 'BEFORE'
$fg=Get-Foreground
$homeText=((& $adb -s $serial shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>$null)|Out-String)
$homeMatch=[regex]::Match($homeText,'([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+)/[A-Za-z0-9_.$]+')
$power=((& $adb -s $serial shell dumpsys power 2>$null)|Out-String)
if($fg -ceq $pkg){Write-Host 'G23_LAUNCH=NOT_NEEDED_ALREADY_FOREGROUND';exit 0}
if(-not $homeMatch.Success -or $fg -cne $homeMatch.Groups[1].Value -or $power -notmatch 'mWakefulness=Awake'){Write-Host 'G23_LAUNCH=NOT_ATTEMPTED_NOT_CONFIRMED_IDLE_HOME_AWAKE';exit 0}
# User-authorized prototype: open only the existing app from awake idle launcher.
$start=((& $adb -s $serial shell am start -W -n ($pkg+'/com.spacesarmat.omp.MainActivity') 2>$null)|Out-String)
if($LASTEXITCODE -ne 0 -or $start -match '(Error|Exception)'){Write-Host 'G23_LAUNCH=FAILED';exit 0}
Write-Host 'G23_LAUNCH=REQUEST_ACCEPTED'
Start-Sleep -Seconds 3
Probe 'AFTER'
Write-Host 'G23_PAIR_PLAY=NOT_ATTEMPTED'
exit 0
