# Torrent TV -- same-repository SRT -> dedicated Windows runner -> Redmi.
# Requires the owner-created SRT in subtitle-artifacts/<slug>.srt at this workflow's checkout SHA.
param([Parameter(Mandatory=$true)][string]$Request)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'TTV_HANDOFF_BAD_RUNNER' }
if ($Request -cnotmatch '^/tv-subtitle deliver ([a-z0-9][a-z0-9-]{0,39}) ([a-f0-9]{64})$') { throw 'TTV_HANDOFF_BAD_REQUEST' }
$slug = $Matches[1]
$expected = $Matches[2]
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$source = Join-Path $env:GITHUB_WORKSPACE ('subtitle-artifacts\' + $slug + '.srt')
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw 'TTV_HANDOFF_ADB_NOT_FOUND' }
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'TTV_HANDOFF_REPO_SRT_NOT_FOUND' }
$info = Get-Item -LiteralPath $source
if ($info.Length -lt 16 -or $info.Length -gt 1048576) { throw 'TTV_HANDOFF_SRT_SIZE_INVALID' }
$localHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($localHash -cne $expected) { throw 'TTV_HANDOFF_SOURCE_SHA_MISMATCH' }
Write-Host ('TTV_HANDOFF_SOURCE=' + $slug)
Write-Host ('TTV_HANDOFF_SOURCE_BYTES=' + $info.Length)
Write-Host 'TTV_HANDOFF_REPO_SHA_PASS'

function Invoke-AdbSafe([string[]]$CommandArgs) {
    foreach ($arg in $CommandArgs) {
        if ([string]::IsNullOrWhiteSpace($arg) -or $arg -match '\s') { throw 'TTV_HANDOFF_ADB_ARG_INVALID' }
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $adb
    $psi.Arguments = ($CommandArgs -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    try {
        $stdout = $process.StandardOutput.ReadToEnd()
        $null = $process.StandardError.ReadToEnd()
        if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'TTV_HANDOFF_ADB_TIMEOUT' }
        return [PSCustomObject]@{ Code=$process.ExitCode; Out=$stdout }
    } finally { $process.Dispose() }
}

$devices = Invoke-AdbSafe -CommandArgs @('devices','-l')
if ($devices.Code -ne 0) { throw 'TTV_HANDOFF_ADB_LIST_FAILED' }
$ids = @()
foreach ($line in ($devices.Out -split '\r?\n')) {
    if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $ids += [string]$Matches[1] }
}
if ($ids.Count -ne 1) { throw 'TTV_HANDOFF_EXPECT_ONE_ADB_DEVICE' }
$serial = [string]$ids[0]
$model = Invoke-AdbSafe -CommandArgs @('-s',$serial,'shell','getprop','ro.product.model')
if ($model.Code -ne 0 -or $model.Out.Trim() -cne 'MiTV-ASTR0') { throw 'TTV_HANDOFF_WRONG_REDMITV_MODEL' }
$target = '/sdcard/Download/TTV-' + $slug + '-' + $expected.Substring(0,12) + '.srt'
# Re-running the same SHA command is idempotent; no APK or app data touched.
$existing = Invoke-AdbSafe -CommandArgs @('-s',$serial,'shell','sha256sum',$target)
if ($existing.Code -eq 0) {
    $seen = [regex]::Match([string]$existing.Out, '^([a-fA-F0-9]{64})\s')
    if (-not $seen.Success) { throw 'TTV_HANDOFF_EXISTING_HASH_UNREADABLE' }
    if ($seen.Groups[1].Value.ToLowerInvariant() -cne $expected) { throw 'TTV_HANDOFF_EXISTING_FILE_DIFFERS' }
    Write-Host 'TTV_HANDOFF_ALREADY_ON_REDMITV_SHA_PASS'
    exit 0
}
$push = Invoke-AdbSafe -CommandArgs @('-s',$serial,'push',$source,$target)
if ($push.Code -ne 0) { throw 'TTV_HANDOFF_ADB_PUSH_FAILED' }
$remote = Invoke-AdbSafe -CommandArgs @('-s',$serial,'shell','sha256sum',$target)
$remoteHash = [regex]::Match([string]$remote.Out, '^([a-fA-F0-9]{64})\s')
if ($remote.Code -ne 0 -or -not $remoteHash.Success) { throw 'TTV_HANDOFF_REMOTE_HASH_UNAVAILABLE' }
if ($remoteHash.Groups[1].Value.ToLowerInvariant() -cne $expected) { throw 'TTV_HANDOFF_REMOTE_SHA_MISMATCH' }
Write-Host 'TTV_HANDOFF_REPO_TO_REDMITV_SHA_PASS'
Write-Host 'TTV_HANDOFF_OMP_IMPORT_RENDER=NOT_RUN'
Write-Host 'TTV_HANDOFF_SEEK_RESUME=NOT_RUN'
