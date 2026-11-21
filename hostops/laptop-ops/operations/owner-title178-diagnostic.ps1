# Owner-private, read-only classification of ONE failed source-pinned install.
# Publish only a bounded code to the HostOps receipt folder; no private log text.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = '9753445bb4bedd1b6662c1cc7e6656813f0f3075'
$op = 'owner-title-alias-178-install'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$history = Join-Path $spool 'History'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'TITLE178_DIAG_CURRENT_REQUEST_INVALID' }
$match = @()
foreach ($path in @(Get-ChildItem -LiteralPath $history -File -Filter 'receipt-*.json')) {
    if ($path.Length -le 0 -or $path.Length -gt 512 -or
        ($path.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
    try {
        $receipt = Get-Content -LiteralPath $path.FullName -Raw | ConvertFrom-Json
        if ($receipt.schema -ceq 'TTV-LAPTOP-HOSTOPS-RECEIPT-V1' -and
            $receipt.source_commit -ceq $source -and
            $receipt.operation -ceq $op -and
            $receipt.result -ceq 'FAILED_NO_RETRY' -and
            $receipt.nonce -cmatch '^[0-9a-f]{32}$') { $match += $receipt }
    } catch { continue }
}
if ($match.Count -ne 1) { throw 'TITLE178_DIAG_FAILED_RECEIPT_NOT_UNIQUE' }
$nonce = [string]$match[0].nonce
$log = Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\LaptopHostOps\run-' + $nonce + '\full-owner-output.log')
if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { throw 'TITLE178_DIAG_LOG_MISSING' }
$file = Get-Item -LiteralPath $log -Force
if ($file.Length -le 0 -or $file.Length -gt 1048576 -or
    ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'TITLE178_DIAG_LOG_UNTRUSTED' }
$lines = @(Get-Content -LiteralPath $log -Tail 220)
$codes = @($lines | ForEach-Object {
    if ($_ -cmatch '^OWNER_TITLE178=(HOLD_[A-Z0-9_]+|STAGED_SIX_EXACT_HASHES|ALREADY_INSTALLED_NO_RESTART|OFFLINE_IMPORT_PASS|INSTALLED_SIX_HASHES_OWNER_READY|ROLLBACK_ATTEMPTED|ROLLBACK_UNCERTAIN_OWNER_ATTENTION_REQUIRED|OLD_OWNER_RESTORED)$') {
        $Matches[1]
    }
})
$code = 'NO_INSTALL_MARKER'
$primary = 'NO_INSTALL_MARKER'
if ($codes.Count -gt 0) {
    $code = [string]$codes[-1]
    $hold = @($codes | Where-Object { $_ -clike 'HOLD_*' })
    if ($hold.Count -gt 0) {
        $primary = [string]$hold[0]
        $code = [string]$hold[-1]
    }
}
if ($code -ceq 'NO_INSTALL_MARKER' -and
    @($lines | Where-Object { $_ -match 'ParserError|Missing.*terminator|Unexpected token' }).Count -gt 0) {
    $code = 'SCRIPT_PARSE_ERROR'
}
if ($code -ceq 'NO_INSTALL_MARKER' -and
    @($lines | Where-Object { $_ -match 'Invoke-WebRequest|HTTP [45][0-9][0-9]|Unable to connect' }).Count -gt 0) {
    $code = 'SOURCE_DOWNLOAD_FAILED'
}
if ($code -cnotmatch '^[A-Z0-9_]{3,80}$') { throw 'TITLE178_DIAG_CODE_INVALID' }
$pinned = @{
    'automatic_vietsub_flow.py' = '0156951817811a3c72a183e23df73611119386716f8f0572e7d6203e533911c5'
    'matcher.py' = 'f56ca2dfe004dfe0c127b19307720661e19920a44c507bceab88986c0997af3b'
    'opensubtitles.py' = '0e5b4e3e1593cfb4e93102a1e269014178d004a3e4a9e3a4af8e4ff07a648ecb'
    'owner_selected_file_resolver.py' = '93ab4f62eded98bfad3c3b8322536fe0547ee80ac0b206c24f735499577b4247'
    'owner_torrserver_readonly.py' = '2add8bfec22afa5a4644d1dfb9228438736301c56968c1015c815e08c3964e07'
    'verified_v3_processor.py' = 'a1805198e62df2f3dbf5d3146bc83a33e08545e01bfe09a6609b72090b5ce42c'
}
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$newCount = 0
foreach ($name in $pinned.Keys) {
    $target = Join-Path $installed $name
    if (Test-Path -LiteralPath $target -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $pinned[$name]) {
            $newCount++
        }
    }
}
$backupState = 'NOT_PROVEN'
$importIssue = 'NOT_FOUND'
$backupRoot = Join-Path $ownerRoot 'backups'
if (Test-Path -LiteralPath $backupRoot -PathType Container) {
    $candidates = @(Get-ChildItem -LiteralPath $backupRoot -Directory -Filter 'owner-title178-*' |
        Sort-Object LastWriteTimeUtc -Descending)
    if ($candidates.Count -ge 1 -and $candidates.Count -le 4 -and
        -not ($candidates[0].Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        $importLog = Join-Path $candidates[0].FullName 'offline-import.log'
        if (Test-Path -LiteralPath $importLog -PathType Leaf) {
            $importItem = Get-Item -LiteralPath $importLog -Force
            if ($importItem.Length -gt 0 -and $importItem.Length -le 131072 -and
                -not ($importItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $importIssue = 'OTHER_IMPORT_FAILURE'
                $importLines = @(Get-Content -LiteralPath $importLog -Tail 50)
                foreach ($line in $importLines) {
                    if ($line -cmatch "ModuleNotFoundError: No module named '([A-Za-z0-9_.]{1,60})'") {
                        $importIssue = 'MODULE_MISSING_' + $Matches[1].ToUpperInvariant().Replace('.','_')
                        break
                    }
                    if ($line -cmatch "ImportError: cannot import name '([A-Za-z0-9_]{1,60})'") {
                        $importIssue = 'SYMBOL_MISSING_' + $Matches[1].ToUpperInvariant()
                        break
                    }
                    if ($line -cmatch 'SyntaxError:') { $importIssue = 'SYNTAX_ERROR'; break }
                }
            }
        }
        $matched = 0
        foreach ($name in $pinned.Keys) {
            $original = Join-Path $candidates[0].FullName $name
            $installedFile = Join-Path $installed $name
            if ((Test-Path -LiteralPath $original -PathType Leaf) -and
                (Test-Path -LiteralPath $installedFile -PathType Leaf) -and
                (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ceq
                (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash) {
                $matched++
            }
        }
        if ($matched -eq 6) { $backupState = 'ORIGINAL_SIX_MATCH' }
        else { $backupState = 'BACKUP_DIFFERS' }
    }
}
$ownerState = 'UNKNOWN'
try {
    $ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
    if ([string]$ownerTask.State -ceq 'Running') { $ownerState = 'RUNNING' }
    elseif ([string]$ownerTask.State -ceq 'Ready') { $ownerState = 'READY' }
    else { $ownerState = 'NOT_RUNNING' }
} catch { $ownerState = 'UNKNOWN' }
$healthState = 'NOT_VERIFIED'
$healthIdentity = 'NOT_VERIFIED'
$health = Join-Path $ownerRoot 'agent-health.json'
if (Test-Path -LiteralPath $health -PathType Leaf) {
    try {
        $heartbeat = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$heartbeat.observed_utc_epoch
        if ($heartbeat.state -ceq 'READY' -and $age -ge 0 -and $age -le 30) {
            $healthState = 'READY_FRESH'
            $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$heartbeat.pid)
            if ($null -eq $live) { $healthIdentity = 'PID_NOT_FOUND' }
            elseif ([string]$live.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                $healthIdentity = 'CMDLINE_MISMATCH'
            } else {
                $ownerIdentity = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
                $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                if ($ownerIdentity.ReturnValue -eq 0 -and $ownerIdentity.Sid -ceq $sid) {
                    $healthIdentity = 'PID_SID_MATCH'
                } else { $healthIdentity = 'PID_SID_MISMATCH' }
            }
        } elseif ($heartbeat.state -ceq 'READY') { $healthState = 'READY_STALE' }
    } catch { $healthState = 'NOT_VERIFIED' }
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'TITLE178_DIAG_REQUEST_CHANGED' }
$result = Join-Path $spool 'Receipts\title178-diag.json'
$payload = @{ schema='TTV-OWNER-TITLE178-DIAG-V4'; nonce=$request.nonce;
    code=$code; primary=$primary; new_count=$newCount;
    backup=$backupState; task=$ownerState; health=$healthState;
    import_issue=$importIssue; health_identity=$healthIdentity } | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 512) { throw 'TITLE178_DIAG_PAYLOAD_LONG' }
$temp = $result + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$result,$true)
Write-Output 'TITLE178_DIAG=PRIVATE_CLASSIFICATION_COMPLETED'
