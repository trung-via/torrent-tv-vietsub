# R0 #174 — fixed, read-only owner-produced sanitized receipt consumer.
# Run only via trusted owner-comment /tv-hostops run <sha> owner-diagnostic-snapshot.
# The NetworkService runner never opens the Owner profile, DPAPI or movie queue.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'HOSTOPS_OWNER_DIAG_TRUSTED_SERVICE_RUNNER_REQUIRED'
}

$taskState = 'UNKNOWN'
try {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    $taskState = if ($task.State.ToString() -ceq 'Running') { 'RUNNING' } else { 'NOT_RUNNING' }
} catch {
    $taskState = 'UNKNOWN'
}
Write-Output "HOSTOPS_OWNER_TASK_STATE=$taskState"

$root = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics'
$file = Join-Path $root 'owner-snapshot.json'
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Write-Output 'HOSTOPS_OWNER_SNAPSHOT_STATUS=MISSING'
    Write-Output 'HOSTOPS_OWNER_DIAG_ENROLLMENT=HOSTOPS_SETUP_REQUIRED'
    Write-Output 'HOSTOPS_OWNER_PRIVATE_DATA=NOT_ACCESSED'
    Write-Output 'HOSTOPS_OWNER_PROVIDER_OR_TV=NOT_RUN'
    return
}
foreach ($path in @($root, $file)) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'HOSTOPS_OWNER_DIAG_REPARSE_PATH_BLOCKED'
    }
}
$item = Get-Item -LiteralPath $file -Force
if ($item.Length -le 0 -or $item.Length -gt 3072) {
    throw 'HOSTOPS_OWNER_DIAG_INVALID_SIZE'
}
try {
    $report = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
} catch {
    throw 'HOSTOPS_OWNER_DIAG_INVALID_JSON'
}
$fields = @('schema','status','snapshot_utc_epoch','owner_observed_utc_epoch',
    'owner_snapshot_age_seconds','mode','version','heartbeat','p3_state',
    'torrserver','ingress_instrumented','ingress')
$ingressFields = @('state_accepted','state_rejected','selection_dispatched',
    'selection_skipped','selection_rejected','selection_rejected_bad_wire',
    'selection_rejected_current_tv_or_torrserver_unavailable',
    'selection_rejected_media_mismatch','selection_rejected_owner_policy',
    'selection_rejected_enqueue','selection_rejected_http_format',
    'selection_rejected_unknown','state_rejected_auth','state_rejected_clock',
    'state_rejected_replay','state_rejected_format','state_rejected_other')
if (-not $report -or -not $report.PSObject -or
    (@($report.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($fields | Sort-Object) -join ',') -or
    -not $report.ingress -or
    (@($report.ingress.PSObject.Properties.Name | Sort-Object) -join ',') -cne
        (@($ingressFields | Sort-Object) -join ',')) {
    throw 'HOSTOPS_OWNER_DIAG_INVALID_FIELDS'
}
$validStatuses = @('MISSING','STALE','PID_MISMATCH','INVALID_SCHEMA',
    'OWNER_NOT_RUNNING','READY_FRESH')
$validP3 = @('FRESH_ON','FRESH_REQUESTED','FRESH_OFF','FRESH_OTHER',
    'FRESH_INACTIVE','STALE','MISSING','UNKNOWN')
$validTs = @('TCP_REACHABLE_METADATA_UNTESTED','TCP_UNREACHABLE',
    'CONFIG_INVALID','UNTESTED')
$validInstrumented = @('YES','NO','NOT_OBSERVED')
if ($report.schema -cne 'TTV-HOSTOPS-OWNER-SNAPSHOT-V1' -or
    $report.status -cnotin $validStatuses -or
    $report.p3_state -cnotin $validP3 -or
    $report.torrserver -cnotin $validTs -or
    $report.ingress_instrumented -cnotin $validInstrumented -or
    $report.mode -cnotin @('INTEGRATED_P3_P4','NOT_OBSERVED') -or
    $report.version -cnotin @('P3P4-INTEGRATED-DIAGNOSTIC-V2-R0','NOT_OBSERVED') -or
    $report.heartbeat -cnotin @('READY_FRESH','NOT_OBSERVED')) {
    throw 'HOSTOPS_OWNER_DIAG_INVALID_ENUM'
}
foreach ($field in @('snapshot_utc_epoch','owner_observed_utc_epoch',
                     'owner_snapshot_age_seconds')) {
    if ($report.$field -isnot [int] -and $report.$field -isnot [long]) {
        throw 'HOSTOPS_OWNER_DIAG_INVALID_EPOCH_TYPE'
    }
}
foreach ($field in $ingressFields) {
    $count = $report.ingress.$field
    if (($count -isnot [int] -and $count -isnot [long]) -or
        $count -lt -1 -or $count -gt 1000000) {
        throw 'HOSTOPS_OWNER_DIAG_INVALID_COUNTER'
    }
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$report.snapshot_utc_epoch
$status = $report.status
if ($age -lt 0 -or $age -gt 10) { $status = 'STALE' }
if ($taskState -ceq 'NOT_RUNNING') { $status = 'OWNER_NOT_RUNNING' }
# A service token may not enumerate the Owner's scheduled task. Report that
# independently; do not mask a genuinely fresh, Owner-written receipt.
if ($status -ceq 'READY_FRESH') {
    if ($report.mode -cne 'INTEGRATED_P3_P4' -or
        $report.heartbeat -cne 'READY_FRESH' -or
        $report.owner_snapshot_age_seconds -lt 0 -or
        $report.owner_snapshot_age_seconds -gt 5 -or
        $report.owner_observed_utc_epoch -le 0) {
        throw 'HOSTOPS_OWNER_DIAG_READY_CONTRACT_INVALID'
    }
} else {
    # Never let obsolete counters look like evidence of the current TV press.
    $report.p3_state = 'UNKNOWN'
    foreach ($field in $ingressFields) { $report.ingress.$field = -1 }
}
Write-Output "HOSTOPS_OWNER_SNAPSHOT_STATUS=$status"
Write-Output "HOSTOPS_OWNER_RECEIPT_AGE_SECONDS=$age"
Write-Output "HOSTOPS_OWNER_P3_STATE=$($report.p3_state)"
Write-Output "HOSTOPS_OWNER_TORRSERVER=$($report.torrserver)"
foreach ($field in @('state_accepted','state_rejected','selection_dispatched',
                     'selection_rejected','selection_skipped',
                     'selection_rejected_media_mismatch',
                     'selection_rejected_current_tv_or_torrserver_unavailable')) {
    Write-Output ("HOSTOPS_OWNER_" + $field.ToUpperInvariant() + '=' + $report.ingress.$field)
}
Write-Output 'HOSTOPS_OWNER_PRIVATE_DATA=NOT_ACCESSED'
Write-Output 'HOSTOPS_OWNER_PROVIDER_OR_TV=NOT_RUN'
Write-Output 'HOSTOPS_OWNER_DIAG=READ_ONLY_COMPLETE'
