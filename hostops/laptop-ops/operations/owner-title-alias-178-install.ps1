# Install the PR #178 torrent-title alias fix into the existing Owner session.
# No TV/APK change, provider call, queued event consumption or cache mutation.
# All downloaded bytes are pinned to the reviewed PR head. This installer
# validates a shadow overlay BEFORE stopping Owner, and keeps a recovery ledger.
param([switch]$PreflightOnly)
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
$healthReason = 'NOT_TESTED'

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
function Ledger([string]$phase, [string]$file = 'NONE') {
    if ($null -eq $backup) { Hold 'LEDGER_NOT_INITIALIZED' }
    if ($phase -cnotmatch '^[A-Z_]{3,40}$' -or $file -cnotmatch '^[A-Za-z0-9._-]{1,80}$') {
        Hold 'LEDGER_PHASE_INVALID'
    }
    $record = [ordered]@{
        utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        phase = $phase
        file = $file
    }
    [IO.File]::AppendAllText((Join-Path $backup 'journal.ndjson'),
        (($record | ConvertTo-Json -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
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
function NoInFlightWork {
    if (Test-Path -LiteralPath $p2) {
        if (-not (Test-Path -LiteralPath $p2 -PathType Container)) { Hold 'P2_STATE_NOT_DIRECTORY' }
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Hold 'OWNER_INBOX_MISSING' }
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    NoInFlightWork
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
    $script:healthReason = 'START_FAILED'
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    # A task state alone is never an accepted health proof. Preserve the last
    # bounded diagnostic reason instead of silently discarding exceptions.
    for ($i=0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -ne 'Running') {
            $script:healthReason = 'TASK_NOT_RUNNING'; continue
        }
        if (-not (Test-Path -LiteralPath $health -PathType Leaf)) {
            $script:healthReason = 'HEALTH_FILE_MISSING'; continue
        }
        try {
            ExactFile $health
            if ((Get-Item -LiteralPath $health).Length -gt 2048) {
                $script:healthReason = 'HEALTH_FILE_INVALID'; continue
            }
            $r = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($r.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $r.state -cne 'READY' -or
                [long]$r.pid -le 0) {
                $script:healthReason = 'HEALTH_NOT_READY'; continue
            }
            if ([long]$r.pid -eq $priorPid) {
                $script:healthReason = 'HEALTH_OLD_PID'; continue
            }
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if ([long]$r.observed_utc_epoch -lt ($since - 2) -or
                $now - [long]$r.observed_utc_epoch -gt 30 -or
                [long]$r.observed_utc_epoch -gt $now) {
                $script:healthReason = 'HEALTH_STALE'; continue
            }
            $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$r.pid)
            if (-not $process) {
                $script:healthReason = 'PROCESS_NOT_FOUND'; continue
            }
            if ([string]$process.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                $script:healthReason = 'PROCESS_COMMAND_MISMATCH'; continue
            }
            $identity = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($identity.ReturnValue -eq 0 -and $identity.Sid -ceq $ownerSid) {
                $script:healthReason = 'READY_PID_SID_MATCH'
                return $true
            }
            $script:healthReason = 'PROCESS_SID_MISMATCH'
        } catch {
            $script:healthReason = 'HEALTH_PROBE_ERROR'
        }
    }
    return $false
}
function TestStagedImports {
    # New modules must load from stage, other dependencies from the actual
    # installed Owner app. Isolated Python, no network/publisher/provider.
    $python = @'
import importlib, pathlib, sys
stage, app = (pathlib.Path(value) for value in sys.argv[1:3])
sys.path[0:0] = [str(stage), str(app / 'poc/p2-sub-discovery'),
                 str(app / 'poc/p2-aisub'), str(app / 'poc/p3-vietsub-trigger')]
names = ('automatic_vietsub_flow', 'matcher', 'opensubtitles',
         'owner_selected_file_resolver', 'owner_torrserver_readonly',
         'verified_v3_processor')
try:
    for name in names:
        module = importlib.import_module(name)
        if pathlib.Path(module.__file__).resolve() != (stage / (name + '.py')).resolve():
            raise RuntimeError('STAGED_ORIGIN_DRIFT')
    importlib.import_module('owner_session_bridge')
    entry = app / 'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py'
    compile(entry.read_bytes(), str(entry), 'exec')
except BaseException:
    print('OWNER_TITLE178_STAGE_IMPORT=HOLD')
    sys.exit(2)
print('OWNER_TITLE178_STAGE_IMPORT=PASS')
'@
    $result = @(& py -3 -I -B -c $python $stage (Join-Path $root 'app') 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        @($result | Where-Object { [string]$_ -ceq 'OWNER_TITLE178_STAGE_IMPORT=PASS' }).Count -ne 1) {
        Hold 'STAGED_IMPORT_FAILED_OWNER_UNCHANGED'
    }
    Write-Output 'OWNER_TITLE178=STAGED_IMPORT_PASS_BEFORE_STOP'
}
function QuiesceForRollback {
    # Queued TV events are allowed AFTER Owner is disabled: keep them durable
    # for the restarted task. Never kill a possibly translating new process.
    NoInFlightWork
    if (@(OwnerWorkers).Count -ne 0) { Hold 'ROLLBACK_NEW_OWNER_WORKER_UNCERTAIN' }
    $task = Task
    if ([string]$task.State -notin @('Ready','Disabled')) {
        Hold 'ROLLBACK_TASK_RUNNING_OR_UNCERTAIN'
    }
    if ([string]$task.State -eq 'Ready') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    }
    if ([string](Task).State -ne 'Disabled' -or @(OwnerWorkers).Count -ne 0) {
        Hold 'ROLLBACK_QUIESCENCE_LOST'
    }
    NoInFlightWork
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
        Invoke-WebRequest -Uri $uri -OutFile $file -TimeoutSec 20 -ErrorAction Stop
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
    TestStagedImports
    if ($PreflightOnly) {
        NoOpenWork
        Write-Output 'OWNER_TITLE178=PREFLIGHT_PASS_NO_OWNER_STOP'
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
    $manifest = [ordered]@{
        schema = 'TTV-OWNER-TITLE178-RECOVERY-V2'
        source_commit = $sourceCommit
        original_sha256 = $original
        target_sha256 = $pinned
        created_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes(
        ($manifest | ConvertTo-Json -Depth 5))
    [IO.File]::WriteAllBytes((Join-Path $backup 'recovery-manifest.json'), $manifestBytes)
    Ledger 'BACKUP_VERIFIED'
    try {
        StopOwner
    } catch {
        $stopError = $_
        # If stopping failed before any replacement and no worker remains,
        # recover the old Owner task. An unknown worker is a hard HOLD.
        if ($stopped -and @(OwnerWorkers).Count -eq 0 -and
            [string](Task).State -eq 'Disabled') {
            Ledger 'RESTORE_OLD_AFTER_STOP_FAILURE'
            if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RESTART_FAILED' }
        }
        throw $stopError
    }
    try {
        if ([string](Task).State -ne 'Disabled' -or @(OwnerWorkers).Count -ne 0) {
            Hold 'OWNER_NOT_QUIESCENT'
        }
        # NoOpenWork here would incorrectly reject a new queued film while
        # Owner is stopped; those events must survive until restart.
        NoInFlightWork
        foreach ($name in $pinned.Keys) {
            NoInFlightWork
            $target = Join-Path $installed $name
            if ((Hash $target) -cne $original[$name]) { Hold 'BASELINE_CHANGED' }
            $next = Join-Path $installed ('.title178-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy((Join-Path $stage $name),$next,$false)
            if ((Hash $next) -cne $pinned[$name]) { Hold 'TEMP_HASH_DRIFT' }
            Ledger 'SWAP_INTENT' $name
            $changed.Add($name)
            [IO.File]::Replace($next,$target,(Join-Path $backup ('displaced-' + $name)))
            if ((Hash $target) -cne $pinned[$name]) { Hold 'INSTALLED_HASH_DRIFT' }
            Ledger 'SWAP_DONE' $name
        }
        Ledger 'NEW_START_INTENT'
        if (-not (StartAndVerify $oldPid)) { Hold 'NEW_OWNER_HEALTH_NOT_READY' }
        foreach ($name in $pinned.Keys) {
            if ((Hash (Join-Path $installed $name)) -cne $pinned[$name]) {
                Hold 'NEW_OWNER_INSTALLED_HASH_CHANGED'
            }
        }
        Ledger 'NEW_READY'
        Write-Output 'OWNER_TITLE178=INSTALLED_SIX_HASHES_OWNER_READY'
        Write-Output 'OWNER_TITLE178=LOADED_MODULE_PROVENANCE_NOT_INSTRUMENTED'
        Write-Output 'OWNER_TITLE178=TV_AND_PROVIDER_NOT_TESTED'
    } catch {
        $failure = $_
        $failedHealthReason = $healthReason
        Write-Output 'OWNER_TITLE178=ROLLBACK_SAFETY_EVALUATION'
        try {
            # If startup was attempted, an unverified running process may
            # still be translating; HOLD without stopping it or swapping code.
            QuiesceForRollback
            Write-Output 'OWNER_TITLE178=ROLLBACK_ATTEMPTED'
            Ledger 'ROLLBACK_INTENT'
            foreach ($name in $pinned.Keys) {
                $target = Join-Path $installed $name
                if ((Hash $target) -ceq $original[$name]) { continue }
                $next = Join-Path $installed ('.title178-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy((Join-Path $backup $name),$next,$false)
                if ((Hash $next) -cne $original[$name]) { Hold 'ROLLBACK_SOURCE_HASH_DRIFT' }
                Ledger 'ROLLBACK_SWAP_INTENT' $name
                [IO.File]::Replace($next,$target,(Join-Path $backup ('failed-' + $name)))
                if ((Hash $target) -cne $original[$name]) { Hold 'ROLLBACK_HASH_DRIFT' }
                Ledger 'ROLLBACK_SWAP_DONE' $name
            }
            Ledger 'ROLLBACK_REPLACED'
            if (-not (StartAndVerify $oldPid)) { Hold 'ROLLBACK_OWNER_NOT_READY' }
            Ledger 'OLD_READY'
        } catch {
            Write-Output 'OWNER_TITLE178=ROLLBACK_UNCERTAIN_OWNER_ATTENTION_REQUIRED'
            Write-Output ('OWNER_TITLE178=HEALTH_REASON_' + $failedHealthReason)
            throw
        }
        Write-Output 'OWNER_TITLE178=OLD_OWNER_RESTORED'
        Write-Output ('OWNER_TITLE178=HEALTH_REASON_' + $failedHealthReason)
        throw $failure
    }
} finally {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage -PathType Container)) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
