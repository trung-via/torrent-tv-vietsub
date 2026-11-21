# Sanitized ProgramData receipt only. Never opens Owner profile or logs.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'P2_FRESH_READER_TRUSTED_HOSTOPS_REQUIRED'
}
$path = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts\p2-fresh-inspect.json'
$item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
if ($item.Length -le 0 -or $item.Length -gt 512 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P2_FRESH_READER_INVALID_FILE'
}
$report = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($report.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'abandoned_count,archived_count,inflight_count,lock_count,pending_count,prior_phase,schema,task_state,utc_epoch' -or
    $report.schema -cne 'TTV-P2-FRESH-INSPECT-V1' -or
    $report.task_state -cnotin @('RUNNING','READY','DISABLED') -or
    $report.prior_phase -cnotin @('UNKNOWN_PRIVATE_FAILURE','ARCHIVED_BEFORE_FAILURE',
        'PREFLIGHT_PASSED_BEFORE_FAILURE','TASK_NOT_RUNNING_BEFORE_CLEAR',
        'INSTALLED_WORKER_MISMATCH','LEDGER_MISMATCH','OTHER_NAMED_PREFLIGHT_HOLD')) {
    throw 'P2_FRESH_READER_INVALID_SCHEMA'
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$report.utc_epoch
if ($age -lt 0 -or $age -gt 120) { throw 'P2_FRESH_READER_STALE' }
foreach ($field in @('abandoned_count','archived_count','inflight_count',
                     'lock_count','pending_count')) {
    if ($report.$field -isnot [ValueType] -or
        [long]$report.$field -lt 0 -or [long]$report.$field -gt 1000000) {
        throw 'P2_FRESH_READER_INVALID_COUNTER'
    }
}
Write-Output ('P2_FRESH_INSPECT_TASK=' + $report.task_state)
Write-Output ('P2_FRESH_INSPECT_PREVIOUS_PHASE=' + $report.prior_phase)
Write-Output ('P2_FRESH_INSPECT_ABANDONED=' + $report.abandoned_count)
Write-Output ('P2_FRESH_INSPECT_ARCHIVED=' + $report.archived_count)
Write-Output ('P2_FRESH_INSPECT_INFLIGHT=' + $report.inflight_count)
Write-Output ('P2_FRESH_INSPECT_PENDING=' + $report.pending_count)
Write-Output ('P2_FRESH_INSPECT_LOCK=' + $report.lock_count)
Write-Output 'P2_FRESH_INSPECT_PRIVATE_DATA=NOT_ACCESSED_BY_RUNNER'
