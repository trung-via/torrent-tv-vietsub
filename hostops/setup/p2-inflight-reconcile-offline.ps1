# Owner-private P2 unknown-effect reconciliation. Read-only by default.
# Acknowledged quarantine requires a disabled Owner task, no Owner worker,
# no inbox event, no active lock, and an exact marker SHA-256 match.
# No model call, secret read, deletion, restart or GitHub operation.
[CmdletBinding()]
param(
    [switch]$ApplyQuarantine,
    [switch]$AcknowledgeUnknownEffect,
    [string]$ExpectedMarkerSha256 = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'P2_RECONCILE_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_RECONCILE_WRONG_WINDOWS_OWNER'
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$inbox = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\inbox'
if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) {
    throw 'P2_RECONCILE_STATE_ROOT_MISSING'
}
function Assert-Regular([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'P2_RECONCILE_REPARSE_POINT_REFUSED'
    }
    return $item
}
Assert-Regular $stateRoot | Out-Null
$markers = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse)
Write-Host ('P2_RECONCILE_INFLIGHT_COUNT=' + $markers.Count)
if ($markers.Count -ne 1) {
    throw 'P2_RECONCILE_EXACTLY_ONE_MARKER_REQUIRED'
}
$marker = $markers[0]
Assert-Regular $marker.DirectoryName | Out-Null
Assert-Regular $marker.FullName | Out-Null
$markerMatch = [regex]::Match($marker.Name, '^batch-([0-9]{4})\.inflight$')
if (-not $markerMatch.Success -or
    $marker.Directory.Name -cnotmatch '^[0-9a-f]{64}$') {
    throw 'P2_RECONCILE_MARKER_PATH_INVALID'
}
$version = [int]$markerMatch.Groups[1].Value
if ($version -lt 1 -or $marker.Length -gt 4096) {
    throw 'P2_RECONCILE_MARKER_VERSION_OR_SIZE_INVALID'
}
$digest = $marker.Directory.Name
try {
    $doc = Get-Content -LiteralPath $marker.FullName -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
} catch {
    throw 'P2_RECONCILE_MARKER_JSON_INVALID'
}
if ($doc.schema -cne 'TTV-P2-INFLIGHT-V1' -or
    $doc.job -cne $digest -or
    ($doc.version -isnot [int] -and $doc.version -isnot [long]) -or
    $doc.version -ne $version -or
    @($doc.PSObject.Properties.Name).Count -ne 3) {
    throw 'P2_RECONCILE_MARKER_SCHEMA_INVALID'
}
$checkpoint = [IO.Path]::ChangeExtension($marker.FullName, '.json')
$lock = Join-Path $marker.DirectoryName 'active.lock'
$ledger = Join-Path $marker.DirectoryName ('batch-{0:0000}.abandoned.json' -f $version)
$quarantine = Join-Path $marker.DirectoryName ('batch-{0:0000}.quarantined' -f $version)
$markerSha = (Get-FileHash -LiteralPath $marker.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$hasCheckpoint = Test-Path -LiteralPath $checkpoint
$hasLock = Test-Path -LiteralPath $lock
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
$workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('py.exe', 'python.exe', 'pythonw.exe') -and
    $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
$pending = @()
if (Test-Path -LiteralPath $inbox -PathType Container) {
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$reviewedWorker = Join-Path $repo 'poc\p2-aisub\automatic_lean120_worker.py'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installedWorker = Join-Path $ownerRoot 'app\poc\p2-aisub\automatic_lean120_worker.py'
$installedWorkerMatch = $false
if ((Test-Path -LiteralPath $reviewedWorker -PathType Leaf) -and
    (Test-Path -LiteralPath $installedWorker -PathType Leaf)) {
    Assert-Regular $installedWorker | Out-Null
    $installedWorkerMatch = (Get-FileHash -LiteralPath $reviewedWorker -Algorithm SHA256).Hash -ceq
        (Get-FileHash -LiteralPath $installedWorker -Algorithm SHA256).Hash
}
Write-Host ('P2_RECONCILE_BATCH=' + $marker.BaseName)
Write-Host ('P2_RECONCILE_MARKER_SHA256=' + $markerSha)
Write-Host ('P2_RECONCILE_CHECKPOINT_PRESENT=' + $hasCheckpoint)
Write-Host ('P2_RECONCILE_ACTIVE_LOCK_PRESENT=' + $hasLock)
Write-Host ('P2_RECONCILE_TASK_STATE=' + [string]$task.State)
Write-Host ('P2_RECONCILE_OWNER_WORKERS=' + $workers.Count)
Write-Host ('P2_RECONCILE_PENDING_EVENTS=' + $pending.Count)
Write-Host ('P2_RECONCILE_INSTALLED_NO_RETRY_WORKER_MATCH=' + $installedWorkerMatch)

if (-not $ApplyQuarantine) {
    Write-Host 'P2_RECONCILE_RESULT=INSPECT_ONLY_NO_CHANGES'
    return
}
if (-not $AcknowledgeUnknownEffect -or
    $ExpectedMarkerSha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
    $markerSha -cne $ExpectedMarkerSha256.ToLowerInvariant()) {
    throw 'P2_RECONCILE_EXPLICIT_ACK_AND_EXACT_HASH_REQUIRED'
}
if ([string]$task.State -cne 'Disabled' -or $workers.Count -ne 0 -or
    $pending.Count -ne 0 -or $hasLock -or $hasCheckpoint) {
    throw 'P2_RECONCILE_OFFLINE_OR_CHECKPOINT_HOLD'
}
if (-not $installedWorkerMatch) {
    # Old deployed Worker versions ignore tombstones; moving their marker
    # could silently retry the same potentially billable batch on restart.
    throw 'P2_RECONCILE_DEPLOYED_NO_RETRY_WORKER_REQUIRED'
}
$guards = Join-Path $repo 'poc\p2-sub-discovery'
. (Join-Path $guards 'owner-task-principal-identity.ps1')
. (Join-Path $guards 'owner-task-action-identity.ps1')
$launcher = Join-Path $ownerRoot 'start-owner-session-agent.ps1'
if (-not (Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $identity.User.Value) -or
    -not (Get-TTVOwnerTaskActionState -Task $task `
        -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) `
        -ExpectedLauncher $launcher).Accepted) {
    throw 'P2_RECONCILE_TASK_IDENTITY_MISMATCH'
}
if ((Test-Path -LiteralPath $ledger) -or (Test-Path -LiteralPath $quarantine)) {
    throw 'P2_RECONCILE_EXISTING_LEDGER_OR_ARCHIVE_HOLD'
}

# Commit a no-retry tombstone FIRST. Any crash before the subsequent rename
# leaves a safe hold, never an unguarded automatic replay.
$receipt = @{
    schema = 'TTV-P2-ABANDONED-UNKNOWN-EFFECT-V1'
    job = $digest
    version = $version
    marker_sha256 = $markerSha
    result = 'UNKNOWN_EFFECT_NO_RETRY'
    acknowledged_utc = [DateTime]::UtcNow.ToString('o')
} | ConvertTo-Json -Compress
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($receipt)
$stream = [IO.FileStream]::new($ledger, [IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
} finally {
    $stream.Dispose()
}
if ((Get-FileHash -LiteralPath $marker.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $markerSha) {
    throw 'P2_RECONCILE_MARKER_CHANGED_AFTER_LEDGER_HOLD'
}
[IO.File]::Move($marker.FullName, $quarantine)
if ((Get-FileHash -LiteralPath $quarantine -Algorithm SHA256).Hash.ToLowerInvariant() -cne $markerSha) {
    throw 'P2_RECONCILE_ARCHIVE_HASH_MISMATCH'
}
Write-Host 'P2_RECONCILE_RESULT=UNKNOWN_EFFECT_QUARANTINED_NO_RETRY'
Write-Host 'P2_RECONCILE_ORIGINAL_MARKER_BYTES=PRESERVED'
Write-Host 'P2_RECONCILE_OWNER_TASK=NOT_STARTED'
