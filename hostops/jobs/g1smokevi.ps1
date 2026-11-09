# Synthetic original 3-cue Vietnamese test fixture; not private film content.
# Owner authorizes one ADB push to a dedicated Download path; no APK or playback changes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
Write-Host 'TTV_SMOKE_BEGIN'
if($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows'){throw 'BAD_RUNNER'}
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$dest='/sdcard/Download/TTV_G1_SMOKE_VI.srt'
$expected='71c87bed31c6bdc73c1e1f27290a3d82271988686e1e6a32ad3fc40661bf1261'
$payload='MQowMDowMDowMSwwMDAgLS0+IDAwOjAwOjAzLDAwMApYaW4gY2jDoG8hIMSQw6J5IGzDoCBi4bqjbiB0aOG7rSB0aeG6v25nIFZp4buHdC4KCjIKMDA6MDA6MDQsMDAwIC0tPiAwMDowMDowNiwwMDAKROG6pXUgc+G6r2MsIGh1eeG7gW4sIGjhu49pLCBuZ8OjLCBu4bq3bmc6IOG6ryDhurEg4bqzIOG6tSDhurcuCgozCjAwOjAwOjA3LDAwMCAtLT4gMDA6MDA6MDksMDAwCktp4buDbSB0cmEgcGjhu6UgxJHhu4Egbmdvw6BpIOG7qW5nIGThu6VuZy4K'
$tempFile=Join-Path $env:RUNNER_TEMP 'TTV_G1_SMOKE_VI.srt'
if(-not (Test-Path -LiteralPath $adb -PathType Leaf)){Write-Host 'TTV_SMOKE_STATUS=ADB_MISSING';exit 0}
try{
  $bytes=[Convert]::FromBase64String($payload)
  if($bytes.Length -ne 255){throw 'WRONG_FIXTURE_BYTES'}
  [IO.File]::WriteAllBytes($tempFile,$bytes)
  if((Get-FileHash -LiteralPath $tempFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected){throw 'FIXTURE_SHA_MISMATCH'}
  $devices=@(& $adb devices -l 2>$null)
  if($LASTEXITCODE -ne 0){throw 'ADB_LIST_FAILED'}
  $ids=@()
  foreach($line in $devices){if($line -match '^\s*(\S+)\s+device(?:\s|$)'){$ids += [string]$Matches[1]}}
  Write-Host ('TTV_SMOKE_DEVICE_COUNT=' + $ids.Count)
  if($ids.Count -ne 1){Write-Host 'TTV_SMOKE_STATUS=DEVICE_AMBIGUOUS';exit 0}
  $serial=[string]$ids[0]
  $model=@(& $adb -s $serial shell getprop ro.product.model 2>$null)
  if($LASTEXITCODE -ne 0 -or $model.Count -ne 1 -or ([string]$model[0]).Trim() -cne 'MiTV-ASTR0'){
    Write-Host 'TTV_SMOKE_STATUS=UNEXPECTED_DEVICE';exit 0
  }
  $existing=@(& $adb -s $serial shell sha256sum $dest 2>$null)
  if($LASTEXITCODE -eq 0 -and $existing.Count -ge 1){
    if(([string]$existing[0]).Trim() -match '^([a-fA-F0-9]{64})\s+' -and $Matches[1].ToLowerInvariant() -ceq $expected){
      Write-Host 'TTV_SMOKE_STATUS=ALREADY_PRESENT_SHA_PASS';exit 0
    }
    Write-Host 'TTV_SMOKE_STATUS=EXISTING_DEST_MISMATCH_BLOCKED';exit 0
  }
  & $adb -s $serial push $tempFile $dest 1>$null 2>$null
  if($LASTEXITCODE -ne 0){Write-Host 'TTV_SMOKE_STATUS=ADB_PUSH_FAILED';exit 0}
  $remote=@(& $adb -s $serial shell sha256sum $dest 2>$null)
  if($LASTEXITCODE -ne 0 -or $remote.Count -ne 1){Write-Host 'TTV_SMOKE_STATUS=REMOTE_SHA_UNAVAILABLE';exit 0}
  if(([string]$remote[0]).Trim() -notmatch '^([a-fA-F0-9]{64})\s+'){Write-Host 'TTV_SMOKE_STATUS=BAD_REMOTE_SHA';exit 0}
  if($Matches[1].ToLowerInvariant() -cne $expected){Write-Host 'TTV_SMOKE_STATUS=REMOTE_SHA_MISMATCH';exit 0}
  Write-Host 'TTV_SMOKE_STATUS=ADB_PUSH_REMOTE_SHA_PASS'
  Write-Host 'TTV_SMOKE_BYTES_ON_REDMITV=255'
  Write-Host 'TTV_SMOKE_OMP_IMPORT_RENDER=NOT_RUN'
}catch{
  Write-Host 'TTV_SMOKE_STATUS=EXCEPTION_REDACTED'
}finally{
  if(Test-Path -LiteralPath $tempFile -PathType Leaf){Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue}
}
Write-Host 'TTV_SMOKE_USER_SUBTITLE_NOT_PUBLISHED=TRUE'
Write-Host 'TTV_SMOKE_END'
exit 0
