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
    # A missing receipt does not mean enrollment is missing. The Owner writer
    # may simply not be installed/running yet; classify the directory/ACL
    # independently so an owner is not asked to repeat a completed UAC step.
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        Write-Output 'HOSTOPS_OWNER_DIAG_ENROLLMENT=HOSTOPS_SETUP_REQUIRED'
    } else {
        $directory = Get-Item -LiteralPath $root -Force -ErrorAction Stop
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'HOSTOPS_OWNER_DIAG_REPARSE_PATH_BLOCKED'
        }
        $enrollment = 'READ_GRANT_NOT_VERIFIED'
        try {
            $acl = Get-Acl -LiteralPath $root -ErrorAction Stop
            $mask = [Security.AccessControl.FileSystemRights]::ReadAndExecute
            $rules = $acl.GetAccessRules(
                $true, $false, [Security.Principal.SecurityIdentifier])
            foreach ($rule in $rules) {
                if ($rule.IdentityReference.Value -ceq 'S-1-5-20' -and
                    $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                    ($rule.FileSystemRights -band $mask) -eq $mask) {
                    $enrollment = 'READ_GRANT_VERIFIED'
                    break
                }
            }
        } catch {
            $enrollment = 'ACL_READ_UNAVAILABLE'
        }
        Write-Output "HOSTOPS_OWNER_DIAG_ENROLLMENT=$enrollment"
    }
    Write-Output 'HOSTOPS_OWNER_WRITER=NOT_OBSERVED'
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
if ($item.Length -le 0 -or $item.Length -gt 4096) {
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
$p2Fields = @('status','pending_events','inflight_count','batch',
    'marker_sha256','checkpoint_present','active_lock_present',
    'installed_no_retry_worker_match')
$isV2 = $report.schema -ceq 'TTV-HOSTOPS-OWNER-SNAPSHOT-V2'
if ($isV2) { $fields += 'p2' }
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
if ($report.schema -cnotin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V1',
                             'TTV-HOSTOPS-OWNER-SNAPSHOT-V2') -or
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
# V1 receipts from previously installed Owners remain readable. Only the new
# V2 exact-schema P2 observation is emitted, never the Owner-private marker.
if ($isV2) {
    if (-not $report.p2 -or
        (@($report.p2.PSObject.Properties.Name | Sort-Object) -join ',') -cne
            (@($p2Fields | Sort-Object) -join ',')) {
        throw 'HOSTOPS_OWNER_P2_INVALID_FIELDS'
    }
    if ($report.p2.status -cnotin @('READ_UNAVAILABLE','STATE_MISSING',
                                   'CLEAR','MULTIPLE_HOLD','INVALID_MARKER',
                                   'UNKNOWN_EFFECT_HOLD') -or
        $report.p2.batch -isnot [string] -or
        $report.p2.marker_sha256 -isnot [string] -or
        $report.p2.checkpoint_present -cnotin @('YES','NO','NOT_OBSERVED') -or
        $report.p2.active_lock_present -cnotin @('YES','NO','NOT_OBSERVED') -or
        $report.p2.installed_no_retry_worker_match -cnotin @('YES','NO','NOT_OBSERVED')) {
        throw 'HOSTOPS_OWNER_P2_INVALID_ENUM'
    }
    foreach ($field in @('pending_events','inflight_count')) {
        $count = $report.p2.$field
        if (($count -isnot [int] -and $count -isnot [long]) -or
            $count -lt -1 -or $count -gt 10001) {
            throw 'HOSTOPS_OWNER_P2_INVALID_COUNTER'
        }
    }
    if ($report.p2.status -ceq 'UNKNOWN_EFFECT_HOLD') {
        if ($report.p2.batch -cnotmatch '^batch-[0-9]{4}$' -or
            $report.p2.marker_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $report.p2.inflight_count -ne 1 -or
            $report.p2.checkpoint_present -cnotin @('YES','NO') -or
            $report.p2.active_lock_present -cnotin @('YES','NO')) {
            throw 'HOSTOPS_OWNER_P2_HOLD_CONTRACT_INVALID'
        }
    } elseif ($report.p2.batch -cne 'NOT_OBSERVED' -or
              $report.p2.marker_sha256 -cne 'NOT_OBSERVED' -or
              $report.p2.checkpoint_present -cne 'NOT_OBSERVED' -or
              $report.p2.active_lock_present -cne 'NOT_OBSERVED') {
        throw 'HOSTOPS_OWNER_P2_INACTIVE_CONTRACT_INVALID'
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
    $report.torrserver = 'UNTESTED'
    $report.ingress_instrumented = 'NOT_OBSERVED'
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
# Missing/stale Owner data and old V1 writers report NOT_OBSERVED, never zero.
if ($isV2 -and $status -ceq 'READY_FRESH') {
    Write-Output "HOSTOPS_OWNER_P2_STATUS=$($report.p2.status)"
    Write-Output "HOSTOPS_OWNER_P2_PENDING_EVENTS=$($report.p2.pending_events)"
    Write-Output "HOSTOPS_OWNER_P2_INFLIGHT_COUNT=$($report.p2.inflight_count)"
    Write-Output "HOSTOPS_OWNER_P2_BATCH=$($report.p2.batch)"
    Write-Output "HOSTOPS_OWNER_P2_MARKER_SHA256=$($report.p2.marker_sha256)"
    Write-Output "HOSTOPS_OWNER_P2_CHECKPOINT_PRESENT=$($report.p2.checkpoint_present)"
    Write-Output "HOSTOPS_OWNER_P2_ACTIVE_LOCK_PRESENT=$($report.p2.active_lock_present)"
    Write-Output "HOSTOPS_OWNER_P2_INSTALLED_NO_RETRY_WORKER_MATCH=$($report.p2.installed_no_retry_worker_match)"
} else {
    Write-Output 'HOSTOPS_OWNER_P2_STATUS=NOT_OBSERVED'
    Write-Output 'HOSTOPS_OWNER_P2_INFLIGHT_COUNT=-1'
    Write-Output 'HOSTOPS_OWNER_P2_PENDING_EVENTS=-1'
}
Write-Output 'HOSTOPS_OWNER_PRIVATE_DATA=NOT_ACCESSED'
Write-Output 'HOSTOPS_OWNER_PROVIDER_OR_TV=NOT_RUN'
Write-Output 'HOSTOPS_OWNER_DIAG=READ_ONLY_COMPLETE'
