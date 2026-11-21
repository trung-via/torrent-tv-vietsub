# Trusted read-only relay of the Owner-private P2 text-QA install status.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'P2_TEXT_STATUS_READER_TRUSTED_RUNNER_REQUIRED'
}
$file = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts\p2-text-qa-status-v1.json'
$item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
if ($item.Length -le 0 -or $item.Length -gt 512 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P2_TEXT_STATUS_READER_FILE_UNTRUSTED'
}
$record = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($record.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'active_locks,bridge,bridge_sha16,gateway,last_install_code,marker_count,owner_health,pending_events,phase,schema,status,task,utc_epoch' -or
    $record.schema -cne 'TTV-P2-TEXT-QA-STATUS-V1' -or
    $record.status -cnotin @('OBSERVED','HOLD') -or
    $record.phase -cnotin @('IDENTITY','TASK','FILES','WORK','LAST_INSTALL','COMPLETE') -or
    $record.task -cnotin @('UNKNOWN','Running','Ready','Disabled') -or
    $record.gateway -cnotin @('UNKNOWN','NEW','OLD','OTHER') -or
    $record.bridge -cnotin @('UNKNOWN','NEW','OLD','OTHER') -or
    $record.bridge_sha16 -cnotmatch '^(UNKNOWN|[0-9a-f]{16})$' -or
    $record.owner_health -cnotin @('UNKNOWN','READY_FRESH','STALE','MISSING') -or
    $record.last_install_code -cnotmatch '^(UNKNOWN|[A-Z][A-Z0-9_]{4,79})$' -or
    $record.active_locks -isnot [ValueType] -or $record.active_locks -lt -1 -or
    $record.pending_events -isnot [ValueType] -or $record.pending_events -lt -1 -or
    $record.marker_count -isnot [ValueType] -or $record.marker_count -lt -1 -or
    $record.active_locks -gt 10000 -or $record.pending_events -gt 10000 -or
    $record.marker_count -gt 10000) {
    throw 'P2_TEXT_STATUS_READER_SCHEMA_INVALID'
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$record.utc_epoch
if ($age -lt 0 -or $age -gt 180) { throw 'P2_TEXT_STATUS_READER_STALE' }
Write-Output ('P2_TEXT_STATUS=' + $record.status)
Write-Output ('P2_TEXT_STATUS_PHASE=' + $record.phase)
Write-Output ('P2_TEXT_STATUS_TASK=' + $record.task)
Write-Output ('P2_TEXT_STATUS_GATEWAY=' + $record.gateway)
Write-Output ('P2_TEXT_STATUS_BRIDGE=' + $record.bridge)
Write-Output ('P2_TEXT_STATUS_BRIDGE_SHA16=' + $record.bridge_sha16)
Write-Output ('P2_TEXT_STATUS_OWNER_HEALTH=' + $record.owner_health)
Write-Output ('P2_TEXT_STATUS_ACTIVE_LOCKS=' + $record.active_locks)
Write-Output ('P2_TEXT_STATUS_PENDING_EVENTS=' + $record.pending_events)
Write-Output ('P2_TEXT_STATUS_MARKER_COUNT=' + $record.marker_count)
Write-Output ('P2_TEXT_STATUS_LAST_INSTALL_CODE=' + $record.last_install_code)
Write-Output 'P2_TEXT_STATUS_PRIVATE_LOG=NOT_EXPORTED'
