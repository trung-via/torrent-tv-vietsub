# Read-only post-attempt classification. Run as dedicated Torrent TV HostOps
# NETWORK_SERVICE, not as the private Windows Owner. No re-trigger or replay.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-Owner-P2-Batch15-FreshStart'
$ownerTaskName = 'TorrentTV-Vietsub-OwnerAgent'
$receipt = Join-Path $env:ProgramData `
    'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\p2-batch15-fresh-start.json'
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$owner = Get-ScheduledTask -TaskName $ownerTaskName -TaskPath '\' -ErrorAction Stop
if ($task.Description -cne 'TTV_OWNER_P2_BATCH15_FRESH_START_ONCE_20261121' -or
    @($task.Actions).Count -ne 1 -or
    [IO.Path]::GetFileName([string]$task.Actions[0].Execute) -ine 'pwsh.exe') {
    throw 'HOSTOPS_P2_POSTMORTEM_TASK_IDENTITY_DRIFT'
}
Write-Output 'HOSTOPS_P2_POSTMORTEM=READ_ONLY'
Write-Output ('HOSTOPS_P2_POSTMORTEM_TASK_STATE=' + [string]$task.State)
Write-Output ('HOSTOPS_P2_POSTMORTEM_TASK_LAST_RESULT=' + [int64]$info.LastTaskResult)
Write-Output ('HOSTOPS_P2_POSTMORTEM_TASK_PREVIOUS_RUN=' + $(if (
    $info.LastRunTime -ge [datetime]'2000-01-01') { 'YES' } else { 'NO' }))
Write-Output ('HOSTOPS_P2_POSTMORTEM_OWNER_TASK_STATE=' + [string]$owner.State)
if (Test-Path -LiteralPath $receipt -PathType Leaf) {
    $file = Get-Item -LiteralPath $receipt -Force -ErrorAction Stop
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint -or
        $file.Length -gt 1024) { throw 'HOSTOPS_P2_POSTMORTEM_RECEIPT_INVALID' }
    $r = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if ($r.schema -cne 'TTV-OWNER-P2-BATCH15-FRESH-START-V1' -or
        $r.batch -cne 'batch-0015' -or
        $r.result -notin @('STARTED_NO_PROVIDER_REPLAY',
            'PRIVATE_ARCHIVE_COMPLETE_OWNER_STOPPED',
            'ARCHIVED_OWNER_RESTARTED_WAIT_NEW_VIEWER_REQUEST',
            'HOLD_OWNER_DISABLED_RECOVERY_PRESERVED')) {
        throw 'HOSTOPS_P2_POSTMORTEM_RECEIPT_SCHEMA_INVALID'
    }
    Write-Output ('HOSTOPS_P2_POSTMORTEM_RECEIPT=' + [string]$r.result)
} else {
    Write-Output 'HOSTOPS_P2_POSTMORTEM_RECEIPT=ABSENT'
}
Write-Output 'HOSTOPS_P2_POSTMORTEM_PRIVATE_MEDIA=NOT_ACCESSED'
Write-Output 'HOSTOPS_P2_POSTMORTEM_PROVIDER_TV=NOT_RUN'
