# Owner-interactive, read-only reconciliation after one-shot P2 clear.
# Export only fixed enums/counts to an existing NETWORK_SERVICE-readable spool.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    throw 'P2_FRESH_INSPECT_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_FRESH_INSPECT_WRONG_OWNER'
}
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$taskState = [string]$task.State
if ($taskState -cnotin @('Running','Ready','Disabled')) {
    throw 'P2_FRESH_INSPECT_UNKNOWN_TASK_STATE'
}
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$archiveRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\ArchivedRetryJobs'
$inbox = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\inbox'
$receiptDir = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts'
$receipt = Join-Path $receiptDir 'receipt.json'
if (-not (Test-Path -LiteralPath $stateRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $receiptDir -PathType Container) -or
    -not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    throw 'P2_FRESH_INSPECT_INPUT_MISSING'
}
$abandoned = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'batch-*.abandoned.json' -Recurse)
$inflight = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse)
$locks = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'active.lock' -Recurse)
$pending = if (Test-Path -LiteralPath $inbox -PathType Container) {
    @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
} else { @() }
$archives = if (Test-Path -LiteralPath $archiveRoot -PathType Container) {
    @(Get-ChildItem -LiteralPath $archiveRoot -Directory -Filter 'approved-fresh-*')
} else { @() }
$previous = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
$phase = 'UNKNOWN_PRIVATE_FAILURE'
if ($previous.operation -ceq 'owner-p2-fresh-start' -and
    $previous.result -ceq 'FAILED_NO_RETRY' -and
    [string]$previous.nonce -cmatch '^[0-9a-f]{32}$') {
    $privateLog = Join-Path $env:LOCALAPPDATA (
        'TorrentTVVietsub\LaptopHostOps\run-' + $previous.nonce + '\full-owner-output.log')
    if (Test-Path -LiteralPath $privateLog -PathType Leaf) {
        $item = Get-Item -LiteralPath $privateLog -Force
        if ($item.Length -gt 0 -and $item.Length -le 1048576 -and
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $log = Get-Content -LiteralPath $privateLog -Raw
            if ($log -match 'P2_FRESH_START_OLD_JOB=ARCHIVED_RECOVERABLY') {
                $phase = 'ARCHIVED_BEFORE_FAILURE'
            } elseif ($log -match 'P2_FRESH_START_PREFLIGHT=EXACT_QUARANTINED_JOB_IDLE') {
                $phase = 'PREFLIGHT_PASSED_BEFORE_FAILURE'
            } elseif ($log -match 'P2_FRESH_START_OWNER_TASK_CONTRACT_HOLD') {
                $phase = 'TASK_NOT_RUNNING_BEFORE_CLEAR'
            } elseif ($log -match 'P2_FRESH_START_INSTALLED_WORKER_DRIFT') {
                $phase = 'INSTALLED_WORKER_MISMATCH'
            } elseif ($log -match 'P2_FRESH_START_QUARANTINE_LEDGER_MISMATCH') {
                $phase = 'LEDGER_MISMATCH'
            } elseif ($log -match 'P2_FRESH_START_') {
                $phase = 'OTHER_NAMED_PREFLIGHT_HOLD'
            }
        }
    }
}
$record = [ordered]@{
    schema = 'TTV-P2-FRESH-INSPECT-V1'
    utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    task_state = $taskState.ToUpperInvariant()
    prior_phase = $phase
    abandoned_count = [int]$abandoned.Count
    archived_count = [int]$archives.Count
    inflight_count = [int]$inflight.Count
    lock_count = [int]$locks.Count
    pending_count = [int]$pending.Count
}
$out = Join-Path $receiptDir 'p2-fresh-inspect.json'
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress))
if ($bytes.Length -gt 512) { throw 'P2_FRESH_INSPECT_RECEIPT_TOO_LARGE' }
$temp = $out + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllBytes($temp, $bytes)
[IO.File]::Move($temp, $out, $true)
Write-Output 'P2_FRESH_INSPECT=SANITIZED_RECEIPT_WRITTEN'
Write-Output 'P2_FRESH_INSPECT_PRIVATE_LOG=NOT_EXPORTED'
