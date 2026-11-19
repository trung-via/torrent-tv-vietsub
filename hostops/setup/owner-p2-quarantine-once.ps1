# One-time interactive Owner maintenance, approved for batch-0001 only.
# Never run in GitHub Actions / NETWORK_SERVICE. No provider or TV call.
# Preserves the original marker and leaves the Owner Task DISABLED.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$approvedMarkerSha256 = '302e646ecf30301a9476be737a82f31484c9a25973abedab6da9d6a02999528f'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$sourceCommit = 'cac462c1dd854a7b19fd0eb02018c9bd1aebb7fe'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'OWNER_P2_QUARANTINE_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_P2_QUARANTINE_WRONG_WINDOWS_OWNER'
}

# Rebuild only the small, reviewed offline quarantine dependency tree from
# immutable source. The actual private P2 state is never copied into TEMP.
$sourceRoot = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' + $sourceCommit
$files = [ordered]@{
    'hostops/setup/p2-inflight-reconcile-offline.ps1' = '7121616cf9286776400bb0cbfb6ce970121014688ed0175a348f42d4be10b21d'
    'hostops/setup/owner-p2-snapshot-once.ps1' = '5ea41dfbcddd4b447dc1bf839a3048654e89f1a2c31a6e50fe3945ae70a753f4'
    'poc/p2-aisub/automatic_lean120_worker.py' = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
    'poc/p2-sub-discovery/owner-task-principal-identity.ps1' = '9fd3c43f10cf9694d6ecc396aae6a3e6fc724a51750c7d51a2d287d431f778d9'
    'poc/p2-sub-discovery/owner-task-action-identity.ps1' = 'f3c497123af4d38c806aa631684e0a77fa926285c4d31ccba8d88f802cb27caf'
}
$stage = Join-Path $env:TEMP ('TorrentTV-P2-Quarantine-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -Path $stage -ItemType Directory -ErrorAction Stop)
foreach ($path in $files.Keys) {
    $target = Join-Path $stage $path
    [void](New-Item -Path (Split-Path -Path $target -Parent) -ItemType Directory -Force)
    Invoke-WebRequest -Uri ($sourceRoot + '/' + $path) -OutFile $target -ErrorAction Stop
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if (-not $actual.Equals($files[$path], [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OWNER_P2_QUARANTINE_SOURCE_HASH_MISMATCH'
    }
}

$reconcile = Join-Path $stage 'hostops/setup/p2-inflight-reconcile-offline.ps1'
$snapshot = Join-Path $stage 'hostops/setup/owner-p2-snapshot-once.ps1'

# Inspect using the *same* reviewed implementation that will perform the
# single transaction. Refuse all unexpected marker, Task or worker states.
$inspection = @(& pwsh -NoProfile -File $reconcile)
if ($LASTEXITCODE -ne 0) { throw 'OWNER_P2_QUARANTINE_INSPECTION_FAILED' }
$fields = @{}
foreach ($line in $inspection) {
    if ($line -cmatch '^(P2_RECONCILE_[A-Z0-9_]+)=(.*)$') {
        $fields[$Matches[1]] = $Matches[2]
    }
}
if ($fields['P2_RECONCILE_RESULT'] -cne 'INSPECT_ONLY_NO_CHANGES' -or
    $fields['P2_RECONCILE_INFLIGHT_COUNT'] -cne '1' -or
    $fields['P2_RECONCILE_BATCH'] -cne 'batch-0001' -or
    $fields['P2_RECONCILE_MARKER_SHA256'] -cne $approvedMarkerSha256 -or
    $fields['P2_RECONCILE_CHECKPOINT_PRESENT'] -cne 'False' -or
    $fields['P2_RECONCILE_ACTIVE_LOCK_PRESENT'] -cne 'False' -or
    $fields['P2_RECONCILE_PENDING_EVENTS'] -cne '0' -or
    $fields['P2_RECONCILE_INSTALLED_NO_RETRY_WORKER_MATCH'] -cne 'True' -or
    $fields['P2_RECONCILE_TASK_STATE'] -cne 'Running') {
    throw 'OWNER_P2_QUARANTINE_OWNER_PREFLIGHT_HOLD'
}
Write-Output 'OWNER_P2_QUARANTINE_PREFLIGHT=PASS_NO_CHANGE'

# Disable scheduling before requesting a stop. Any failure after this point
# deliberately leaves the Task disabled: never restart an unknown-effect job.
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
if ($task.State.ToString() -cne 'Running') {
    throw 'OWNER_P2_QUARANTINE_TASK_STATE_DRIFT'
}
Disable-ScheduledTask -TaskName $taskName -ErrorAction Stop | Out-Null
Write-Output 'OWNER_P2_QUARANTINE_TASK=DISABLED'
try {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Start-Sleep -Seconds 3
    $result = @(& pwsh -NoProfile -File $reconcile -ApplyQuarantine `
        -AcknowledgeUnknownEffect -ExpectedMarkerSha256 $approvedMarkerSha256)
    if ($LASTEXITCODE -ne 0 -or
        $result -cnotcontains 'P2_RECONCILE_RESULT=UNKNOWN_EFFECT_QUARANTINED_NO_RETRY' -or
        $result -cnotcontains 'P2_RECONCILE_ORIGINAL_MARKER_BYTES=PRESERVED') {
        throw 'OWNER_P2_QUARANTINE_OFFLINE_TRANSACTION_HOLD'
    }
    Write-Output 'OWNER_P2_QUARANTINE_RESULT=UNKNOWN_EFFECT_QUARANTINED_NO_RETRY'
    Write-Output 'OWNER_P2_QUARANTINE_MARKER_BYTES=PRESERVED'
} catch {
    Write-Output 'OWNER_P2_QUARANTINE_RESULT=HOLD_TASK_LEFT_DISABLED'
    throw
}

# Refresh the existing sanitized ProgramData receipt for trusted HostOps.
# Snapshot failure never reverses the safe tombstone/archive transaction.
try {
    $after = @(& pwsh -NoProfile -File $snapshot)
    if ($LASTEXITCODE -ne 0 -or
        $after -cnotcontains 'OWNER_P2_SNAPSHOT_EXPORT=SUCCESS' -or
        $after -cnotcontains 'OWNER_P2_SNAPSHOT_INFLIGHT_COUNT=0') {
        throw 'OWNER_P2_QUARANTINE_POST_SNAPSHOT_HOLD'
    }
    Write-Output 'OWNER_P2_QUARANTINE_HOSTOPS_SNAPSHOT=EXPORTED'
} catch {
    Write-Output 'OWNER_P2_QUARANTINE_HOSTOPS_SNAPSHOT=NOT_VERIFIED'
}
Write-Output 'OWNER_P2_QUARANTINE_TASK=LEFT_DISABLED_FOR_REVIEWED_RESTART'
Write-Output 'OWNER_P2_QUARANTINE_PROVIDER_OR_TV=NOT_RUN'
