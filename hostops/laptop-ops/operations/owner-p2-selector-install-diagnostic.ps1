# Observe only: exact selector installer receipts, module bytes, Owner task and
# fresh PID. No restart, rollback, provider, file modification or claim replay.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$current.nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'SELECTOR_DIAG_REQUEST_INVALID' }
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $owner 'app\poc\p2-sub-discovery'
$old = @{
    'automatic_vietsub_flow.py' = '0156951817811a3c72a183e23df73611119386716f8f0572e7d6203e533911c5'
    'matcher.py' = 'f56ca2dfe004dfe0c127b19307720661e19920a44c507bceab88986c0997af3b'
}
$new = @{
    'automatic_vietsub_flow.py' = 'b74f2ea36aa824795c9bfb465a3d159649ef9e89db5005d8dd64c19ed171ae60'
    'matcher.py' = '068ae2306e5bd02a5e90fff36c9d8005059697ec00fc11865be42ab143f75ee0'
}
$versions = @{}
foreach ($name in $old.Keys) {
    $path = Join-Path $installed $name
    $versions[$name] = 'MISSING_OR_OTHER'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $file = Get-Item -LiteralPath $path -Force
        if (-not ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ceq $old[$name]) { $versions[$name] = 'OLD' }
            elseif ($hash -ceq $new[$name]) { $versions[$name] = 'NEW' }
        }
    }
}
$backup = 'NOT_OBSERVED'
$backups = Join-Path $owner 'backups'
if (Test-Path -LiteralPath $backups -PathType Container) {
    $candidates = @(Get-ChildItem -LiteralPath $backups -Directory -Filter 'owner-selector-*' |
                    Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 3)
    if ($candidates.Count -gt 0) {
        $backup = 'INCOMPLETE'
        $allOld = $true
        foreach ($name in $old.Keys) {
            $path = Join-Path $candidates[0].FullName $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $old[$name]) {
                $allOld = $false
            }
        }
        if ($allOld) { $backup = 'ORIGINAL_TWO_MATCH' }
    }
}
$taskState = 'UNKNOWN'
try { $taskState = [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent').State }
catch { $taskState = 'UNKNOWN' }
if ($taskState -cnotin @('Running','Ready','Disabled')) { $taskState = 'OTHER' }
$health = 'NOT_PROVEN'
$healthFile = Join-Path $owner 'agent-health.json'
if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
    $item = Get-Item -LiteralPath $healthFile -Force
    if ($item.Length -gt 0 -and $item.Length -le 2048 -and
        -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        try {
            $record = Get-Content -LiteralPath $healthFile -Raw | ConvertFrom-Json
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$record.observed_utc_epoch
            if ($record.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and
                $record.state -ceq 'READY' -and $age -ge 0 -and $age -le 30 -and
                [long]$record.pid -gt 0) {
                $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$record.pid)
                if ($null -ne $proc -and [string]$proc.CommandLine -match 'owner_p3_p4_entrypoint\.py') {
                    $who = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
                    if ($who.ReturnValue -eq 0 -and $who.Sid -ceq
                        [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) {
                        $health = 'READY_PID_SID_MATCH'
                    }
                }
            } elseif ($age -gt 30) { $health = 'STALE' }
        } catch { $health = 'NOT_PROVEN' }
    }
}
$busy = 'UNKNOWN'
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
if (Test-Path -LiteralPath $p2 -PathType Container) {
    $count = @(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter '*.inflight').Count +
        @(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter 'active.lock').Count
    $busy = if ($count -gt 0) { 'YES' } else { 'NO' }
}
$failure = 'NOT_OBSERVED'
$prior = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
# The dispatcher archives the previous request during this diagnostic run;
# the previous Owner operation is found by its exact source SHA in History.
$history = Join-Path $spool 'History'
foreach ($candidate in @(Get-ChildItem -LiteralPath $history -File -Filter 'request-*.json' |
                         Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 8)) {
    try {
        $doc = Get-Content -LiteralPath $candidate.FullName -Raw | ConvertFrom-Json
        if ($doc.source_commit -cne '91533e5b15d17fef20554acfae295e7de4bb5645') { continue }
        $logPath = Join-Path $env:LOCALAPPDATA ('TorrentTVVietsub\LaptopHostOps\run-' + $doc.nonce + '\full-owner-output.log')
        if (Test-Path -LiteralPath $logPath -PathType Leaf) {
            $log = @(Get-Content -LiteralPath $logPath -Tail 100 -ErrorAction Stop)
            if (@($log | Where-Object { $_ -match 'OWNER_SELECTOR_INSTALL_ROLLBACK_UNCERTAIN_PRIVATE_LOG' }).Count -gt 0) {
                $failure = 'ROLLBACK_UNCERTAIN'
            } elseif (@($log | Where-Object { $_ -match 'OWNER_SELECTOR_INSTALL_FAILED_BEFORE_STOP_PRIVATE_LOG' }).Count -gt 0) {
                $failure = 'FAILED_BEFORE_STOP'
            } elseif (@($log | Where-Object { $_ -match 'OWNER_SELECTOR_INSTALL=ROLLED_BACK_OWNER_READY' }).Count -gt 0) {
                $failure = 'ROLLED_BACK'
            } elseif (@($log | Where-Object { $_ -match 'MethodInvocationException|File\.Replace' }).Count -gt 0) {
                $failure = 'FILE_REPLACE_ERROR'
            } else { $failure = 'OWNER_FAILURE_UNCLASSIFIED' }
        } else { $failure = 'PRIVATE_LOG_MISSING' }
        break
    } catch { continue }
}
if ($current.nonce -cne $prior.nonce) { throw 'SELECTOR_DIAG_REQUEST_CHANGED' }
$payload = [ordered]@{
    schema='TTV-OWNER-SELECTOR-DIAG-V1'; nonce=$current.nonce
    flow=$versions['automatic_vietsub_flow.py']; matcher=$versions['matcher.py']
    backup=$backup; task=$taskState; health=$health; p2_busy=$busy; failure=$failure
} | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 512) { throw 'SELECTOR_DIAG_SUMMARY_OVERSIZE' }
$target = Join-Path $spool 'Receipts\selector-diag.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$payload,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_SELECTOR_DIAG=PRIVATE_CLASSIFICATION_COMPLETE'
