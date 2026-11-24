# Read-only classification of exactly the prior source-neutral install attempt.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or $request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'NEUTRAL_DIAG_REQUEST_INVALID' }
$prior = $null
$files = @(Get-ChildItem -LiteralPath (Join-Path $spool 'History') -File -Filter 'request-*.json' | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 300)
foreach ($file in $files) {
    if ($file.Length -gt 1024 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    try { $r = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json } catch { continue }
    if ($r.source_commit -ceq '5d45e2e181395546cd9cc60df397ddcba63a96c2' -and $r.nonce -cmatch '^[0-9a-f]{32}$') { $prior = $r; break }
}
$reason = 'NOT_FOUND'
$previous = 'NOT_FOUND'
if ($null -ne $prior) {
    $previous = 'OTHER'
    $receipt = Join-Path $spool ('History\receipt-' + $prior.nonce + '.json')
    if (Test-Path -LiteralPath $receipt -PathType Leaf) {
        $r = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
        if ($r.nonce -ceq $prior.nonce -and $r.source_commit -ceq $prior.source_commit -and $r.result -cin @('FAILED_NO_RETRY','SUCCESS')) { $previous = $r.result }
    }
    $log = Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\LaptopHostOps\run-' + $prior.nonce + '\full-owner-output.log')
    $reason = 'NO_LOG'
    if (Test-Path -LiteralPath $log -PathType Leaf) {
        $reason = 'UNCLASSIFIED'
        $item = Get-Item -LiteralPath $log
        if ($item.Length -le 1048576 -and -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $lines = @(Get-Content -LiteralPath $log -Tail 300)
            $allowed = @('NO_LOG',
    'UNCLASSIFIED',
    'NOT_FOUND',
    'PINNED_SOURCE_HASH_MISMATCH',
    'PINNED_SOURCE_PATH_INVALID',
    'TRUSTED_SOURCE_BRANCH_DRIFT',
    'NETWORK_FETCH_FAILED',
    'PS_RUNTIME_ERROR',
    'ROLLED_BACK',
    'HOLD_DIRECTORY_INVALID',
    'HOLD_FILE_INVALID',
    'HOLD_OWNER_TASK_IDENTITY_DRIFT',
    'HOLD_PENDING_OWNER_EVENTS',
    'HOLD_OWNER_TASK_STATE_UNKNOWN',
    'HOLD_RESIDUAL_WORKER_SET_UNEXPECTED',
    'HOLD_RESIDUAL_IDENTITY_UNVERIFIED',
    'HOLD_RESIDUAL_TASK_REENABLED',
    'HOLD_RESIDUAL_CHANGED',
    'HOLD_RESIDUAL_NOT_STOPPED',
    'HOLD_INTERACTIVE_OWNER_REQUIRED',
    'HOLD_OWNER_TASK_NOT_RUNNING_OR_READY',
    'HOLD_OWNER_HEARTBEAT_NOT_VERIFIED',
    'HOLD_STOPPED_TASK_RESIDUAL_WORKERS',
    'HOLD_PINNED_DOWNLOAD_HASH_DRIFT',
    'HOLD_INSTALLED_ENTRYPOINT_SHA_DRIFT',
    'HOLD_STAGED_SOURCE_SHA_DRIFT',
    'HOLD_STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED',
    'HOLD_BACKUP_HASH_INVALID',
    'HOLD_OWNER_NOT_STOPPED_DURING_APPLY',
    'HOLD_SOURCE_CHANGED_DURING_APPLY',
    'HOLD_NEW_MODULE_PATH_CONFLICT',
    'HOLD_INSTALLED_BASELINE_CHANGED',
    'HOLD_TEMP_COPY_DRIFT',
    'HOLD_POST_REPLACE_HASH_CHANGED',
    'HOLD_OFFLINE_IMPORT_FAILED',
    'HOLD_FRESH_OWNER_NOT_VERIFIED',
    'HOLD_ROLLBACK_NEW_FILE_DRIFT',
    'HOLD_ROLLBACK_BACKUP_DRIFT',
    'HOLD_ROLLBACK_INSTALLED_DRIFT',
    'HOLD_ROLLBACK_ORIGINAL_HASH_CHANGED',
    'HOLD_ROLLBACK_OWNER_HEARTBEAT_FAILED_TASK_HOLD')
            foreach ($line in $lines) {
                if ($line -match '^OWNER_BRAIN_R3=(HOLD_[A-Z_]+)$' -and $Matches[1] -cin $allowed -and $reason -notmatch '^HOLD_') { $reason = $Matches[1] }
                elseif ($line -match 'OWNER_OPS_PINNED_SOURCE_HASH_MISMATCH') { $reason = 'PINNED_SOURCE_HASH_MISMATCH' }
                elseif ($line -match 'OWNER_OPS_PINNED_SOURCE_PATH_INVALID') { $reason = 'PINNED_SOURCE_PATH_INVALID' }
                elseif ($line -match 'OWNER_OPS_TRUSTED_SOURCE_BRANCH_DRIFT') { $reason = 'TRUSTED_SOURCE_BRANCH_DRIFT' }
                elseif ($line -match 'OWNER_BRAIN_R3_INSTALL_FAILED_ROLLED_BACK') { $reason = 'ROLLED_BACK' }
                elseif ($reason -eq 'UNCLASSIFIED' -and $line -match 'HttpResponseException|WebCmdletWebResponseException|timed out') { $reason = 'NETWORK_FETCH_FAILED' }
                elseif ($reason -eq 'UNCLASSIFIED' -and $line -match 'RuntimeException|MethodInvocationException|PropertyNotFoundException') { $reason = 'PS_RUNTIME_ERROR' }
            }
        }
    }
}
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$state = [string]$task.State
if ($state -cnotin @('Ready','Disabled','Running','Queued','Unknown')) { $state = 'Unknown' }
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app\poc\p2-sub-discovery'
$expected = @(
    @('agy_opensubtitles_acquisition.py','dcf4282926067dce8e1e05f9be9d36aa1e96443bbe2710c134b0eaedec9debce','6ce182d5e9bd5de4b31827203cd967c752d97aea18bdce8a7630b8ed20950c84'),
    @('brain_english_inbox.py','61d64d3c170b325f587d82220b2e2b23aee196496a24d655fd3dae9b34f3f2fb','dab7cfe87bb134c6ee939b62e0ee2f14ca7cee1c3744317c52c12eef3dc1cf07')
)
$version = @()
foreach ($row in $expected) {
    $file = Join-Path $root $row[0]
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { $version += 'MISSING'; continue }
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ceq $row[1]) { $version += 'OLD' } elseif ($hash -ceq $row[2]) { $version += 'NEW' } else { $version += 'DRIFT' }
}
$report = [ordered]@{schema='TTV-OWNER-NEUTRAL-DIAG-V1';nonce=$request.nonce;reason=$reason;prior=$previous;task=$state;agy=$version[0];inbox=$version[1]}
$out = Join-Path $spool ('Receipts\owner-neutral-diag-' + $request.nonce + '.json')
[IO.File]::WriteAllText($out,($report | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output 'OWNER_NEUTRAL_DIAG=READ_ONLY_RECEIPT_WRITTEN'
