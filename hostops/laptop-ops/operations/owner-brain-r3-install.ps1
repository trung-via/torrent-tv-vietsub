# One existing Owner Task, one pinned staged R3 release, one reversible update.
# Owner-interactive only. No provider, TorrServer API call, cache deletion, or TV action.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$p2App = Join-Path $root 'app\poc\p2-aisub'
$stage = Join-Path $root 'staged-releases\owner-brain-en-182-r3-20261123-7705971bfba9'
$p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$cache = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\subtitle-trials'
$healthPath = Join-Path $root 'agent-health.json'
$backupRoot = Join-Path $root 'backups'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$expected = [ordered]@{
    'automatic_vietsub_flow.py' = '86423538c3c04a37e02d308a26edea07666693b4eae2e43281229fecd3661e27'
    'brain_english_inbox.py' = '61d64d3c170b325f587d82220b2e2b23aee196496a24d655fd3dae9b34f3f2fb'
    'owner_p3_p4_runtime.py' = 'a8af95433fc256082636440e74fa3343912f56b4a45b483948af00a9ce4898e3'
    'owner_r2_progressive_registry.py' = '91278b64505c7dc88acc93f76240290f873243ffeff4c2901c07ec6d7fa9d963'
    'owner_session_bridge.py' = '636e91b671527730a9ce59a937768d254b865ee8be8557d823af9424c3e5b0a8'
    'p3_p4_shared_https_route_r0.py' = '1e700b3f0788ce91265a627b99baff9f3874d91102d5b87088e974531f67e8e6'
    'p3_signed_signal_to_owner.py' = '842a900b1b0fc9ea6e670774685e47b3f02f9309c3a1f6f95bd09772f2fd4108'
    'agy_opensubtitles_acquisition.py' = 'dcf4282926067dce8e1e05f9be9d36aa1e96443bbe2710c134b0eaedec9debce'
    'matcher.py' = '18df6d45786caff6d5c97a11f6d463afeb21820f5766a4d944c3e2f6a1418b83'
    'opensubtitles.py' = '3711dab1d40de9751d17cb3b5d9fbe485c644e6e2488b05e7d248cf5bb93a3f0'
    'owner_selected_file_resolver.py' = '93ab4f62eded98bfad3c3b8322536fe0547ee80ac0b206c24f735499577b4247'
    'trusted_playback_to_owner.py' = '7e8bb7d86d5395d9d3f40feb7ada3813cb7802d4e9995fc50607076728412c47'
    'p3_owner_current_redmi.py' = '69f4da5b2cdc94781b672c9858d4adf2b03837580d78045becf768ec42fb96a0'
    'owner_r2_verified_processor.py' = '24d653ebe39dcf73c4b80b6b93872cd3af4c1ee4a27973bbae5b4d21031e433f'
    'automatic_lean120_worker.py' = '4eb92f5d8e8ef6191cab8ac8d68df99ff1d791ae800607d3c8f01bd02fc707dd'
    'progressive_handoff.py' = '782b4ac8b7d993405bbab37a6e1e2109ff2250c5efefb1d0da3a1b035c954cf3'
}
$p2Names = @('automatic_lean120_worker.py','progressive_handoff.py')
function StageFile([string]$name) {
    if ($name -in $p2Names) {
        return (Join-Path $stage ('poc\p2-aisub\' + $name))
    }
    return (Join-Path $stage ('poc\p2-sub-discovery\' + $name))
}
function InstalledFile([string]$name) {
    if ($name -in $p2Names) { return (Join-Path $p2App $name) }
    return (Join-Path $app $name)
}
function Hold([string]$reason) {
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
foreach ($dir in @($root,$app,$p2App,$stage)) { RegularDirectory $dir }
if (@(CheckTask).Count -ne 1 -or [string](CheckTask).State -cne 'Running') {
    Hold 'OWNER_NOT_RUNNING'
}
NoOpenWork
if (-not (VerifiedHeartbeat -1 0)) { Hold 'OWNER_HEARTBEAT_NOT_VERIFIED' }
$oldHealth = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
$oldPid = [long]$oldHealth.pid

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
import importlib, pathlib, sys
stage, app = (pathlib.Path(p) for p in sys.argv[1:3])
sys.path[:0] = [str(stage / "poc/p2-sub-discovery"),
                str(stage / "poc/p2-aisub"),
                str(app / "poc/p2-sub-discovery"),
                str(app / "poc/p2-aisub"),
                str(app / "poc/p3-vietsub-trigger")]
for name in ("brain_english_inbox", "automatic_vietsub_flow",
             "automatic_lean120_worker", "progressive_handoff",
             "owner_p3_p4_runtime", "owner_r2_progressive_registry",
             "p3_signed_signal_to_owner", "owner_session_bridge",
             "owner_p3_p4_entrypoint"):
    module = importlib.import_module(name)
    expected_root = app if name == "owner_p3_p4_entrypoint" else stage
    assert str(module.__file__).lower().startswith(str(expected_root).lower()), name
# This only constructs a local worker. The AGY preflight and all model calls
# are deferred by build_owner_auto_flow; no subtitle work is started here.
from automatic_vietsub_flow import build_owner_auto_flow
flow = build_owner_auto_flow(
    enabled=True, cache_root=pathlib.Path(sys.argv[3]),
    state_root=pathlib.Path(sys.argv[4]))
assert flow.worker.first_window_cues == 50
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
    candidate_sha = '4215726ea0ecae24bbac4fb94b75817c3e984e0f'
    stage_sha = '7705971bfba9b838b41d17b9caeb5e5d6418ca87'
    previous = $previous
    target = $expected
}
[IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
    ($ledger | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output 'OWNER_BRAIN_R3_BACKUP=ALL_16_ORIGINALS_RECORDED'
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
    Write-Output 'OWNER_BRAIN_R3_INSTALL=16_FILES_HASH_VERIFIED_FRESH_OWNER_RUNNING'
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
