# Torrent TV: private GitHub inbox to authorized Redmi SRT transfer.
# This public source file does not contain film dialogue or user media.
param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'TTV_HANDOFF_WRONG_RUNNER' }
if ($Request -cnotmatch '^/tv-subtitle deliver ([a-z0-9][a-z0-9-]{0,39}) ([a-f0-9]{64})$') { throw 'TTV_HANDOFF_BAD_REQUEST' }
$key = $Matches[1]
$expected = $Matches[2]
if ([string]::IsNullOrWhiteSpace($env:TTV_PRIVATE_SUBTITLE_READ_TOKEN)) { throw 'TTV_HANDOFF_PRIVATE_REPO_TOKEN_MISSING' }
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'TTV_HANDOFF_ADB_MISSING' }
$uri = 'https://api.github.com/repos/trung-via/torrent-tv-subtitle-inbox/contents/inbox/' + $key + '.srt'
$headers = @{
  Authorization = 'Bearer ' + $env:TTV_PRIVATE_SUBTITLE_READ_TOKEN
  Accept = 'application/vnd.github+json'
  'User-Agent' = 'Torrent-TV-private-subtitle-handoff'
}
$temp = Join-Path $env:RUNNER_TEMP ('ttv-subtitle-' + [Guid]::NewGuid().ToString('N') + '.srt')
function Invoke-AdbSafe([string[]]$CommandArgs) {
  foreach($value in $CommandArgs) { if($value -match '\s' -or [string]::IsNullOrEmpty($value)) { throw 'TTV_HANDOFF_INVALID_ADB_ARGUMENT' } }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $adb
  $psi.Arguments = ($CommandArgs -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::Start($psi)
  try {
    $out = $process.StandardOutput.ReadToEnd()
    $null = $process.StandardError.ReadToEnd()
    if(-not $process.WaitForExit(60000)) { $process.Kill(); throw 'TTV_HANDOFF_ADB_TIMEOUT' }
    return [PSCustomObject]@{Code=$process.ExitCode;Out=$out}
  } finally { $process.Dispose() }
}
Write-Host 'TTV_PRIVATE_SUBTITLE_HANDOFF_BEGIN'
Write-Host ('TTV_PRIVATE_SUBTITLE_KEY=' + $key)
try {
  try { $file = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop }
  catch { throw 'TTV_HANDOFF_PRIVATE_REPO_READ_FAILED' }
  if ($file.type -cne 'file' -or $file.encoding -cne 'base64') { throw 'TTV_HANDOFF_UNEXPECTED_FILE_RESPONSE' }
  $payload = [Convert]::FromBase64String(([string]$file.content -replace '\s', ''))
  if ($payload.Length -lt 16 -or $payload.Length -gt 1048576 -or [int]$file.size -ne $payload.Length) { throw 'TTV_HANDOFF_FILE_SIZE_INVALID' }
  [IO.File]::WriteAllBytes($temp,$payload)
  $sha = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($sha -cne $expected) { throw 'TTV_HANDOFF_SOURCE_SHA_MISMATCH' }
  Write-Host 'TTV_HANDOFF_GITHUB_PRIVATE_SOURCE_SHA_PASS'
  $devices = Invoke-AdbSafe -CommandArgs @('devices','-l')
  if ($devices.Code -ne 0) { throw 'TTV_HANDOFF_ADB_LIST_FAILED' }
  $ids = @()
  foreach ($line in ($devices.Out -split '\r?\n')) {
    if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $ids += [string]$Matches[1] }
  }
  if ($ids.Count -ne 1) { throw 'TTV_HANDOFF_DEVICE_COUNT_NOT_ONE' }
  $serial = [string]$ids[0]
  $model = Invoke-AdbSafe -CommandArgs @('-s',$serial,'shell','getprop','ro.product.model')
  if ($model.Code -ne 0 -or $model.Out.Trim() -cne 'MiTV-ASTR0') { throw 'TTV_HANDOFF_WRONG_TV' }
  $target = '/sdcard/Download/TTV-' + $key + '-' + $expected.Substring(0,12) + '.srt'
  $push = Invoke-AdbSafe -CommandArgs @('-s',$serial,'push',$temp,$target)
  if ($push.Code -ne 0) { throw 'TTV_HANDOFF_ADB_PUSH_FAILED' }
  $remote = Invoke-AdbSafe -CommandArgs @('-s',$serial,'shell','sha256sum',$target)
  $remoteHash = [regex]::Match([string]$remote.Out, '^([a-fA-F0-9]{64})\s')
  if ($remote.Code -ne 0 -or -not $remoteHash.Success) { throw 'TTV_HANDOFF_REMOTE_HASH_UNAVAILABLE' }
  if ($remoteHash.Groups[1].Value.ToLowerInvariant() -cne $expected) { throw 'TTV_HANDOFF_REMOTE_SHA_MISMATCH' }
  Write-Host 'TTV_HANDOFF_PRIVATE_GITHUB_TO_REDMITV_SHA_PASS'
  Write-Host 'TTV_HANDOFF_OMP_IMPORT_AND_RENDER=NOT_RUN'
  Write-Host 'TTV_HANDOFF_SEEK_RESUME=NOT_RUN'
} finally {
  if (Test-Path -LiteralPath $temp -PathType Leaf) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}
Write-Host 'TTV_PRIVATE_SUBTITLE_HANDOFF_END'
