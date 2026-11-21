# Read-only post-timeout reconciliation. Never starts/stops Owner or HostOps,
# changes spool state, reads user-private transcripts or reaches the TV/API.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_OPS_RECONCILE_TRUSTED_SERVICE_REQUIRED'
}
$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$ops = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\' -ErrorAction Stop
Write-Output ('OWNER_RECONCILE_OWNER_TASK=' + [string]$owner.State)
Write-Output ('OWNER_RECONCILE_OPS_TASK=' + [string]$ops.State)
try {
    $info = Get-ScheduledTaskInfo -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\' -ErrorAction Stop
    $code = [uint32]([long]$info.LastTaskResult -band 4294967295)
    Write-Output ('OWNER_RECONCILE_OPS_LAST_RESULT=' + ('0x{0:X8}' -f $code))
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
        [DateTimeOffset]::new($info.LastRunTime.ToUniversalTime()).ToUnixTimeSeconds()
    Write-Output ('OWNER_RECONCILE_OPS_LAST_RUN_AGE=' + $(if ($age -ge 0 -and $age -le 86400) { $age } else { -1 }))
} catch {
    Write-Output 'OWNER_RECONCILE_OPS_LAST_RESULT=UNAVAILABLE'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestFile = Join-Path $spool 'Requests\request.json'
$receiptFile = Join-Path $spool 'Receipts\receipt.json'
$request = $null
if (-not (Test-Path -LiteralPath $requestFile -PathType Leaf)) {
    Write-Output 'OWNER_RECONCILE_REQUEST=MISSING'
} else {
    $item = Get-Item -LiteralPath $requestFile -Force
    if ($item.Length -le 0 -or $item.Length -gt 1024 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_OPS_RECONCILE_REQUEST_UNTRUSTED'
    }
    $request = Get-Content -LiteralPath $requestFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
        $request.nonce -cnotmatch '^[0-9a-f]{32}$' -or
        $request.source_commit -cnotmatch '^[0-9a-f]{40}$') { throw 'OWNER_OPS_RECONCILE_BAD_REQUEST' }
    Write-Output ('OWNER_RECONCILE_REQUEST=' + $(if ($request.source_commit -ceq
        '1559ef1587debeb19879b4aca885096c14e7ae48') { 'P4_V4_APPLY' } else { 'OTHER' }))
}
if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) {
    Write-Output 'OWNER_RECONCILE_RECEIPT=MISSING'
} else {
    $item = Get-Item -LiteralPath $receiptFile -Force
    if ($item.Length -le 0 -or $item.Length -gt 512 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_OPS_RECONCILE_RECEIPT_UNTRUSTED'
    }
    $receipt = Get-Content -LiteralPath $receiptFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if ($receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
        $receipt.nonce -cnotmatch '^[0-9a-f]{32}$' -or
        $receipt.result -cnotin @('SUCCESS','FAILED_NO_RETRY')) {
        throw 'OWNER_OPS_RECONCILE_BAD_RECEIPT'
    }
    $matched = $null -ne $request -and $request.nonce -ceq $receipt.nonce -and
        $request.source_commit -ceq $receipt.source_commit
    Write-Output ('OWNER_RECONCILE_RECEIPT=' + $(if ($matched) { $receipt.result } else { 'UNMATCHED' }))
}
$snapshotFile = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
if (Test-Path -LiteralPath $snapshotFile -PathType Leaf) {
    $item = Get-Item -LiteralPath $snapshotFile -Force
    if ($item.Length -le 0 -or $item.Length -gt 4096 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'OWNER_OPS_RECONCILE_SNAPSHOT_UNTRUSTED' }
    $s = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$s.snapshot_utc_epoch
    Write-Output ('OWNER_RECONCILE_OWNER_RUNTIME=' + $(switch ($s.schema) {
        'TTV-HOSTOPS-OWNER-SNAPSHOT-V4' {'V4'}
        'TTV-HOSTOPS-OWNER-SNAPSHOT-V3' {'V3'}
        default {'OTHER'}
    }))
    Write-Output ('OWNER_RECONCILE_OWNER_HEALTH=' + $(if ($age -ge 0 -and $age -le 10 -and
        $s.status -ceq 'READY_FRESH') { 'READY_FRESH' } else { 'NOT_FRESH' }))
    Write-Output ('OWNER_RECONCILE_P2=' + $(if ($age -ge 0 -and $age -le 20 -and
        [string]$s.p2.status -ceq 'CLEAR' -and
        [long]$s.p2.pending_events -eq 0 -and
        [long]$s.p2.inflight_count -eq 0) { 'CLEAR' } else { 'UNKNOWN_OR_ACTIVE' }))
} else {
    Write-Output 'OWNER_RECONCILE_OWNER_RUNTIME=UNKNOWN'
    Write-Output 'OWNER_RECONCILE_OWNER_HEALTH=UNKNOWN'
    Write-Output 'OWNER_RECONCILE_P2=UNKNOWN'
}
Write-Output 'OWNER_RECONCILE=READ_ONLY_NO_REPLAY'
