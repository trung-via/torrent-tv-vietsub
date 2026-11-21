# One-time Owner-interactive installation of a complete, unredacted local log.
# Fixed 3-file source revision; does not grant GitHub/NETWORK_SERVICE log access.
# Inspect by default. -Apply requires an idle verified Owner and restarts only
# the existing Owner Agent Task. Never processes or replays an old P2 request.
[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$commit = '627f45269bec7adef3ef8ce473fa67161eb87a99'
$pinned = [ordered]@{
    'owner_session_bridge.py' = '6d987ab9b9cf29334807c933bf6ab48baff258be3f9accba4776a629dd725de0'
    'owner_p3_p4_entrypoint.py' = '3febeac9f8ee5f3c0719894e1fb9ba67c91af4439970adbafdcbc8df28d9f953'
    'p3_p4_shared_https_route_r0.py' = 'c1c3bdbef76a7a33dbe797e83e95912a63720b3976a80089e84c8db9d039d0be'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $root 'app\poc\p2-sub-discovery'
$health = Join-Path $root 'agent-health.json'
$trace = Join-Path $root 'diagnostics\owner-full.log'
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Hold([string]$reason) {
    Write-Output ('OWNER_FULL_DIAG=HOLD_' + $reason)
    throw 'OWNER_FULL_DIAGNOSTICS_MAINTENANCE_HOLD'
}
function Hash([string]$file) {
    (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
            Hold 'PENDING_OWNER_EVENTS'
        }
    }
    if (Test-Path -LiteralPath $p2 -PathType Container) {
        foreach ($pattern in @('batch-*.inflight', 'active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_ACTIVE_OR_UNKNOWN_EFFECT'
            }
        }
    }
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne $ownerSid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_CHANGED'
    }
    return $task
}
function StopOwner {
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -ne 'Disabled') { Hold 'TASK_STATE_UNEXPECTED' }
    for ($i=0; $i -lt 12; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKER_NOT_STOPPED_TASK_DISABLED'
}
function StartAndVerify([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -ne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $heartbeat = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($heartbeat.state -ne 'READY' -or [long]$heartbeat.pid -eq $oldPid -or
                [long]$heartbeat.observed_utc_epoch -lt ($since - 2)) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$heartbeat.pid)
            if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $identity = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) { continue }
            return $true
        } catch { continue }
    }
    return $false
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
$task = CheckTask
NoOpenWork
$stage = Join-Path $env:TEMP ('ttv-owner-full-diag-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
try {
    foreach ($name in $pinned.Keys) {
        $target = Join-Path $installed $name
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { Hold 'INSTALLED_MODULE_MISSING' }
        $source = Join-Path $stage $name
        Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
            $commit + '/poc/p2-sub-discovery/' + $name) -OutFile $source -ErrorAction Stop
        if ((Hash $source) -cne $pinned[$name]) { Hold 'DOWNLOADED_MODULE_HASH_MISMATCH' }
    }
    Write-Output 'OWNER_FULL_DIAG_STAGE=3_FILES_HASH_VERIFIED'
    Write-Output ('OWNER_FULL_DIAG_TASK_BEFORE=' + [string]$task.State)
    if (-not $Apply) { Write-Output 'OWNER_FULL_DIAG=INSPECT_ONLY'; return }

    $oldPid = 0L
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        try {
            $oldDoc = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            $oldPid = [long]$oldDoc.pid
        }
        catch { $oldPid = 0L }
    }
    $oldTraceBytes = 0L
    if (Test-Path -LiteralPath $trace -PathType Leaf) {
        $oldTraceBytes = (Get-Item -LiteralPath $trace).Length
    }
    StopOwner
    NoOpenWork
    $backups = Join-Path $root ('backups\owner-full-diag-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backups) | Out-Null
    $changed = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($name in $pinned.Keys) {
            $target = Join-Path $installed $name
            Copy-Item -LiteralPath $target -Destination (Join-Path $backups $name) -ErrorAction Stop
            $next = Join-Path $installed ('.full-diag-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination $next -ErrorAction Stop
            [IO.File]::Replace($next, $target, $null)
            $changed.Add($name)
            if ((Hash $target) -cne $pinned[$name]) { throw 'INSTALLED_HASH_MISMATCH' }
        }
        if (-not (StartAndVerify $oldPid) -or
            -not (Test-Path -LiteralPath $trace -PathType Leaf) -or
            (Get-Item -LiteralPath $trace).Length -le $oldTraceBytes -or
            @((Get-Content -LiteralPath $trace -Tail 70) | Where-Object {
                $_ -match '^OWNER_FULL_DIAGNOSTICS_STARTED pid=\d+ epoch=\d+$'
            }).Count -eq 0) {
            throw 'FULL_DIAGNOSTICS_STARTUP_NOT_VERIFIED'
        }
        Write-Output 'OWNER_FULL_DIAG=INSTALLED_FRESH_OWNER_RUNNING'
        Write-Output 'OWNER_FULL_DIAG_LOG=OWNER_PRIVATE_FULL_UNREDACTED'
        Write-Output 'OWNER_FULL_DIAG_PROVIDER_TV=NOT_RUN_BY_INSTALLER'
    } catch {
        Write-Output 'OWNER_FULL_DIAG=ROLLBACK_ATTEMPTED'
        StopOwner
        foreach ($name in $changed) {
            $target = Join-Path $installed $name
            $restore = Join-Path $installed ('.full-diag-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            Copy-Item -LiteralPath (Join-Path $backups $name) -Destination $restore -ErrorAction Stop
            [IO.File]::Replace($restore, $target, $null)
        }
        if (-not (StartAndVerify $oldPid)) { Hold 'ROLLBACK_OWNER_NOT_RECOVERED' }
        Hold 'NEW_OWNER_FAILED_OLD_OWNER_RECOVERED'
    }
} finally {
    if (Test-Path -LiteralPath $stage -PathType Container) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
