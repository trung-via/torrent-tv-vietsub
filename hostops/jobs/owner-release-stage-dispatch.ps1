# Trusted owner-comment /tv-hostops run <exact branch SHA> owner-release-stage-dispatch.
# NETWORK_SERVICE writes ONLY a bounded ProgramData request, then starts the
# pre-enrolled fixed Owner-session STAGE-ONLY task. Never writes Owner-private
# source, changes the main Owner Task, calls AI/provider, or touches TV.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'HOSTOPS_OWNER_RELEASE_TRUSTED_RUNNER_REQUIRED'
}
$commit = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -cnotmatch '\A[0-9a-f]{40}\z') {
    throw 'HOSTOPS_OWNER_RELEASE_PIN_INVALID'
}
$manifestRel = 'hostops/releases/owner-p4-v4-stage-v1.json'
$manifestFile = Join-Path $env:GITHUB_WORKSPACE ($manifestRel.Replace('/', '\'))
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) {
    throw 'HOSTOPS_OWNER_RELEASE_MANIFEST_MISSING'
}
# Read exact Git bytes through binary stdout, independent of checkout filters.
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'git.exe'
$psi.Arguments = 'show HEAD:' + $manifestRel
$psi.WorkingDirectory = $env:GITHUB_WORKSPACE
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($psi)
$stream = [IO.MemoryStream]::new()
try {
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0 -or $stream.Length -le 0 -or
        $stream.Length -gt 8192) {
        throw 'HOSTOPS_OWNER_RELEASE_MANIFEST_GIT_BLOB_UNAVAILABLE'
    }
    $exactBlob = $stream.ToArray()
} finally { $stream.Dispose(); $process.Dispose() }
$hasher = [Security.Cryptography.SHA256]::Create()
try {
    $manifestHash = [BitConverter]::ToString($hasher.ComputeHash($exactBlob)).Replace('-','').ToLowerInvariant()
} finally { $hasher.Dispose() }
if ($manifestHash -cnotmatch '\A[0-9a-f]{64}\z') {
    throw 'HOSTOPS_OWNER_RELEASE_MANIFEST_HASH_INVALID'
}
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
    $manifest.release_id -cne 'p4-native-178-v4' -or
    $manifest.mode -cne 'STAGE_ONLY') {
    throw 'HOSTOPS_OWNER_RELEASE_MANIFEST_SCOPE_INVALID'
}

$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Owner-Release-Stage' -TaskPath '\' `
    -ErrorAction SilentlyContinue
if ($null -eq $task) {
    Write-Output 'HOSTOPS_OWNER_RELEASE=HOSTOPS_SETUP_REQUIRED'
    throw 'HOSTOPS_OWNER_RELEASE_TASK_NOT_ENROLLED'
}
if ([string]$task.State -cne 'Ready' -or
    [string]$task.Description -cne 'TTV_OWNER_HOSTOPS_RELEASE_STAGE_ONLY_V1' -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    $null -ne $task.Triggers -and @($task.Triggers).Count -ne 0 -or
    @($task.Actions).Count -ne 1) {
    throw 'HOSTOPS_OWNER_RELEASE_TASK_DRIFT'
}
function SidOf([string]$id) {
    if ($id -match '^S-\d+(?:-\d+){2,}$') { return $id }
    return ([Security.Principal.NTAccount]::new($id).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ((SidOf ([string]$task.Principal.UserId)) -cne
    (SidOf ([string]$owner.Principal.UserId))) {
    throw 'HOSTOPS_OWNER_RELEASE_OWNER_IDENTITY_DRIFT'
}
$action = @($task.Actions)[0]
if (-not [IO.Path]::GetFileName([string]$action.Execute).Equals('pwsh.exe',
        [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace([string]$action.WorkingDirectory) -or
    [string]$action.Arguments -cnotmatch
        '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-release-stage-helper\.ps1"\z') {
    throw 'HOSTOPS_OWNER_RELEASE_TASK_ACTION_DRIFT'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge'
$inbox = Join-Path $spool 'ReleaseRequests'
$outbox = Join-Path $spool 'ReleaseReceipts'
foreach ($folder in @($inbox,$outbox)) {
    if (-not (Test-Path -LiteralPath $folder -PathType Container) -or
        ((Get-Item -LiteralPath $folder -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'HOSTOPS_OWNER_RELEASE_SPOOL_NOT_ENROLLED'
    }
}
$requestFile = Join-Path $inbox 'request.json'
$receiptFile = Join-Path $outbox 'stage.json'
if (Test-Path -LiteralPath $requestFile) {
    # Never overwrite an unresolved request; otherwise a dispatched but
    # unobserved Owner task could be induced to stage a different release.
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) {
        throw 'HOSTOPS_OWNER_RELEASE_PREVIOUS_REQUEST_UNRESOLVED'
    }
    $previous = Get-Content -LiteralPath $requestFile -Raw | ConvertFrom-Json
    $previousReceipt = Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
    if ($previous.schema -cne 'TTV-OWNER-RELEASE-STAGE-REQUEST-V1' -or
        $previousReceipt.schema -cne 'TTV-OWNER-RELEASE-STAGE-RECEIPT-V1' -or
        $previous.nonce -cne $previousReceipt.nonce -or
        $previous.source_commit -cne $previousReceipt.source_commit -or
        $previousReceipt.result -cne 'STAGED_VERIFIED_INSTALLED_UNCHANGED') {
        throw 'HOSTOPS_OWNER_RELEASE_PREVIOUS_REQUEST_UNRESOLVED'
    }
}
$nonce = [Guid]::NewGuid().ToString('N')
$request = [ordered]@{
    schema = 'TTV-OWNER-RELEASE-STAGE-REQUEST-V1'
    source_commit = $commit
    manifest_path = $manifestRel
    manifest_sha256 = $manifestHash
    nonce = $nonce
    requested_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($request | ConvertTo-Json -Compress))
if ($bytes.Length -gt 512) { throw 'HOSTOPS_OWNER_RELEASE_REQUEST_OVER_LIMIT' }
$temp = Join-Path $inbox ('request-' + $nonce + '.tmp')
$stream = [IO.File]::Open($temp,[IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush($true)
} finally { $stream.Dispose() }
Move-Item -LiteralPath $temp -Destination $requestFile -Force -ErrorAction Stop
Start-ScheduledTask -TaskName 'TorrentTV-Vietsub-Owner-Release-Stage' -TaskPath '\' `
    -ErrorAction Stop
Write-Output 'HOSTOPS_OWNER_RELEASE=TASK_TRIGGERED_NOT_YET_VERIFIED'
for ($i=0;$i -lt 70;$i++) {
    Start-Sleep -Seconds 1
    $state = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Owner-Release-Stage' -TaskPath '\'
    if ([string]$state.State -cne 'Ready' -or
        -not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { continue }
    $receiptItem = Get-Item -LiteralPath $receiptFile -Force
    if ($receiptItem.Length -le 0 -or $receiptItem.Length -gt 512 -or
        ($receiptItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw | ConvertFrom-Json
    if ($receipt.schema -cne 'TTV-OWNER-RELEASE-STAGE-RECEIPT-V1' -or
        $receipt.nonce -cne $nonce -or
        $receipt.source_commit -cne $commit) { continue }
    if ($receipt.result -cne 'STAGED_VERIFIED_INSTALLED_UNCHANGED') {
        throw 'HOSTOPS_OWNER_RELEASE_OWNER_TASK_HOLD_NO_INSTALL'
    }
    Write-Output 'HOSTOPS_OWNER_RELEASE=STAGED_VERIFIED_INSTALLED_UNCHANGED'
    Write-Output 'HOSTOPS_OWNER_RELEASE_OWNER_AGENT=NOT_RESTARTED'
    Write-Output 'HOSTOPS_OWNER_RELEASE_PROVIDER_TV=NOT_RUN'
    Write-Output 'HOSTOPS_OWNER_RELEASE_LIVE_R2=NOT_INSTALLED'
    return
}
throw 'HOSTOPS_OWNER_RELEASE_TRIGGERED_NOT_VERIFIED_NO_RETRY'
