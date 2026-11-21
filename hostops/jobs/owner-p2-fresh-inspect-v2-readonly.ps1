# Read only the Owner-produced, sanitized V2 inspection receipt.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'P2_FRESH_V2_READER_TRUSTED_RUNNER_REQUIRED'
}
$path = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts\p2-fresh-inspect-v2.json'
$item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
if ($item.Length -le 0 -or $item.Length -gt 512 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P2_FRESH_V2_READER_INVALID_FILE'
}
$doc = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($doc.PSObject.Properties.Name | Sort-Object) -join ',' -cne
        'abandoned_count,archived_count,inflight_count,lock_count,owner_python_count,pending_count,phase,schema,status,task_contract,task_state,uninspectable_python_count,utc_epoch' -or
    $doc.schema -cne 'TTV-P2-FRESH-INSPECT-V2' -or
    $doc.status -cnotin @('OBSERVED','HOLD') -or
    $doc.phase -cnotin @('IDENTITY','TASK','STATE','PROCESSES','COMPLETE') -or
    $doc.task_state -cnotin @('Running','Ready','Disabled','UNKNOWN') -or
    $doc.task_contract -cnotin @('MATCH','MISMATCH','UNKNOWN')) {
    throw 'P2_FRESH_V2_READER_INVALID_SCHEMA'
}
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$doc.utc_epoch
if ($age -lt 0 -or $age -gt 120) { throw 'P2_FRESH_V2_READER_STALE' }
foreach ($name in @('abandoned_count','archived_count','inflight_count','lock_count',
                   'pending_count','owner_python_count','uninspectable_python_count')) {
    if ($doc.$name -isnot [ValueType] -or [long]$doc.$name -lt -1 -or
        [long]$doc.$name -gt 1000000) { throw 'P2_FRESH_V2_READER_INVALID_COUNT' }
}
Write-Output ('P2_FRESH_V2_STATUS=' + $doc.status)
Write-Output ('P2_FRESH_V2_PHASE=' + $doc.phase)
Write-Output ('P2_FRESH_V2_TASK=' + $doc.task_state)
Write-Output ('P2_FRESH_V2_TASK_CONTRACT=' + $doc.task_contract)
foreach ($name in @('abandoned_count','archived_count','inflight_count','lock_count',
                   'pending_count','owner_python_count','uninspectable_python_count')) {
    Write-Output ('P2_FRESH_V2_' + $name.ToUpperInvariant() + '=' + $doc.$name)
}
Write-Output 'P2_FRESH_V2_PRIVATE_DATA=NOT_READ_BY_RUNNER'
