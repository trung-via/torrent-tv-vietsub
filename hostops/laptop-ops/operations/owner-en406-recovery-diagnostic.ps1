# Read-only Owner-interactive diagnosis of two exact, failed EN406 HostOps requests.
# Private logs never leave the Owner account; report only bounded enum fields.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestPath = Join-Path $spool 'Requests\request.json'
$current = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($current.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$current.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'EN406_DIAG_REQUEST_INVALID'
}
$history = Join-Path $spool 'History'
$expected = [ordered]@{
    quarantine = '4611cbb481f2b706c164238764f5509ecfcb9310'
    restore = '3f070231a90039185b85e5963b0a575d1f39e0c8'
}
function Classify([string]$kind) {
    $match = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $history -File -Filter 'receipt-*.json' -Force)) {
        try {
            if ($file.Length -gt 512 -or $file.Length -le 0) { continue }
            $receipt = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($receipt.schema -cne 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -or
                $receipt.source_commit -cne $expected[$kind] -or
                $receipt.result -cne 'FAILED_NO_RETRY' -or
                [string]$receipt.nonce -cnotmatch '^[a-f0-9]{32}$') { continue }
            $match += $receipt
        } catch { continue }
    }
    if ($match.Count -ne 1) { return 'RECEIPT_NOT_UNIQUE' }
    $logPath = Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\LaptopHostOps\run-' + $match[0].nonce + '\full-owner-output.log')
    if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) { return 'PRIVATE_LOG_MISSING' }
    $item = Get-Item -LiteralPath $logPath -Force
    if ($item.Length -le 0 -or $item.Length -gt 1048576 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return 'PRIVATE_LOG_INVALID' }
    $lines = @(Get-Content -LiteralPath $logPath -Tail 160 -Encoding UTF8)
    $prefix = if ($kind -ceq 'quarantine') { 'OWNER_EN406_QUARANTINE_HOLD_' } else { 'OWNER_406_INSTALL_HOLD_' }
    $allowed = if ($kind -ceq 'quarantine') {
        @('INTERACTIVE_OWNER_REQUIRED','ROOT_MISSING','ROOT_REPARSE_POINT',
          'OWNER_TASK_IDENTITY_DRIFT','OWNER_TASK_NOT_RUNNING','PENDING_OWNER_EVENT',
          'P2_UNKNOWN_OR_ACTIVE_EFFECT','MARKER_NOT_UNIQUE','FILE_MISSING',
          'FILE_UNTRUSTED','MARKER_CONTENT_CHANGED','BLOCKED_EVENT_NOT_FOUND',
          'BLOCKED_EVENT_NOT_RECENT','MULTIPLE_RECENT_BLOCKED_EVENTS',
          'LATEST_BLOCKED_EVENT_NOT_BOUND','OWNER_EVENT_CLAIM_INVALID',
          'MARKER_NEWER_THAN_EVENT','CURRENT_AI_EN_ALREADY_CACHED',
          'CURRENT_LEGACY_EN_ALREADY_CACHED','CURRENT_FAILURE_TRACE_NOT_PROVEN',
          'HEALTH_NOT_READABLE','UNEXPECTED_WORKER_COUNT',
          'OWNER_WORKER_IDENTITY_UNVERIFIED','WORKERS_STILL_RUNNING',
          'PREMOVE_CLAIM_DRIFT','ARCHIVED_BYTES_MISMATCH',
          'RESTART_NEW_OWNER_NOT_VERIFIED')
    } else {
        @('OWNER_INTERACTIVE_REQUIRED','OWNER_INSTALL_ROOT_INVALID',
          'OWNER_TASK_IDENTITY_DRIFT','POST_QUARANTINE_TASK_NOT_DISABLED',
          'OWNER_WORKERS_PRESENT','P2_STATE_MISSING',
          'EXACT_B11_ARCHIVE_NOT_VERIFIED','FILE_MISSING','REPARSE_PATH',
          'B11_NO_RETRY_LEDGER_INVALID','PENDING_OWNER_EVENT',
          'P2_INFLIGHT_OR_ACTIVE_LOCK','PREVIOUS_HEALTH_UNREADABLE',
          'INSTALLED_SOURCE_DRIFT','SOURCE_HASH_MISMATCH',
          'POST_QUARANTINE_CONCURRENCY_DRIFT','BACKUP_HASH_MISMATCH',
          'INSTALLED_HASH_MISMATCH','OFFLINE_IMPORT_FAILED',
          'FRESH_OWNER_HEALTH_NOT_VERIFIED','POST_RESTART_SOURCE_HASH_DRIFT')
    }
    foreach ($code in $allowed) {
        if (@($lines | Where-Object { $_ -clike ('*' + $prefix + $code + '*') }).Count -gt 0) {
            return $code
        }
    }
    if ($kind -ceq 'quarantine') {
        if (@($lines | Where-Object { $_ -cmatch 'OWNER_EN406_MARKER=QUARANTINED_ORIGINAL_BYTES_PRESERVED' }).Count -gt 0) {
            return 'MARKER_ARCHIVED_THEN_FAILED'
        }
        if (@($lines | Where-Object { $_ -cmatch 'OWNER_EN406_HOLD=TASK_DISABLED_MARKER_ORIGINAL' }).Count -gt 0) {
            return 'TASK_DISABLED_MARKER_ORIGINAL'
        }
    }
    return 'UNCLASSIFIED_PRIVATE_ERROR'
}
$q = Classify 'quarantine'
$r = Classify 'restore'
$ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$task = [string]$ownerTask.State
if ($task -cnotin @('Running','Ready','Disabled')) { $task = 'OTHER' }
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$cache = Join-Path $base 'subtitle-trials'
$markerState = 'UNKNOWN'
if (Test-Path -LiteralPath $cache -PathType Container) {
    $active = @(Get-ChildItem -LiteralPath $cache -File -Force -Filter '.en-once-*' |
        Where-Object { $_.Name -cmatch '^\.en-once-[0-9a-f]{64}$' })
    $archived = @(Get-ChildItem -LiteralPath $cache -File -Force -Filter '.en-once-*.quarantined-*' |
        Where-Object { $_.Name -cmatch '^\.en-once-[0-9a-f]{64}\.quarantined-[0-9a-f]{32}$' })
    $markerState = if ($active.Count -eq 0 -and $archived.Count -eq 1) { 'ONE_ARCHIVED_NONE_ACTIVE' }
    elseif ($active.Count -eq 1 -and $archived.Count -eq 0) { 'ONE_ACTIVE_NONE_ARCHIVED' }
    elseif ($active.Count -gt 1) { 'MULTIPLE_ACTIVE' }
    elseif ($active.Count -eq 0 -and $archived.Count -eq 0) { 'NO_MARKER_SEEN' }
    else { 'MIXED_MARKER_STATE' }
}
$p2 = 'UNKNOWN'
$p2Root = Join-Path $base 'P2\auto-lean120-state'
$inbox = Join-Path $base 'OwnerBridge\inbox'
if ((Test-Path -LiteralPath $p2Root -PathType Container) -and
    (Test-Path -LiteralPath $inbox -PathType Container)) {
    $locks = @(Get-ChildItem -LiteralPath $p2Root -Recurse -File -Force |
        Where-Object { $_.Name -ceq 'active.lock' -or $_.Name -cmatch '^batch-[0-9]{4}\.inflight$' })
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json')
    $p2 = if ($locks.Count -eq 0 -and $pending.Count -eq 0) { 'CLEAR' } else { 'BUSY_OR_UNCERTAIN' }
}
$currentCheck = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($currentCheck.nonce -cne $current.nonce) { throw 'EN406_DIAG_REQUEST_CHANGED' }
$report = [ordered]@{
    schema='TTV-OWNER-EN406-RECOVERY-DIAG-V1'; nonce=$current.nonce
    quarantine=$q; restore=$r; task=$task; marker=$markerState; p2=$p2
} | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($report) -gt 512) { throw 'EN406_DIAG_REPORT_OVERSIZE' }
$destination = Join-Path $spool 'Receipts\en406-recovery-diag.json'
$temp = $destination + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$report,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$destination,$true)
Write-Output 'OWNER_EN406_DIAG=PRIVATE_LOGS_CLASSIFIED_NO_MUTATION'
