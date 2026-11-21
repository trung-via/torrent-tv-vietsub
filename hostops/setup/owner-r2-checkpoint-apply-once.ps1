# Fixed, one-shot Owner-interactive installation of the five staged R2/P4
# checkpoint modules. The Owner explicitly authorized stopping the current
# translation on 2026-11-21. Preserve P2 inflight/lock/event bytes unchanged;
# NEVER retry a provider call here. A separate HostOps task may only trigger
# this exact installed helper after one-time Owner enrollment.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$release = 'r2-checkpoint-175'
$stageCommit = '5ab8a2dd6e09c2eeef83b473e82b2ff4c758e961'
$files = [ordered]@{
    'poc/p2-aisub/paired_activation.py' = 'fbba82a269848fa74b24da37e9dfdd14ccdaf539851e916ba2026f59117b7ff2'
    'poc/p2-sub-discovery/owner_r2_progressive_registry.py' = 'e7bf7ed53e55837f0b34517d0aefc7205711d9a4b76bc6c67c6e12c276cd0a02'
    'poc/p2-sub-discovery/owner_session_bridge.py' = '2ee9061743852092e3543245e7b711656774b2f615fabcff39a13cb92b4c695e'
    'poc/p2-sub-discovery/p3_owner_state_wiring_r2.py' = '8b285ca33fe8aa2fc24e6c7d1af616150a5fec181d0ac40f56c51910ac6b7a0d'
    'poc/p2-sub-discovery/p3_p4_shared_https_route_r0.py' = '7358cfafa901fa0a74743450302d99cb7ee370561c28fa336a73535498a7dadf'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$stage = Join-Path $root ('staged-releases\owner-' + $release + '-' + $stageCommit.Substring(0,12))
$healthPath = Join-Path $root 'agent-health.json'
$recoveryRoot = Join-Path $root 'recovery'
$receiptPath = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\checkpoint-apply.json'

function Hold([string]$code) { throw ('OWNER_CHECKPOINT_APPLY_HOLD_' + $code) }
function CheckFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_ABSENT_OR_REPARSE'
    }
}
function CheckDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_ABSENT_OR_REPARSE'
    }
}
function SHA([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function WriteReceipt([string]$result) {
    $record = [ordered]@{schema='TTV-OWNER-CHECKPOINT-APPLY-V1'; release_id=$release;
        stage_commit=$stageCommit; result=$result;
        observed_utc_epoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    $temp = $receiptPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($record | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp,$receiptPath,$true)
    Write-Output ('OWNER_CHECKPOINT_APPLY=' + $result)
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertWorkerIdentities($list) {
    if (@($list).Count -gt 4) { Hold 'TOO_MANY_OWNER_WORKERS' }
    $allowed = @((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
        (Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($p in $list) {
        if ($null -eq $p.CreationDate -or
            @($allowed | Where-Object { [string]$p.CommandLine -and
                $p.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -ne 1) {
            Hold 'UNKNOWN_WORKER_COMMAND'
        }
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne $identity.User.Value) {
            Hold 'WORKER_OWNER_MISMATCH'
        }
    }
}
function StopOwner {
    $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    if ([string]$current.State -notin @('Running','Ready','Disabled')) { Hold 'TASK_STATE_UNEXPECTED' }
    if ([string]$current.State -cne 'Disabled') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$current.State -ceq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    }
    for ($n=0;$n -lt 10;$n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $stuck = @(Workers)
    AssertWorkerIdentities $stuck
    foreach ($p in $stuck) {
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$p.ProcessId)
        if ($null -eq $live) { continue }
        if ([string]$live.CommandLine -cne [string]$p.CommandLine -or
            $live.CreationDate -ne $p.CreationDate) { Hold 'WORKER_CHANGED' }
        AssertWorkerIdentities @($live)
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop
    }
    for ($n=0;$n -lt 10;$n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'WORKER_NOT_STOPPED'
}
function StartAndVerify([long]$oldPid) {
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($n=0;$n -lt 45;$n++) {
        Start-Sleep -Seconds 1
        if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Running') { continue }
        if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { continue }
        CheckFile $healthPath
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { continue }
        try { $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json -AsHashtable }
        catch { continue }
        if (-not $h.Contains('schema') -or -not $h.Contains('state') -or
            -not $h.Contains('pid') -or -not $h.Contains('observed_utc_epoch') -or
            $h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or
            $h.pid -isnot [ValueType] -or [long]$h.pid -le 0 -or
            [long]$h.pid -eq $oldPid -or $h.observed_utc_epoch -isnot [ValueType]) { continue }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { continue }
        $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid) -ErrorAction SilentlyContinue
        if ($null -eq $p -or [string]$p.CommandLine -notmatch
            'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') { continue }
        AssertWorkerIdentities @($p)
        return $true
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($root,$app,$stage,(Split-Path -Parent $receiptPath))) { CheckDir $dir }
if (Test-Path -LiteralPath $receiptPath) { Hold 'ALREADY_ATTEMPTED_NO_REPLAY' }
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$ownerSid = [string]$task.Principal.UserId
if ($ownerSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $ownerSid = ([Security.Principal.NTAccount]::new($ownerSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($ownerSid -cne $identity.User.Value -or [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    -not [IO.Path]::GetFileName([string]$task.Actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1' -or
    [string]$task.State -cne 'Running') { Hold 'ORIGINAL_OWNER_TASK_DRIFT' }

# The enrolled stage helper leaves the manifest in its private scratch
# directory. Pin the immutable stage commit in the destination directory
# and all five content hashes instead of relying on a nonexistent copy.
$old = [ordered]@{}
foreach ($rel in $files.Keys) {
    $source = Join-Path $stage $rel.Replace('/','\')
    $destination = Join-Path $app $rel.Replace('/','\')
    CheckFile $source; CheckFile $destination
    if ((SHA $source) -cne $files[$rel]) { Hold 'STAGED_HASH_DRIFT' }
    $old[$rel] = SHA $destination
}
# Read-only Python syntax gate before touching a running Owner.
$syntax = @'
import pathlib,sys
for name in sys.argv[1:]:
    p=pathlib.Path(name)
    compile(p.read_bytes(),str(p),'exec')
print('R2_CHECKPOINT_SYNTAX_PASS')
'@
$sources = @($files.Keys | ForEach-Object { Join-Path $stage $_.Replace('/','\') })
$parsed = @(& py -3 -I -B -c $syntax @sources 2>$null)
if ($LASTEXITCODE -ne 0 -or 'R2_CHECKPOINT_SYNTAX_PASS' -notin $parsed) {
    Hold 'STAGED_PYTHON_SYNTAX_FAILED'
}
$oldPid = 0L
if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
    try {
        $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
        if ($h.pid -is [ValueType]) { $oldPid = [long]$h.pid }
    } catch { $oldPid = 0L }
}
AssertWorkerIdentities @(Workers)
if (-not (Test-Path -LiteralPath $recoveryRoot)) {
    New-Item -ItemType Directory -Path $recoveryRoot -ErrorAction Stop | Out-Null
}
CheckDir $recoveryRoot
$backup = Join-Path $recoveryRoot ('owner-r2-checkpoint-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
foreach ($rel in $files.Keys) {
    $source = Join-Path $app $rel.Replace('/','\')
    $target = Join-Path $backup $rel.Replace('/','\')
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force -ErrorAction Stop | Out-Null
    [IO.File]::Copy($source,$target,$false)
    if ((SHA $target) -cne $old[$rel]) { Hold 'BACKUP_HASH_FAILED_OWNER_UNCHANGED' }
}
$record = [ordered]@{schema='TTV-OWNER-CHECKPOINT-ROLLBACK-V1';
    stage_commit=$stageCommit; previous=$old}
[IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),($record | ConvertTo-Json -Depth 4),
    [Text.UTF8Encoding]::new($false))

# Explicit Human-authorized interruption: current paid batch may have an
# unknown effect. Neither the active lock nor any P2 state is removed.
$modified = [Collections.Generic.List[string]]::new()
try {
    WriteReceipt 'STARTED_OWNER_STOP_P2_STATE_PRESERVED'
    StopOwner
    foreach ($rel in $files.Keys) {
        $src = Join-Path $stage $rel.Replace('/','\')
        $dst = Join-Path $app $rel.Replace('/','\')
        if ((SHA $src) -cne $files[$rel] -or (SHA $dst) -cne $old[$rel]) {
            Hold 'STAGE_OR_INSTALLED_CHANGED_DURING_APPLY'
        }
        $temp = Join-Path (Split-Path -Parent $dst) ('.r2-checkpoint-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($src,$temp,$false)
        if ((SHA $temp) -cne $files[$rel]) { Hold 'TEMP_HASH_DRIFT' }
        $modified.Add($rel)
        [IO.File]::Move($temp,$dst,$true)
        if ((SHA $dst) -cne $files[$rel]) { Hold 'INSTALLED_HASH_DRIFT' }
    }
    if (-not (StartAndVerify $oldPid)) { Hold 'NEW_OWNER_NOT_HEALTHY' }
    WriteReceipt 'INSTALLED_OWNER_FRESH_P2_STATE_PRESERVED'
} catch {
    $failure = $_
    try {
        StopOwner
        foreach ($rel in $modified) {
            $dst = Join-Path $app $rel.Replace('/','\')
            $source = Join-Path $backup $rel.Replace('/','\')
            if ((SHA $source) -cne $old[$rel]) { Hold 'ROLLBACK_BACKUP_DRIFT' }
            $temp = Join-Path (Split-Path -Parent $dst) ('.r2-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy($source,$temp,$false)
            [IO.File]::Move($temp,$dst,$true)
        }
        foreach ($rel in $files.Keys) {
            if ((SHA (Join-Path $app $rel.Replace('/','\'))) -cne $old[$rel]) {
                Hold 'ROLLBACK_VERIFY_FAILED'
            }
        }
        if (-not (StartAndVerify $oldPid)) { Hold 'ROLLED_BACK_OLD_OWNER_NOT_HEALTHY' }
        WriteReceipt 'ROLLED_BACK_OLD_OWNER_FRESH'
    } catch {
        WriteReceipt 'HOLD_OWNER_DISABLED_OR_RECOVERY_UNVERIFIED'
        throw
    }
    throw $failure
}
