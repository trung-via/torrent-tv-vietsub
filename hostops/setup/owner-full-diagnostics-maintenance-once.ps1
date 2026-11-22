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
    for ($i=0; $i -lt 4; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    # Stopping the Task can terminate the PowerShell parent while leaving
    # Python children alive. Verify exact installed entrypoint, Owner SID,
    # PID, command and creation time before stopping only those children.
    NoOpenWork
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_OWNER_WORKER_COUNT_UNEXPECTED' }
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matches = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matches.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_OWNER_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenWork
        if ([string](CheckTask).State -cne 'Disabled') { Hold 'OWNER_TASK_REENABLED_DURING_STOP' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $identity = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_OWNER_WORKER_IDENTITY_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(OwnerWorkers).Count -eq 0) {
            Write-Output ('OWNER_FULL_DIAG_RESIDUAL_WORKERS_STOPPED=' + $workers.Count)
            return
        }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKERS_STILL_RUNNING_TASK_DISABLED'
}
function StartAndVerify([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $script:lastStartReason = 'NO_FRESH_HEARTBEAT'
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -ne 'Running') {
            $script:lastStartReason = 'TASK_NOT_RUNNING'
            continue
        }
        if (-not (Test-Path -LiteralPath $health -PathType Leaf)) {
            $script:lastStartReason = 'HEALTH_FILE_MISSING'
            continue
        }
        try {
            $heartbeat = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($heartbeat.state -ne 'READY') {
                $script:lastStartReason = 'HEALTH_NOT_READY'
                continue
            }
            if ([long]$heartbeat.pid -eq $oldPid -or
                [long]$heartbeat.observed_utc_epoch -lt ($since - 2)) {
                $script:lastStartReason = 'HEALTH_NOT_FRESH'
                continue
            }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$heartbeat.pid)
            if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                $script:lastStartReason = 'HEALTH_PROCESS_NOT_VERIFIED'
                continue
            }
            $identity = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
                $script:lastStartReason = 'HEALTH_OWNER_NOT_VERIFIED'
                continue
            }
            $script:lastStartReason = 'FRESH_OWNER_READY'
            return $true
        } catch {
            $script:lastStartReason = 'HEALTH_READ_OR_IDENTITY_ERROR: ' + $_.Exception.Message
            continue
        }
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
    $phase = 'REPLACE_FILES'
    $script:lastStartReason = 'NOT_STARTED'
    $smoke = Join-Path $backups 'offline-import-smoke.log'
    try {
        foreach ($name in $pinned.Keys) {
            $target = Join-Path $installed $name
            Copy-Item -LiteralPath $target -Destination (Join-Path $backups $name) -ErrorAction Stop
            $next = Join-Path $installed ('.full-diag-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination $next -ErrorAction Stop
            # .NET on the Owner's PowerShell 7 runtime rejects a null backup
            # path with "The path is empty". Use an explicit same-volume path.
            $atomicBackup = Join-Path $backups ('atomic-before-' + $name)
            [IO.File]::Replace($next, $target, $atomicBackup)
            $changed.Add($name)
            if ((Hash $target) -cne $pinned[$name]) { throw 'INSTALLED_HASH_MISMATCH' }
        }
        # Import the exact newly installed modules while Owner is stopped.
        # No LAN listener or provider request is started by module import.
        $phase = 'OFFLINE_IMPORT'
        Push-Location -LiteralPath $installed
        try {
            & py -3 -B -c 'import owner_p3_p4_entrypoint; print("OWNER_FULL_DIAG_OFFLINE_IMPORT_PASS")' *> $smoke
            $importExit = $LASTEXITCODE
        } finally { Pop-Location }
        if ($importExit -ne 0) { throw 'OFFLINE_IMPORT_FAILED' }
        Write-Output 'OWNER_FULL_DIAG_OFFLINE_IMPORT=PASS_NO_LAN_NO_PROVIDER'

        $phase = 'FRESH_OWNER_START'
        if (-not (StartAndVerify $oldPid)) {
            throw ('OWNER_FRESH_HEARTBEAT_NOT_VERIFIED: ' + $script:lastStartReason)
        }
        $phase = 'FULL_LOG_VERIFY'
        if (-not (Test-Path -LiteralPath $trace -PathType Leaf)) {
            throw 'OWNER_FULL_LOG_NOT_CREATED'
        }
        if ((Get-Item -LiteralPath $trace).Length -le $oldTraceBytes) {
            throw 'OWNER_FULL_LOG_NOT_APPENDED'
        }
        if (@((Get-Content -LiteralPath $trace -Tail 70) | Where-Object {
                $_ -match '^OWNER_FULL_DIAGNOSTICS_STARTED pid=\d+ epoch=\d+$'
            }).Count -eq 0) {
            throw 'OWNER_FULL_LOG_STARTUP_MARKER_NOT_FOUND'
        }
        Write-Output 'OWNER_FULL_DIAG=INSTALLED_FRESH_OWNER_RUNNING'
        Write-Output 'OWNER_FULL_DIAG_LOG=OWNER_PRIVATE_FULL_UNREDACTED'
        Write-Output 'OWNER_FULL_DIAG_PROVIDER_TV=NOT_RUN_BY_INSTALLER'
    } catch {
        # Preserve the *original* failure before rollback (which starts its
        # own process and could otherwise conceal why the new one failed).
        $originalFailure = $_
        Write-Output ('OWNER_FULL_DIAG_FAILURE_PHASE=' + $phase)
        Write-Output ('OWNER_FULL_DIAG_FAILURE_TYPE=' + $originalFailure.Exception.GetType().FullName)
        Write-Output ('OWNER_FULL_DIAG_FAILURE_MESSAGE=' + $originalFailure.Exception.Message)
        Write-Output ('OWNER_FULL_DIAG_NEW_OWNER_START=' + [string]$script:lastStartReason)
        Write-Output ('OWNER_FULL_DIAG_LOG_CREATED=' +
            [string](Test-Path -LiteralPath $trace -PathType Leaf))
        if ($phase -eq 'OFFLINE_IMPORT' -and (Test-Path -LiteralPath $smoke -PathType Leaf)) {
            Write-Output 'OWNER_FULL_DIAG_OFFLINE_IMPORT_TRACE_BEGIN'
            Get-Content -LiteralPath $smoke -ErrorAction Continue | Write-Output
            Write-Output 'OWNER_FULL_DIAG_OFFLINE_IMPORT_TRACE_END'
        }
        try {
            @(
                'OWNER_FULL_DIAG_FAILURE_UTC=' + [DateTimeOffset]::UtcNow.ToString('o')
                'OWNER_FULL_DIAG_FAILURE_PHASE=' + $phase
                'OWNER_FULL_DIAG_NEW_OWNER_START=' + [string]$script:lastStartReason
                'OWNER_FULL_DIAG_ORIGINAL_EXCEPTION=' + $originalFailure.Exception.ToString()
                'OWNER_FULL_DIAG_SCRIPT_STACK=' + $originalFailure.ScriptStackTrace
            ) | Set-Content -LiteralPath (Join-Path $backups 'maintenance-failure.log') -Encoding utf8
            Write-Output ('OWNER_FULL_DIAG_PRIVATE_FAILURE_LOG=' +
                (Join-Path $backups 'maintenance-failure.log'))
        } catch {
            Write-Output 'OWNER_FULL_DIAG_PRIVATE_FAILURE_LOG=WRITE_FAILED'
        }
        Write-Output 'OWNER_FULL_DIAG=ROLLBACK_ATTEMPTED'
        StopOwner
        foreach ($name in $changed) {
            $target = Join-Path $installed $name
            $restore = Join-Path $installed ('.full-diag-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            Copy-Item -LiteralPath (Join-Path $backups $name) -Destination $restore -ErrorAction Stop
            $failedReplacementBackup = Join-Path $backups ('failed-installed-' + $name)
            [IO.File]::Replace($restore, $target, $failedReplacementBackup)
        }
        if (-not (StartAndVerify $oldPid)) { Hold 'ROLLBACK_OWNER_NOT_RECOVERED' }
        Hold 'NEW_OWNER_FAILED_OLD_OWNER_RECOVERED'
    }
} finally {
    if (Test-Path -LiteralPath $stage -PathType Container) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
