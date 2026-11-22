# Owner-interactive deployment of PR #178 OpenSubtitles SRT timeline repair.
# One pinned P2 source module only; preserve all P2 jobs, caches, credentials,
# P3/P4 state and the already-installed TV APK. No provider or playback call.
param([switch]$PreflightOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCommit = '7f6b2ce0e7233267e5b9094b11e2fd93259ec67d'
$old = [ordered]@{
    'opensubtitles.py' = '0e5b4e3e1593cfb4e93102a1e269014178d004a3e4a9e3a4af8e4ff07a648ecb'
}
$new = [ordered]@{
    'opensubtitles.py' = '7707da40a6463fff830065c0266725b6138e5e3c59cd67a1dd1cd2cbef6818c7'
}
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $owner 'app\poc\p2-sub-discovery'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_SELECTOR_REQUEST_INVALID'
}
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$stage = $null
$backup = $null
$stopped = $false
$touched = $false
$code = 'UNKNOWN'
$oldPid = 0L

function Fail([string]$reason) { throw ('SELECTOR_' + $reason) }
function Hash([string]$file) {
    (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function ExactFile([string]$file) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        ((Get-Item -LiteralPath $file -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Fail 'UNTRUSTED_SOURCE'
    }
}
function Task {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Fail 'TASK_IDENTITY_DRIFT'
    }
    return $task
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('python.exe','pythonw.exe','py.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoWork {
    $inbox = Join-Path $owner 'inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Fail 'INBOX_MISSING' }
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Fail 'PENDING_OWNER_EVENT'
    }
    NoP2InFlight
}
function NoP2InFlight {
    if (Test-Path -LiteralPath $stateRoot) {
        if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) { Fail 'P2_STATE_INVALID' }
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter $pattern).Count -gt 0) {
                Fail 'P2_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function WaitOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -cne 'Running') { continue }
        $healthPath = Join-Path $owner 'agent-health.json'
        if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { continue }
        try {
            $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
            $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            if ($health.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
                $health.state -cne 'READY' -or [long]$health.pid -le 0 -or
                [long]$health.pid -eq $oldPid -or
                [long]$health.observed_utc_epoch -lt ($since - 2) -or
                $now - [long]$health.observed_utc_epoch -gt 30 -or
                [long]$health.observed_utc_epoch -gt $now) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$health.pid)
            if ($null -eq $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                continue
            }
            $identity = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($identity.ReturnValue -eq 0 -and $identity.Sid -ceq $sid) { return $true }
        } catch { continue }
    }
    return $false
}
function Quiesce {
    NoWork
    $task = Task
    if ([string]$task.State -notin @('Running','Ready')) { Fail 'TASK_NOT_RUNNABLE' }
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $script:stopped = $true
    if ([string]$task.State -ceq 'Running') {
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    }
    for ($i = 0; $i -lt 8; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    # Windows may stop the scheduled-task wrapper yet leave its child Python
    # Owner process alive. The old six-file installer already handled this.
    # Stop only an exact, identity-verified Owner process, never arbitrary py.
    $left = @(Workers)
    if ($left.Count -gt 3) { Fail 'RESIDUAL_WORKER_COUNT_UNVERIFIED' }
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $left) {
        $matching = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matching.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Fail 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $left) {
        NoP2InFlight
        if ([string](Task).State -ne 'Disabled') { Fail 'TASK_REENABLED_DURING_STOP' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $who = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Fail 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i = 0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Fail 'OWNER_WORKER_STILL_RUNNING'
}
function RestoreOriginal {
    if (@(Workers).Count -ne 0) { Fail 'ROLLBACK_WORKER_RUNNING' }
    # A film may be selected while Owner is stopped. Preserve queued .json;
    # it is not a reason to destroy the backup or block restoring service.
    NoP2InFlight
    if ([string](Task).State -ne 'Disabled') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    }
    foreach ($name in $new.Keys) {
        $dest = Join-Path $installed $name
        $saved = Join-Path $backup $name
        ExactFile $saved
        if ((Hash $saved) -cne $old[$name]) { Fail 'ROLLBACK_BACKUP_DRIFT' }
        if ((Hash $dest) -ceq $old[$name]) { continue }
        $temp = Join-Path $installed ('.selector-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($saved, $temp, $false)
        [IO.File]::Replace($temp, $dest, (Join-Path $backup ('failed-' + $name)))
        if ((Hash $dest) -cne $old[$name]) { Fail 'ROLLBACK_HASH_DRIFT' }
    }
    if (-not (WaitOwner $oldPid)) { Fail 'ROLLBACK_OWNER_NOT_READY' }
    return $true
}
function WriteSummary([string]$outcome) {
    $current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
    if ($current.nonce -cne $request.nonce) { Fail 'REQUEST_CHANGED' }
    $payload = [ordered]@{
        schema = 'TTV-OWNER-SELECTOR-INSTALL-V1'
        nonce = $request.nonce
        result = $outcome
        installed_modules = if ($outcome -in @('INSTALLED_OWNER_READY','ALREADY_INSTALLED')) { 1 } else { 0 }
        owner = if ($outcome -in @('INSTALLED_OWNER_READY','ALREADY_INSTALLED','ROLLED_BACK_OWNER_READY')) { 'RUNNING_READY' } else { 'NOT_PROVEN' }
    } | ConvertTo-Json -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 512) { Fail 'SUMMARY_OVERSIZE' }
    $target = Join-Path $spool 'Receipts\selector-install.json'
    $temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp, $payload, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp, $target, $true)
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
        Fail 'OWNER_INTERACTIVE_REQUIRED'
    }
    if (-not (Test-Path -LiteralPath $installed -PathType Container)) {
        Fail 'OWNER_INSTALL_ROOT_MISSING'
    }
    $observedTask = Task
    if ([string]$observedTask.State -notin @('Running','Ready')) {
        Fail 'OWNER_TASK_NOT_RUNNABLE'
    }
    # A recovered scheduled task can be Ready while its previously launched
    # Python child still owns the Owner singleton. Confirm its exact identity
    # before treating this state as installable; never launch a second Owner.
    if ([string]$observedTask.State -eq 'Ready') {
        $heartbeat = Get-Content -LiteralPath (Join-Path $owner 'agent-health.json') -Raw |
            ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$heartbeat.observed_utc_epoch
        $liveOwner = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$heartbeat.pid)
        if ($heartbeat.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $heartbeat.state -cne 'READY' -or $age -lt 0 -or $age -gt 30 -or
            $null -eq $liveOwner -or
            [string]$liveOwner.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
            Fail 'READY_TASK_WITHOUT_OWNER'
        }
        $liveIdentity = Invoke-CimMethod -InputObject $liveOwner -MethodName GetOwnerSid
        if ($liveIdentity.ReturnValue -ne 0 -or $liveIdentity.Sid -cne $sid) {
            Fail 'READY_OWNER_IDENTITY_DRIFT'
        }
    }
    NoWork
    $baseline = [Collections.Generic.List[string]]::new()
    foreach ($name in $new.Keys) {
        $path = Join-Path $installed $name
        ExactFile $path
        $digest = Hash $path
        if ($digest -cne $new[$name] -and $digest -cne $old[$name]) {
            Fail 'INSTALLED_BASELINE_DRIFT'
        }
        $baseline.Add($digest)
    }
    if ($baseline[0] -ceq $new['opensubtitles.py']) {
        $code = 'ALREADY_INSTALLED'
    } else {
        if ($baseline[0] -cne $old['opensubtitles.py']) { Fail 'PARTIAL_INSTALL_NEEDS_RECONCILIATION' }
        $stage = Join-Path $env:TEMP ('ttv-selector-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        foreach ($name in $new.Keys) {
            $url = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
                $sourceCommit + '/poc/p2-sub-discovery/' + $name
            $dest = Join-Path $stage $name
            Invoke-WebRequest -Uri $url -OutFile $dest -TimeoutSec 30 -ErrorAction Stop
            ExactFile $dest
            if ((Get-Item -LiteralPath $dest).Length -gt 1048576 -or
                (Hash $dest) -cne $new[$name]) { Fail 'SOURCE_HASH_DRIFT' }
        }
        $preflight = @'
import importlib, pathlib, sys
stage, app = (pathlib.Path(x) for x in sys.argv[1:3])
sys.path[0:0] = [str(stage), str(app / 'poc/p2-sub-discovery'),
                str(app / 'poc/p2-aisub'), str(app / 'poc/p3-vietsub-trigger')]
try:
    for name in ('opensubtitles',):
        mod = importlib.import_module(name)
        if pathlib.Path(mod.__file__).resolve() != (stage / (name + '.py')).resolve():
            raise RuntimeError('WRONG_MODULE')
except BaseException:
    sys.exit(2)
print('SELECTOR_STAGE_IMPORT_PASS')
'@
        $result = @(& py -3 -I -B -c $preflight $stage (Join-Path $owner 'app') 2>$null)
        if ($LASTEXITCODE -ne 0 -or @($result | Where-Object { $_ -ceq 'SELECTOR_STAGE_IMPORT_PASS' }).Count -ne 1) {
            Fail 'STAGED_IMPORT_FAILED'
        }
        NoWork
        if ($PreflightOnly) {
            $code = 'PREFLIGHT_PASS_NO_STOP'
        } else {
        $healthFile = Join-Path $owner 'agent-health.json'
        if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
            try { $oldPid = [long](Get-Content -LiteralPath $healthFile -Raw | ConvertFrom-Json).pid }
            catch { $oldPid = 0L }
        }
        $backup = Join-Path $owner ('backups\owner-selector-' + [Guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($name in $new.Keys) {
            [IO.File]::Copy((Join-Path $installed $name), (Join-Path $backup $name), $false)
            if ((Hash (Join-Path $backup $name)) -cne $old[$name]) { Fail 'BACKUP_HASH_MISMATCH' }
        }
        $receipt = [ordered]@{
            schema='TTV-OWNER-SELECTOR-BACKUP-V1'; source_commit=$sourceCommit
            original_sha256=$old; target_sha256=$new
        } | ConvertTo-Json -Depth 5
        [IO.File]::WriteAllText((Join-Path $backup 'recovery.json'), $receipt,
            [Text.UTF8Encoding]::new($false))
        Quiesce
        NoP2InFlight
        foreach ($name in $new.Keys) {
            if ((Hash (Join-Path $installed $name)) -cne $old[$name]) { Fail 'BASELINE_CHANGED' }
            $temp = Join-Path $installed ('.selector-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy((Join-Path $stage $name), $temp, $false)
            if ((Hash $temp) -cne $new[$name]) { Fail 'STAGE_HASH_DRIFT' }
            $touched = $true
            [IO.File]::Replace($temp, (Join-Path $installed $name),
                (Join-Path $backup ('displaced-' + $name)))
            if ((Hash (Join-Path $installed $name)) -cne $new[$name]) { Fail 'INSTALLED_HASH_DRIFT' }
        }
        if (-not (WaitOwner $oldPid)) { Fail 'NEW_OWNER_NOT_READY' }
        foreach ($name in $new.Keys) {
            if ((Hash (Join-Path $installed $name)) -cne $new[$name]) { Fail 'POSTSTART_HASH_DRIFT' }
        }
        $code = 'INSTALLED_OWNER_READY'
        }
    }
} catch {
    $errorReason = [string]$_.Exception.Message
    if ($stopped) {
        # Never touch code while any Owner worker might still have work.
        try {
            if ($touched) {
                [void](RestoreOriginal)
            } elseif (@(Workers).Count -eq 0) {
                if (-not (WaitOwner $oldPid)) { Fail 'OLD_OWNER_NOT_READY' }
            } else { Fail 'OWNER_STOP_UNCERTAIN' }
            $code = 'ROLLED_BACK_OWNER_READY'
        } catch { throw 'OWNER_SELECTOR_INSTALL_ROLLBACK_UNCERTAIN_PRIVATE_LOG' }
    } elseif ($errorReason -cmatch '^SELECTOR_(PENDING_OWNER_EVENT|P2_ACTIVE_OR_UNCERTAIN|INSTALLED_BASELINE_DRIFT|PARTIAL_INSTALL_NEEDS_RECONCILIATION|OWNER_TASK_NOT_RUNNABLE|READY_TASK_WITHOUT_OWNER|READY_OWNER_IDENTITY_DRIFT|STAGED_IMPORT_FAILED|SOURCE_HASH_DRIFT)$') {
        $code = $errorReason
    } else { throw 'OWNER_SELECTOR_INSTALL_FAILED_BEFORE_STOP_PRIVATE_LOG' }
} finally {
    if ($null -ne $stage -and (Test-Path -LiteralPath $stage -PathType Container)) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
WriteSummary $code
Write-Output ('OWNER_SELECTOR_INSTALL=' + $code)
