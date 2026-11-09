# Torrent TV — real Redmi Thor v0.3.5 and OMP session inventory (READ ONLY).
# No ADB pairing, new app launch, key events, file transfer, screen capture, media or metadata dumps.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'G1_THOR_UI_PREFLIGHT_BEGIN'
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'UNEXPECTED_RUNNER' }
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$dest='/sdcard/Download/TTV-thor-v035-3d9d4bf37fe3.srt'
$expected='3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Write-Host 'G1_THOR_UI_STATUS=ADB_NOT_FOUND'; exit 0 }
function RunAdb([string[]]$A) {
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$adb
  $psi.Arguments=($A -join ' ')
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $p=[System.Diagnostics.Process]::Start($psi)
  try{
    $stdout=$p.StandardOutput.ReadToEnd()
    $null=$p.StandardError.ReadToEnd()
    if(-not $p.WaitForExit(30000)){ $p.Kill(); throw 'ADB_TIMEOUT' }
    return [PSCustomObject]@{Exit=$p.ExitCode;Text=$stdout}
  } finally { $p.Dispose() }
}
try {
  $devices=RunAdb @('devices','-l')
  if($devices.Exit -ne 0){throw 'ADB_DEVICES_FAILED'}
  $ids=@()
  foreach($line in ($devices.Text -split '\r?\n')) {
    if($line -match '^\s*(\S+)\s+device(?:\s|$)'){ $ids += [string]$Matches[1] }
  }
  Write-Host ('G1_THOR_ADB_DEVICE_COUNT=' + $ids.Count)
  if($ids.Count -ne 1){Write-Host 'G1_THOR_UI_STATUS=DEVICE_NOT_UNAMBIGUOUS';exit 0}
  $serial=$ids[0]
  $model=RunAdb @('-s',$serial,'shell','getprop','ro.product.model')
  if($model.Exit -ne 0 -or $model.Text.Trim() -cne 'MiTV-ASTR0'){
    Write-Host 'G1_THOR_UI_STATUS=WRONG_DEVICE';exit 0
  }
  Write-Host 'G1_THOR_MODEL=MiTV-ASTR0'
  $hash=RunAdb @('-s',$serial,'shell','sha256sum',$dest)
  if($hash.Exit -eq 0 -and $hash.Text -match '^([a-fA-F0-9]{64})\s') {
    $verified=($Matches[1].ToLowerInvariant() -ceq $expected)
    Write-Host ('G1_THOR_SRT_REMOTE_SHA_MATCH=' + $verified.ToString().ToUpperInvariant())
  } else {
    Write-Host 'G1_THOR_SRT_REMOTE_SHA_MATCH=UNVERIFIED'
  }
  $activities=RunAdb @('-s',$serial,'shell','dumpsys','activity','activities')
  if($activities.Exit -ne 0){Write-Host 'G1_THOR_ACTIVITY_STATUS=UNAVAILABLE'}
  else {
    $interesting=@(($activities.Text -split '\r?\n') | Where-Object {
      $_ -match 'topResumedActivity|mResumedActivity|mFocusedApp|mCurrentFocus|mTopResumedActivity'
    })
    if($interesting.Count -eq 0){Write-Host 'G1_THOR_ACTIVITY_STATUS=UNKNOWN'}
    else{
      $omp=@($interesting | Where-Object { $_ -match 'com\.spacesarmat\.omp\.test' })
      Write-Host ('G1_THOR_FOREGROUND_OMP_SIGNALS=' + $omp.Count)
      Write-Host ('G1_THOR_FOREGROUND_STATUS=' + $(if($omp.Count -gt 0){'OMP_FOCUSED'}else{'OTHER_OR_UNCERTAIN'}))
      $player=@($omp | Where-Object { $_ -match 'PlayerActivity|player' })
      Write-Host ('G1_THOR_FOREGROUND_PLAYER_SIGNALS=' + $player.Count)
    }
  }
  $sessions=RunAdb @('-s',$serial,'shell','dumpsys','media_session')
  if($sessions.Exit -eq 0){
    $packageMentions=@(($sessions.Text -split '\r?\n') | Where-Object {
      $_ -match '^\s*(?:package|packageName|ownerPackageName|mPackageName)\s*[=:]\s*com\.spacesarmat\.omp\.test\b'
    })
    Write-Host ('G1_THOR_OMP_MEDIA_SESSION_PACKAGE_LINES=' + $packageMentions.Count)
  } else {Write-Host 'G1_THOR_MEDIA_SESSION_STATUS=UNAVAILABLE'}
  Write-Host 'G1_THOR_UI_STATUS=READ_ONLY_PREFLIGHT_DONE'
} catch {
  Write-Host 'G1_THOR_UI_STATUS=READ_ONLY_PROBE_FAILED'
  Write-Host ('G1_THOR_UI_EXCEPTION_TYPE=' + $_.Exception.GetType().Name)
}
Write-Host 'G1_THOR_ADB_UI_ACTIONS=NONE'
Write-Host 'G1_THOR_OMP_IMPORT_AND_RENDER=NOT_RUN'
Write-Host 'G1_THOR_SEEK_RESUME=NOT_RUN'
Write-Host 'G1_THOR_UI_PREFLIGHT_END'
exit 0
