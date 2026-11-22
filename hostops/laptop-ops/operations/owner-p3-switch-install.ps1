# One-shot, exact-source two-module Owner P3 film-switch repair. Never deletes
# P2 checkpoints, requests or subtitle files. Requires idle P2 before replace.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = '977d89f68b87ac696c7b73e012dde30766c47e2d'
$pinned = [ordered]@{
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = 'a2c7ff61d4e4c414bcb510fb573059a99f17cbcbb0e4cd2ee17b7cd98c01d666'
    'poc/p2-sub-discovery/owner_p3_p4_policy_r0.py' = '8ab15096e0e1dbd2c28ee2b6d12620150b5d17966e27e89ec73b0a398f32fc46'
}
$expectedOld = @{
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = '3febeac9f8ee5f3c0719894e1fb9ba67c91af4439970adbafdcbc8df28d9f953'
    'poc/p2-sub-discovery/owner_p3_p4_policy_r0.py' = 'f52e5ce0fd41fd6bbd593d9dd11265aaf0f8334d85dd99f0ebb075238d918121'
}

$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$inbox = Join-Path $root 'inbox'
$p2state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$health = Join-Path $root 'agent-health.json'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$interactive = [string](Get-CimInstance Win32_ComputerSystem).UserName

function Hold([string]$phase) {
    Write-Output ('OWNER_DUAL_INSTALL=HOLD_' + $phase)
    throw ('OWNER_DUAL_INSTALL_HOLD_' + $phase)
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0) {
            Hold 'OWNER_PENDING_EVENT'
        }
    }
    if (Test-Path -LiteralPath $p2state -PathType Container) {
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2state -File -Recurse -Filter $pattern).Count -ne 0) {
                Hold 'P2_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function StartAndVerify([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 35; $i++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -ne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $beat = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($beat.state -cne 'READY' -or [long]$beat.pid -eq $oldPid -or
                [long]$beat.observed_utc_epoch -lt ($since - 2)) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$beat.pid)
            if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($owner.ReturnValue -eq 0 -and $owner.Sid -ceq $sid) { return $true }
        } catch { continue }
    }
    return $false
}
function StopOwner {
    NoOpenWork
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -ne 'Disabled') { Hold 'OWNER_TASK_STATE_UNKNOWN' }
    for ($i=0; $i -lt 5; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $left = @(Workers)
    if ($left.Count -gt 4) { Hold 'WORKER_COUNT_UNEXPECTED' }
    foreach ($worker in $left) {
        $owner = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        $cmd = [string]$worker.CommandLine
        $entry = Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'
        $bridge = Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid -or
            $null -eq $worker.CreationDate -or
            ($cmd.IndexOf($entry,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and
             $cmd.IndexOf($bridge,[StringComparison]::OrdinalIgnoreCase) -lt 0)) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $left) {
        NoOpenWork
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $owner = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(Workers).Count -ne 0) { Hold 'WORKERS_STILL_RUNNING' }
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($interactive) -or
    -not ([Security.Principal.WindowsIdentity]::GetCurrent().Name).Equals(
        $interactive,[StringComparison]::OrdinalIgnoreCase)) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
if (-not (Test-Path -LiteralPath $app -PathType Container)) { Hold 'OWNER_APP_MISSING' }
$task = CheckTask
$oldPid = 0L
if (Test-Path -LiteralPath $health -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
    catch { $oldPid = 0L }
}

$backupRoot = Join-Path $root ('backups\owner-dual-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $backupRoot 'staged'
$previous = Join-Path $backupRoot 'previous'
[IO.Directory]::CreateDirectory($stage) | Out-Null
[IO.Directory]::CreateDirectory($previous) | Out-Null
$paths = [System.Collections.Generic.List[string]]::new()
$changed = [System.Collections.Generic.List[string]]::new()
$wasStopped = $false
$completed = $false
try {
    # Pinned exact Git source, downloaded before stopping the real Owner.
    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $target = Join-Path $stage $native
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
            $source + '/' + $rel) -OutFile $target -ErrorAction Stop
        if ((Hash $target) -cne $pinned[$rel]) { Hold 'PINNED_BYTES_MISMATCH' }
        $paths.Add((Join-Path $app $native))
    }
    Write-Output 'OWNER_P3_SWITCH_STAGE=2_EXACT_SHA256_PASS'
    NoOpenWork
    $wasStopped = $true
    StopOwner
    NoOpenWork

    # Existing bytes are backed up individually, including an ABSENT marker
    # for a newly introduced module, before any destination is replaced.
    $before = [ordered]@{}
    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $target = Join-Path $app $native
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $target) -PathType Container)) {
            Hold 'DESTINATION_FOLDER_MISSING'
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Hash $target) -cne $expectedOld[$rel]) {
                Hold 'OWNER_INSTALLED_BASELINE_DRIFT'
            }
            $saved = Join-Path $previous $native
            [IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
            [IO.File]::Copy($target,$saved,$false)
            if ((Hash $target) -cne (Hash $saved)) { Hold 'BACKUP_HASH_MISMATCH' }
            $before[$rel] = (Hash $saved)
        } elseif (Test-Path -LiteralPath $target) { Hold 'DESTINATION_NOT_FILE' }
        else { $before[$rel] = 'ABSENT' }
    }
    ([ordered]@{schema='TTV-OWNER-DUAL-ROLLBACK-V1';source_commit=$source;
        previous=$before} | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $backupRoot 'rollback-ledger.json') -Encoding utf8

    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $dest = Join-Path $app $native
        $new = Join-Path (Split-Path -Parent $dest) ('.owner-dual-' +
            [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy((Join-Path $stage $native),$new,$false)
        if ((Hash $new) -cne $pinned[$rel]) { Hold 'TEMP_HASH_MISMATCH' }
        if ($before[$rel] -ceq 'ABSENT') { [IO.File]::Move($new,$dest) }
        else {
            $displaced = Join-Path (Split-Path -Parent $dest) ('.owner-dual-before-' +
                [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Replace($new,$dest,$displaced)
        }
        $changed.Add($rel)
        if ((Hash $dest) -cne $pinned[$rel]) { Hold 'INSTALLED_HASH_MISMATCH' }
    }
    # Syntax smoke, without executing Owner imports or calling an AI provider.
    & py -3 -B -c 'import ast,sys,pathlib; [ast.parse(pathlib.Path(p).read_text(encoding="utf-8")) for p in sys.argv[1:]]' @paths
    if ($LASTEXITCODE -ne 0) { Hold 'OFFLINE_PYTHON_AST_FAILED' }
    if (-not (StartAndVerify $oldPid)) { Hold 'FRESH_OWNER_NOT_READY' }
    $completed = $true
    Write-Output 'OWNER_P3_SWITCH_INSTALL=2_FILES_INSTALLED_FRESH_OWNER_RUNNING'
    Write-Output ('OWNER_DUAL_SOURCE=' + $source)
    Write-Output ('OWNER_DUAL_ROLLBACK_BACKUP=' + $backupRoot)
    Write-Output 'OWNER_DUAL_P2_CHECKPOINTS=UNMODIFIED'
} catch {
    $failure = $_
    if ($changed.Count -ne 0) {
        try {
            StopOwner
            foreach ($rel in $changed) {
                $dest = Join-Path $app ($rel.Replace('/','\'))
                if (-not (Test-Path -LiteralPath $dest -PathType Leaf) -or
                    (Hash $dest) -cne $pinned[$rel]) { throw 'ROLLBACK_DESTINATION_DRIFT' }
                if ($before[$rel] -ceq 'ABSENT') { [IO.File]::Delete($dest) }
                else {
                    $saved = Join-Path $previous ($rel.Replace('/','\'))
                    if ((Hash $saved) -cne $before[$rel]) { throw 'ROLLBACK_BACKUP_DRIFT' }
                    $restore = Join-Path (Split-Path -Parent $dest) ('.owner-dual-restore-' +
                        [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Copy($saved,$restore,$false)
                    $displaced = Join-Path (Split-Path -Parent $dest) ('.owner-dual-failed-' +
                        [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Replace($restore,$dest,$displaced)
                }
            }
            Write-Output 'OWNER_DUAL_ROLLBACK=OLD_BYTES_RESTORED'
        } catch { Write-Output 'OWNER_DUAL_ROLLBACK=FAILED_PRIVATE_MANUAL_RECOVERY_REQUIRED'; throw }
    }
    if ($wasStopped) {
        if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RECOVERY_FAILED' }
        Write-Output 'OWNER_DUAL_OLD_OWNER=RECOVERED_RUNNING'
    }
    throw $failure
} finally {
    # Keep backup/ledger and failed staged evidence private for recovery.
    if (-not $completed) { Write-Output 'OWNER_DUAL_INSTALL=NOT_CONFIRMED' }
}
