# One existing Owner Task, one pinned staged R3 release, one reversible update.
# Owner-interactive only. No provider, TorrServer API call, cache deletion, or TV action.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$p2App = Join-Path $root 'app\poc\p2-aisub'
$stage = Join-Path $root ('staged-releases\g1-186-' + [Guid]::NewGuid().ToString('N'))
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$healthPath = Join-Path $root 'agent-health.json'
$backupRoot = Join-Path $root 'backups'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$expected = [ordered]@{
    'automatic_lean120_worker.py' = '826d1a2eefa8efc805fd86a77dce10eef6fa50dfa98ce9f8ebb6e8811930839b'
    'automatic_vietsub_flow.py' = 'e3d1e6da2c8d08ae428f97fbae2d188e5817103dfc8bda7ed2c8a6e13f18792a'
    'owner_full_flow_snapshot_v4.py' = 'abbc90507a179c5aa5c6a9402e11dfcd77a3a639629662f47dc1436cb0ca1210'
    'owner_r2_progressive_registry.py' = 'c234749c1f9165d3436d344546b8b97089ff73c1e361aa225d0e0cb544320346'
    'owner_r2_progressive_worker.py' = 'a8b0243ddd91ba7390177f55f904ef30273e39635a1f20f4c505e0f9fab26527'
}
$p2Names = @('automatic_lean120_worker.py','translator_profile.json')
$launcher = $null
function StageFile([string]$name) {
    if ($name -ceq 'start-owner-session-agent.ps1') { return (Join-Path $stage $name) }
    if ($name -in $p2Names) {
        return (Join-Path $stage ('poc\p2-aisub\' + $name))
    }
    return (Join-Path $stage ('poc\p2-sub-discovery\' + $name))
}
function InstalledFile([string]$name) {
    if ($name -ceq 'start-owner-session-agent.ps1') { return $launcher }
    if ($name -in $p2Names) { return (Join-Path $p2App $name) }
    return (Join-Path $app $name)
}
function Hold([string]$reason) {
    try {
        $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
        $rq = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
        if ($rq.nonce -cmatch '^[0-9a-f]{32}$' -and $reason -cmatch '^[A-Z0-9_]{3,80}$') {
            $report = @{schema='TTV-G1-INSTALL-HOLD-V1';nonce=$rq.nonce;reason=$reason}
            [IO.File]::WriteAllText((Join-Path $spool ('Receipts\g1-186-hold-' + $rq.nonce + '.json')),($report|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
        }
    } catch {}
    Write-Output ('OWNER_BRAIN_R3=HOLD_' + $reason)
    throw 'OWNER_BRAIN_R3_INSTALL_HOLD'
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function RegularDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_INVALID'
    }
}
function RegularFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_INVALID'
    }
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $ownerSid -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function Workers {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    RegularDirectory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'PENDING_OWNER_EVENTS'
    }
    if (Test-Path -LiteralPath $p2) {
        RegularDirectory $p2
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_INFLIGHT_OR_ACTIVE_LOCK'
            }
        }
    }
}
function VerifiedHeartbeat([long]$rejectPid, [long]$freshSince) {
    if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { return $false }
    try {
        RegularFile $healthPath
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { return $false }
        $h = Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $h.state -cne 'READY' -or $h.pid -isnot [ValueType] -or
            [long]$h.pid -le 0 -or [long]$h.pid -eq $rejectPid -or
            [long]$h.observed_utc_epoch -lt $freshSince) { return $false }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { return $false }
        $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
        if (-not $worker -or
            [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
            return $false
        }
        $sid = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        return ($sid.ReturnValue -eq 0 -and $sid.Sid -ceq $ownerSid)
    } catch { return $false }
}
function StopOwner {
    NoOpenWork
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -cne 'Disabled') { Hold 'OWNER_TASK_STATE_UNKNOWN' }
    for ($n = 0; $n -lt 5; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    # Exactly scoped Owner-owned residual processes: never terminate other Python.
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_SET_UNEXPECTED' }
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($w in $workers) {
        $hits = @($allowed | Where-Object {
            [string]$w.CommandLine -and
            $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($hits.Count -ne 1 -or -not $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($w in $workers) {
        NoOpenWork
        if ([string](CheckTask).State -cne 'Disabled') { Hold 'RESIDUAL_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$w.ProcessId)
        if ($null -eq $live) { continue }
        $sid = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ([string]$live.CommandLine -cne [string]$w.CommandLine -or
            $live.CreationDate -ne $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_CHANGED'
        }
        Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
    }
    for ($n = 0; $n -lt 10; $n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_NOT_STOPPED'
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 1
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($n = 0; $n -lt 30; $n++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -cne 'Running') { continue }
        if (VerifiedHeartbeat $oldPid $since) { return $true }
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
foreach ($dir in @($root,$app,$p2App)) { RegularDirectory $dir }
$action = [string](CheckTask).Actions[0].Arguments
if ($action -notmatch '(?i)-File\s+"([^"]+start-owner-session-agent\.ps1)"') { Hold 'LAUNCHER_PATH_UNVERIFIED' }
$launcher = [IO.Path]::GetFullPath($Matches[1])
if (-not $launcher.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { Hold 'LAUNCHER_OUTSIDE_OWNER_ROOT' }
RegularFile $launcher
[IO.Directory]::CreateDirectory((Join-Path $stage 'poc\p2-sub-discovery')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $stage 'poc\p2-aisub')) | Out-Null
foreach ($name in @($expected.Keys)) {
    $subdir = if ($name -in $p2Names) {'p2-aisub'} else {'p2-sub-discovery'}
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/c707f0844eb8032e999054ece61dcc7e5ef8543f/poc/' + $subdir + '/' + $name
    Invoke-WebRequest -Uri $uri -OutFile (StageFile $name) -TimeoutSec 30 -ErrorAction Stop
    if ((Hash (StageFile $name)) -cne $expected[$name]) { Hold 'PINNED_SOURCE_HASH_MISMATCH' }
}
# Two explicit local configuration changes, separately backed up and hashed.
$profilePath = StageFile 'translator_profile.json'
[IO.File]::WriteAllText($profilePath,'{"provider":"antigravity","model":"gemini-4-hydrogen-low","thinking_level":"low"}',[Text.UTF8Encoding]::new($false))
$expected['translator_profile.json'] = Hash $profilePath
$launchText = [IO.File]::ReadAllText($launcher)
$launchAnchor = '    $env:PYTHONUTF8 = ''1'''
if ($launchText.Contains('TTV_LEAN120_PARALLEL_BATCHES') -or
    [regex]::Matches($launchText,[regex]::Escape($launchAnchor)).Count -ne 1) { Hold 'LAUNCHER_CONFIG_DRIFT' }
$launchText = $launchText.Replace($launchAnchor, $launchAnchor + [Environment]::NewLine + '    $env:TTV_LEAN120_PARALLEL_BATCHES = ''3''')
[IO.File]::WriteAllText((StageFile 'start-owner-session-agent.ps1'),$launchText,[Text.UTF8Encoding]::new($false))
$tokens=$null; $parseErrors=$null
[Management.Automation.Language.Parser]::ParseFile((StageFile 'start-owner-session-agent.ps1'),[ref]$tokens,[ref]$parseErrors) | Out-Null
if (@($parseErrors).Count -ne 0) { Hold 'LAUNCHER_PARSE_FAILED' }
$expected['start-owner-session-agent.ps1'] = Hash (StageFile 'start-owner-session-agent.ps1')
$taskState = [string](CheckTask).State
if ($taskState -cnotin @('Running','Ready','Disabled')) { Hold 'OWNER_TASK_STATE_UNKNOWN' }
NoOpenWork
$oldPid = 0L
if ($taskState -ceq 'Running') {
    if (-not (VerifiedHeartbeat -1 0)) { Hold 'OWNER_HEARTBEAT_NOT_VERIFIED' }
    $oldPid = [long](Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json).pid
} elseif (@(Workers).Count -ne 0) {
    Hold 'STOPPED_OWNER_RESIDUAL_WORKER_HOLD'
}

# Entrypoint is intentionally NOT part of the 16-file patch; the exact
# installed version is already the reviewed candidate and must stay so.
$entry = Join-Path $app 'owner_p3_p4_entrypoint.py'
RegularFile $entry
if ((Hash $entry) -cne 'acaa545be25d397b4ab85276516e92fdc99316f58063f69fcd620b8af0198c2c') {
    Hold 'INSTALLED_ENTRYPOINT_SHA_DRIFT'
}
foreach ($name in $expected.Keys) {
    $src = StageFile $name
    RegularFile $src
    if ((Hash $src) -cne $expected[$name]) { Hold 'STAGED_SOURCE_SHA_DRIFT' }
}
# Fail before touching the running Owner if staged modules cannot import
# against existing Owner dependencies. This is a smoke, not real provider/TV.
$overlay = @'
import importlib, pathlib, sys, os
stage, app = (pathlib.Path(p) for p in sys.argv[1:3])
sys.path[:0] = [str(stage / "poc/p2-sub-discovery"), str(stage / "poc/p2-aisub"), str(app / "poc/p2-sub-discovery"), str(app / "poc/p2-aisub"), str(app / "poc/p3-vietsub-trigger")]
for name in ("automatic_vietsub_flow","automatic_lean120_worker","owner_r2_progressive_registry","owner_r2_progressive_worker","owner_full_flow_snapshot_v4","owner_p3_p4_entrypoint"):
    importlib.import_module(name)
from automatic_vietsub_flow import build_owner_auto_flow
import owner_vietsub_pipeline
owner_vietsub_pipeline._P2=stage / "poc/p2-aisub"
os.environ["TTV_LEAN120_PARALLEL_BATCHES"]="3"
flow=build_owner_auto_flow(enabled=True,cache_root=pathlib.Path(sys.argv[3]),state_root=pathlib.Path(sys.argv[4]))
assert flow.worker.first_window_cues==50 and flow.worker.parallel_batches==3
assert flow.worker.profile.model=="gemini-4-hydrogen-low" and flow.worker.preserve_hydrogen_jobs
print("OWNER_BRAIN_R3_STAGED_OVERLAY=PASS")
'@
$import = @(& py -3 -I -B -c $overlay $stage (Join-Path $root 'app') $cache $p2 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($import | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_STAGED_OVERLAY=PASS' }).Count -ne 1) {
    Hold 'STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED'
}
Write-Output 'OWNER_BRAIN_R3_PREFLIGHT=PASS_OWNER_RUNNING_IDLE_STAGED_IMPORT'

if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
}
RegularDirectory $backupRoot
$backup = Join-Path $backupRoot ('owner-brain-r3-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($backup) | Out-Null
$previous = [ordered]@{}
foreach ($name in $expected.Keys) {
    $file = InstalledFile $name
    if (Test-Path -LiteralPath $file) {
        RegularFile $file
        $previous[$name] = Hash $file
        $saved = Join-Path $backup $name
        [IO.File]::Copy($file,$saved,$false)
        if ((Hash $saved) -cne $previous[$name]) { Hold 'BACKUP_HASH_INVALID' }
    } else { $previous[$name] = 'MISSING' }
}
$ledger = [ordered]@{
    schema = 'TTV-OWNER-BRAIN-R3-BACKUP-V1'
    candidate_sha = 'c707f0844eb8032e999054ece61dcc7e5ef8543f'
    stage_sha = 'c707f0844eb8032e999054ece61dcc7e5ef8543f'
    previous = $previous
    target = $expected
}
[IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
    ($ledger | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output 'OWNER_BRAIN_R3_BACKUP=ALL_7_ORIGINALS_RECORDED'
$stopped = $false
try {
    NoOpenWork
    StopOwner
    $stopped = $true
    NoOpenWork
    foreach ($name in $expected.Keys) {
        if ([string](CheckTask).State -cne 'Disabled' -or @(Workers).Count -ne 0) {
            Hold 'OWNER_NOT_STOPPED_DURING_APPLY'
        }
        $src = StageFile $name
        $file = InstalledFile $name
        if ((Hash $src) -cne $expected[$name]) { Hold 'SOURCE_CHANGED_DURING_APPLY' }
        if ($previous[$name] -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) { Hold 'NEW_MODULE_PATH_CONFLICT' }
        } elseif ((Hash $file) -cne $previous[$name]) {
            Hold 'INSTALLED_BASELINE_CHANGED'
        }
        if ($previous[$name] -ceq $expected[$name]) { continue }
        $temp = Join-Path (Split-Path -Parent $file) ('.brain-r3-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($src,$temp,$false)
        if ((Hash $temp) -cne $expected[$name]) { Hold 'TEMP_COPY_DRIFT' }
        if ($previous[$name] -ceq 'MISSING') {
            [IO.File]::Move($temp,$file)
        } else {
            $displaced = Join-Path $backup ('displaced-' + $name)
            [IO.File]::Replace($temp,$file,$displaced)
        }
        if ((Hash $file) -cne $expected[$name]) { Hold 'POST_REPLACE_HASH_CHANGED' }
    }
    Push-Location -LiteralPath $app
    try {
        $installedCheck = 'import sys;sys.path.insert(0,sys.argv[1]);import owner_p3_p4_entrypoint,brain_english_inbox;print("OWNER_BRAIN_R3_IMPORT_PASS")'
        $verify = @(& py -3 -I -B -c $installedCheck $app 2>&1)
        if ($LASTEXITCODE -ne 0 -or
            @($verify | Where-Object { [string]$_ -ceq 'OWNER_BRAIN_R3_IMPORT_PASS' }).Count -ne 1) {
            Hold 'OFFLINE_IMPORT_FAILED'
        }
    } finally { Pop-Location }
    NoOpenWork
    if (-not (StartOwner $oldPid)) { Hold 'FRESH_OWNER_NOT_VERIFIED' }
    Write-Output 'OWNER_BRAIN_R3_INSTALL=7_FILES_HASH_VERIFIED_FRESH_OWNER_RUNNING'
    foreach ($name in $expected.Keys) { if ((Hash (InstalledFile $name)) -cne $expected[$name]) { Hold 'POST_START_HASH_DRIFT' } }
    Write-Output 'OWNER_G1_CONFIG=HYDROGEN_LOW_PARALLEL_3'
    Write-Output 'OWNER_BRAIN_R3_PROVIDER_TV=NOT_RUN'
    Write-Output 'OWNER_BRAIN_R3_CACHE_CHECKPOINTS=UNCHANGED'
} catch {
    $failure = $_
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ATTEMPTING_PRIVATE_ROLLBACK'
    if (-not $stopped) {
        # No source files were changed. Restore availability only if the
        # previous owner worker has exited and the queue remains untouched.
        if (@(Workers).Count -eq 0 -and
            [string](CheckTask).State -ceq 'Disabled') {
            NoOpenWork
            if (StartOwner $oldPid) {
                Write-Output 'OWNER_BRAIN_R3_RECOVERY=NO_FILES_CHANGED_OLD_OWNER_RUNNING'
            }
        }
        throw
    }
    StopOwner
    foreach ($name in $expected.Keys) {
        $file = InstalledFile $name
        $old = [string]$previous[$name]
        $new = [string]$expected[$name]
        if ($old -ceq $new) { continue }
        if ($old -ceq 'MISSING') {
            if (Test-Path -LiteralPath $file) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_NEW_FILE_DRIFT' }
                [IO.File]::Delete($file)
            }
        } else {
            $saved = Join-Path $backup $name
            if ((Hash $saved) -cne $old) { Hold 'ROLLBACK_BACKUP_DRIFT' }
            if ((Hash $file) -cne $old) {
                if ((Hash $file) -cne $new) { Hold 'ROLLBACK_INSTALLED_DRIFT' }
                $temp = Join-Path (Split-Path -Parent $file) ('.brain-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy($saved,$temp,$false)
                $displaced = Join-Path $backup ('failed-' + $name)
                [IO.File]::Replace($temp,$file,$displaced)
            }
            if ((Hash $file) -cne $old) { Hold 'ROLLBACK_ORIGINAL_HASH_CHANGED' }
        }
    }
    if (-not (StartOwner $oldPid)) { Hold 'ROLLBACK_OWNER_HEARTBEAT_FAILED_TASK_HOLD' }
    Write-Output 'OWNER_BRAIN_R3_RECOVERY=ORIGINAL_OWNER_RESTORED'
    throw 'OWNER_BRAIN_R3_INSTALL_FAILED_ROLLED_BACK'
}
