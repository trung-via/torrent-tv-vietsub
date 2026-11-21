# Install the PR #178 torrent-title alias fix into the existing Owner session.
# No TV/APK change, provider call, queued event consumption or cache mutation.
# All downloaded bytes are pinned to the reviewed PR head; fail closed on work.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCommit = '44ebc36c7b6086a1b7c846d3068c01c791202428'
$pinned = [ordered]@{
    'automatic_vietsub_flow.py' = '0156951817811a3c72a183e23df73611119386716f8f0572e7d6203e533911c5'
    'matcher.py' = 'f56ca2dfe004dfe0c127b19307720661e19920a44c507bceab88986c0997af3b'
    'opensubtitles.py' = '0e5b4e3e1593cfb4e93102a1e269014178d004a3e4a9e3a4af8e4ff07a648ecb'
    'owner_selected_file_resolver.py' = '93ab4f62eded98bfad3c3b8322536fe0547ee80ac0b206c24f735499577b4247'
    'owner_torrserver_readonly.py' = '2add8bfec22afa5a4644d1dfb9228438736301c56968c1015c815e08c3964e07'
    'verified_v3_processor.py' = 'a1805198e62df2f3dbf5d3146bc83a33e08545e01bfe09a6609b72090b5ce42c'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $root 'app\poc\p2-sub-discovery'
$health = Join-Path $root 'agent-health.json'
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$stage = $null
$backup = $null
$changed = [Collections.Generic.List[string]]::new()
$oldPid = 0L
$stopped = $false

function Hold([string]$code) {
    Write-Output ('OWNER_TITLE178=HOLD_' + $code)
    throw ('OWNER_TITLE178_HOLD_' + $code)
}
function Hash([string]$file) {
    (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function ExactFile([string]$file) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_LINK'
    }
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function Task {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne $ownerSid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Hold 'OWNER_INBOX_MISSING' }
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    if (Test-Path -LiteralPath $p2) {
        if (-not (Test-Path -LiteralPath $p2 -PathType Container)) { Hold 'P2_STATE_NOT_DIRECTORY' }
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function StopOwner {
    NoOpenWork
    $task = Task
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -ne 'Disabled') { Hold 'OWNER_TASK_UNEXPECTED_STATE' }
    $script:stopped = $true
    for ($i=0; $i -lt 8; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT_UNVERIFIED' }
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matching = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matching.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenWork
        if ([string](Task).State -ne 'Disabled') { Hold 'TASK_REENABLED_DURING_STOP' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $identity = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_WORKER_STILL_RUNNING'
}
function StartAndVerify([long]$priorPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    # The Owner task may take longer than one health-tick interval to boot.
    # Observe a fresh PID and live Owner SID, never just a task state.
    for ($i=0; $i -lt 90; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -ne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $r = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($r.state -cne 'READY' -or [long]$r.pid -le 0 -or
                [long]$r.pid -eq $priorPid -or
                [long]$r.observed_utc_epoch -lt ($since - 2)) { continue }
            $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$r.pid)
            if (-not $process -or
                [string]$process.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $identity = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($identity.ReturnValue -eq 0 -and $identity.Sid -cne $ownerSid) { return $true }
        } catch { continue }
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
if (-not (Test-Path -LiteralPath $installed -PathType Container)) { Hold 'OWNER_INSTALL_ROOT_MISSING' }
if ([string](Task).State -ne 'Running') { Hold 'OWNER_TASK_NOT_RUNNING' }
NoOpenWork
$stage = Join-Path $env:TEMP ('ttv-owner-title178-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
try {
    foreach ($name in $pinned.Keys) {
        $target = Join-Path $installed $name
        ExactFile $target
        $file = Join-Path $stage $name
        $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
            $sourceCommit + '/poc/p2-sub-discovery/' + $name
        Invoke-WebRequest -Uri $uri -OutFile $file -ErrorAction Stop
        ExactFile $file
        if ((Get-Item -LiteralPath $file).Length -gt 1048576 -or
            (Hash $file) -cne $pinned[$name]) { Hold 'SOURCE_HASH_DRIFT' }
    }
    Write-Output 'OWNER_TITLE178=STAGED_SIX_EXACT_HASHES'
    $missing = @($pinned.Keys | Where-Object {
        (Hash (Join-Path $installed $_)) -cne $pinned[$_]
    })
    if ($missing.Count -eq 0) {
        Write-Output 'OWNER_TITLE178=ALREADY_INSTALLED_NO_RESTART'
        return
    }
    NoOpenWork
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
        catch { $oldPid = 0L }
    }
    $backup = Join-Path $root ('backups\owner-title178-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    $original = @{}
    foreach ($name in $pinned.Keys) {
        $target = Join-Path $installed $name
        $saved = Join-Path $backup $name
        [IO.File]::Copy($target,$saved,$false)
        if ((Hash $saved) -cne (Hash $target)) { Hold 'BACKUP_HASH_MISMATCH' }
        $original[$name] = Hash $saved
    }
    try {
        StopOwner
    } catch {
        $stopError = $_
        # If stopping failed before any replacement and no worker remains,
        # recover the old Owner task. An unknown worker is a hard HOLD.
        if ($stopped -and @(OwnerWorkers).Count -eq 0 -and
            [string](Task).State -eq 'Disabled') {
            NoOpenWork
            if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RESTART_FAILED' }
        }
        throw $stopError
    }
    if ([string](Task).State -ne 'Disabled' -or @(OwnerWorkers).Count -ne 0) {
        Hold 'OWNER_NOT_QUIESCENT'
    }
    NoOpenWork
    try {
        foreach ($name in $pinned.Keys) {
            NoOpenWork
            $target = Join-Path $installed $name
            if ((Hash $target) -cne $original[$name]) { Hold 'BASELINE_CHANGED' }
            $next = Join-Path $installed ('.title178-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy((Join-Path $stage $name),$next,$false)
            if ((Hash $next) -cne $pinned[$name]) { Hold 'TEMP_HASH_DRIFT' }
            [IO.File]::Replace($next,$target,(Join-Path $backup ('displaced-' + $name)))
            $changed.Add($name)
            if ((Hash $target) -cne $pinned[$name]) { Hold 'INSTALLED_HASH_DRIFT' }
        }
        Push-Location -LiteralPath $installed
        try {
            & py -3 -B -c 'import automatic_vietsub_flow, matcher, opensubtitles, owner_selected_file_resolver, owner_torrserver_readonly, verified_v3_processor' *> (Join-Path $backup 'offline-import.log')
            $code = $LASTEXITCODE
        } finally { Pop-Location }
        if ($code -ne 0) { Hold 'OFFLINE_IMPORT_FAILED' }
        Write-Output 'OWNER_TITLE178=OFFLINE_IMPORT_PASS'
        if (-not (StartAndVerify $oldPid)) { Hold 'NEW_OWNER_HEALTH_NOT_READY' }
        Write-Output 'OWNER_TITLE178=INSTALLED_SIX_HASHES_OWNER_READY'
        Write-Output 'OWNER_TITLE178=TV_AND_PROVIDER_NOT_TESTED'
    } catch {
        $failure = $_
        Write-Output 'OWNER_TITLE178=ROLLBACK_ATTEMPTED'
        try {
            StopOwner
            foreach ($name in $changed) {
                $target = Join-Path $installed $name
                $next = Join-Path $installed ('.title178-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy((Join-Path $backup $name),$next,$false)
                [IO.File]::Replace($next,$target,(Join-Path $backup ('failed-' + $name)))
                if ((Hash $target) -cne $original[$name]) { Hold 'ROLLBACK_HASH_DRIFT' }
            }
            if (-not (StartAndVerify $oldPid)) { Hold 'ROLLBACK_OWNER_NOT_READY' }
        } catch {
            Write-Output 'OWNER_TITLE178=ROLLBACK_UNCERTAIN_OWNER_ATTENTION_REQUIRED'
            throw
        }
        Write-Output 'OWNER_TITLE178=OLD_OWNER_RESTORED'
        throw $failure
    }
} finally {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage -PathType Container)) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
