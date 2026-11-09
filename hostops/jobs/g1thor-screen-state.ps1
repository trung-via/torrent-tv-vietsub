# Torrent TV: read-only screen state before any attended OMP UI test.
# Never launch, wake, keyevent, change playback, capture screen, or log private media.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Write-Host 'G1_SCREEN_READINESS_BEGIN'
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'UNEXPECTED_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){throw 'ADB_MISSING'}
function RunAdb([string[]]$A) {
  $p=New-Object System.Diagnostics.ProcessStartInfo
  $p.FileName=$adb
  $p.Arguments=($A -join ' ')
  $p.UseShellExecute=$false
  $p.RedirectStandardOutput=$true
  $p.RedirectStandardError=$true
  $p.CreateNoWindow=$true
  $q=[System.Diagnostics.Process]::Start($p)
  try {
    $output=$q.StandardOutput.ReadToEnd()
    $null=$q.StandardError.ReadToEnd()
    if(-not $q.WaitForExit(30000)){$q.Kill();throw 'ADB_TIMEOUT'}
    return [PSCustomObject]@{Exit=$q.ExitCode;Text=$output}
  } finally {$q.Dispose()}
}
try{
  $devices=RunAdb @('devices','-l')
  if($devices.Exit -ne 0){throw 'ADB_DEVICE_LIST_FAILED'}
  $ids=@()
  foreach($line in ($devices.Text -split '\r?\n')){
    if($line -match '^\s*(\S+)\s+device(?:\s|$)'){$ids += [string]$Matches[1]}
  }
  if($ids.Count -ne 1){Write-Host 'G1_SCREEN_STATUS=DEVICE_NOT_UNAMBIGUOUS';exit 0}
  $serial=[string]$ids[0]
  $model=RunAdb @('-s',$serial,'shell','getprop','ro.product.model')
  if($model.Exit -ne 0 -or $model.Text.Trim() -cne 'MiTV-ASTR0'){
    Write-Host 'G1_SCREEN_STATUS=WRONG_DEVICE';exit 0
  }
  $power=RunAdb @('-s',$serial,'shell','dumpsys','power')
  if($power.Exit -ne 0){Write-Host 'G1_SCREEN_POWER=UNKNOWN'}
  elseif($power.Text -match 'mWakefulness=(Awake|Asleep|Dozing|Dreaming)'){
    Write-Host ('G1_SCREEN_POWER=' + $Matches[1].ToUpperInvariant())
  } else {Write-Host 'G1_SCREEN_POWER=UNKNOWN'}
  $win=RunAdb @('-s',$serial,'shell','dumpsys','window','windows')
  if($win.Exit -ne 0) {Write-Host 'G1_SCREEN_FOCUS=UNKNOWN'}
  else {
    $focus=@(($win.Text -split '\r?\n') | Where-Object { $_ -match 'mCurrentFocus=|mFocusedApp=' })
    if($focus.Count -eq 0){Write-Host 'G1_SCREEN_FOCUS=UNKNOWN'}
    else{
      $top=[string]$focus[0]
      $type='OTHER_OR_UNKNOWN'
      if($top -match 'com\.spacesarmat\.omp\.test'){ $type='OMP' }
      elseif($top -match 'com\.mitv\.(?:tvhome|home|launcher)\b|com\.android\.launcher\b|com\.google\.android\.tvlauncher\b'){ $type='LAUNCHER' }
      elseif($top -match 'com\.android\.systemui\b'){ $type='SYSTEM_UI' }
      Write-Host ('G1_SCREEN_FOCUS=' + $type)
    }
  }
  $session=RunAdb @('-s',$serial,'shell','dumpsys','media_session')
  if($session.Exit -eq 0){
    $playStates=@(($session.Text -split '\r?\n') | Where-Object { $_ -match '(?i)state=PlaybackState\s*\{state=3|state=PlaybackState\s*\{state=3' })
    Write-Host ('G1_SCREEN_ACTIVE_PLAYBACK_INDICATORS=' + $playStates.Count)
  } else {Write-Host 'G1_SCREEN_MEDIA_SESSION=UNAVAILABLE'}
  Write-Host 'G1_SCREEN_STATUS=READ_ONLY_DONE'
} catch {
  Write-Host 'G1_SCREEN_STATUS=READ_ONLY_FAILED'
  Write-Host ('G1_SCREEN_EXCEPTION_TYPE=' + $_.Exception.GetType().Name)
}
Write-Host 'G1_SCREEN_ACTUATION=NONE'
Write-Host 'G1_SCREEN_READINESS_END'
exit 0
