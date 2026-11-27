# G2.3 diagnostic: inspect exact Redmi and OMP native service. Ephemeral ADB forwards are removed.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win'){throw 'G23_BAD_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$pkg='com.spacesarmat.omp.test'
if(-not(Test-Path -LiteralPath $adb -PathType Leaf)){throw 'G23_ADB_MISSING'}
$devices=@(& $adb devices 2>$null)
$auth=@($devices | Where-Object {$_ -match '^\S+\s+device(\s|$)'})
$other=@($devices | Where-Object {$_ -match '^\S+\s+(unauthorized|offline)(\s|$)'})
if($LASTEXITCODE -ne 0 -or $auth.Count -ne 1 -or $other.Count -gt 0){throw 'G23_SINGLE_DEVICE_REQUIRED'}
$serial=($auth[0] -split '\s+')[0]
$model=((& $adb -s $serial shell getprop ro.product.model 2>$null)|Out-String).Trim()
if($model -cne 'MiTV-ASTR0'){throw 'G23_WRONG_DEVICE'}
$installed=@(& $adb -s $serial shell pm path $pkg 2>$null)
if($LASTEXITCODE -ne 0 -or -not @($installed | Where-Object {$_ -match '^package:.*base\.apk$'}).Count){throw 'G23_APK_ABSENT'}
$process=((& $adb -s $serial shell pidof $pkg 2>$null)|Out-String).Trim()
Write-Host ('G23_PROCESS_RUNNING='+[bool]($process -match '^\d+(\s+\d+)*$'))
$activities=((& $adb -s $serial shell dumpsys activity activities 2>$null)|Out-String)
$resumed=@($activities -split "\r?\n" | Where-Object {$_ -match '(mResumedActivity|topResumedActivity)'})
$mine=@($resumed | Where-Object {$_ -match [regex]::Escape($pkg+'/')})
$playing=@($mine | Where-Object {$_ -match 'PlayerActivity'})
Write-Host ('G23_OMP_FOREGROUND='+[bool]$mine.Count)
Write-Host ('G23_PLAYER_FOREGROUND='+[bool]$playing.Count)
$features=((& $adb -s $serial shell pm list features 2>$null)|Out-String)
Write-Host ('G23_LEANBACK_FEATURE='+[bool]($features -match 'android\.software\.leanback(\s|$)'))
$mode=((& $adb -s $serial shell dumpsys uimode 2>$null)|Out-String)
$m=[regex]::Match($mode,'mCurUiMode\s*=\s*0x([0-9a-fA-F]+)')
if($m.Success){Write-Host ('G23_UI_MODE_TELEVISION='+[bool](([Convert]::ToInt32($m.Groups[1].Value,16) -band 15) -eq 4))}
else{Write-Host 'G23_UI_MODE_TELEVISION=UNKNOWN'}
$sockets=((& $adb -s $serial shell ss -ltn 2>$null)|Out-String)
$ports=@(8095..8099 | Where-Object {$sockets -match (':'+$_+'(\s|$)')})
Write-Host ('G23_LISTEN_PORT_COUNT='+$ports.Count)
$found=0
foreach($p in 8095..8099){
  $local=((& $adb -s $serial forward 'tcp:0' ('tcp:'+$p) 2>$null)|Out-String).Trim()
  if($LASTEXITCODE -ne 0 -or $local -notmatch '^\d{1,5}$'){continue}
  try{
    try{
      $r=Invoke-WebRequest -Uri ("http://127.0.0.1:"+$local+"/omp/info") -TimeoutSec 2 -MaximumRedirection 0 -NoProxy
      $obj=$r.Content | ConvertFrom-Json
      if($r.StatusCode -eq 200 -and $null -ne $obj.PSObject.Properties['version'] -and $null -ne $obj.PSObject.Properties['foreground'] -and $null -ne $obj.PSObject.Properties['paired']){
        $found++
        Write-Host ('G23_LOCAL_INFO_PORT='+$p)
        Write-Host ('G23_LOCAL_OMP_FOREGROUND='+[bool]$obj.foreground)
      }
    }catch{}
  }finally{
    & $adb -s $serial forward --remove ('tcp:'+$local) 2>$null | Out-Null
    if($LASTEXITCODE -ne 0){throw 'G23_FORWARD_CLEANUP_FAILED'}
  }
}
Write-Host ('G23_LOCAL_ENDPOINT_COUNT='+$found)
Write-Host 'G23_APP_LAUNCH=NOT_ATTEMPTED'
Write-Host 'G23_PAIR_PLAY=NOT_ATTEMPTED'
exit 0
