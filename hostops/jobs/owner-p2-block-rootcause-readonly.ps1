# Fixed, read-only consumer of the Owner-private P2 root-cause classifier.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'P2_ROOTCAUSE_READER_TRUSTED_RUNNER_REQUIRED'
}
$file = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts\p2-block-rootcause-v1.json'
$item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
if ($item.Length -le 0 -or $item.Length -gt 512 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P2_ROOTCAUSE_READER_INVALID_FILE'
}
$report = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($report.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'batch1_file,batch2_file,last_block_code,log_block_seen,marker_batch,marker_count,phase,schema,status,task_state,utc_epoch' -or
    $report.schema -cne 'TTV-P2-BLOCK-ROOTCAUSE-V1' -or
    $report.status -cnotin @('OBSERVED','HOLD') -or
    $report.phase -cnotin @('IDENTITY','TASK','MARKER','LOG','COMPLETE') -or
    $report.task_state -cnotin @('Running','Ready','Disabled','UNKNOWN') -or
    $report.marker_batch -cnotin @('UNKNOWN','BATCH_0002') -or
    $report.batch1_file -cnotin @('UNKNOWN','YES','NO') -or
    $report.batch2_file -cnotin @('UNKNOWN','YES','NO') -or
    $report.log_block_seen -cnotin @('UNKNOWN','YES','NO') -or
    $report.last_block_code -cnotmatch '^(UNKNOWN|UNCLASSIFIED|AGY_[A-Z0-9_]+|AUTO_LEAN120_[A-Z0-9_]+|LEAN120_[A-Z0-9_]+|P4_ROLLING_[A-Z0-9_]+)$' -or
    $report.marker_count -isnot [ValueType] -or
    $report.marker_count -lt -1 -or $report.marker_count -gt 10000) {
    throw 'P2_ROOTCAUSE_READER_INVALID_SCHEMA'
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$report.utc_epoch
if ($age -lt 0 -or $age -gt 180) { throw 'P2_ROOTCAUSE_READER_STALE' }
Write-Output ('P2_ROOTCAUSE_STATUS=' + $report.status)
Write-Output ('P2_ROOTCAUSE_PHASE=' + $report.phase)
Write-Output ('P2_ROOTCAUSE_TASK=' + $report.task_state)
Write-Output ('P2_ROOTCAUSE_MARKER_COUNT=' + $report.marker_count)
Write-Output ('P2_ROOTCAUSE_MARKER_BATCH=' + $report.marker_batch)
Write-Output ('P2_ROOTCAUSE_BATCH1_FILE=' + $report.batch1_file)
Write-Output ('P2_ROOTCAUSE_BATCH2_FILE=' + $report.batch2_file)
Write-Output ('P2_ROOTCAUSE_LOG_BLOCK_SEEN=' + $report.log_block_seen)
Write-Output ('P2_ROOTCAUSE_LAST_BLOCK_CODE=' + $report.last_block_code)
Write-Output 'P2_ROOTCAUSE_PRIVATE_DATA=NOT_READ_BY_RUNNER'
