# Owner-interactive, exact one-file P2 translator text-QA hotfix. Preserve the
# unknown installed Owner bridge byte-for-byte. No provider, TV, queue, P2
# marker, or checkpoint operation. Roll back if restart fails.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$stage = Join-Path $root 'staged-releases\owner-p2-text-qa-v1-39f2a63787b0'
$healthPath = Join-Path $root 'agent-health.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$files = [ordered]@{
    'poc/p2-aisub/translator_gateway.py' = @{
        new = 'd63c468a6417fab87d6c9e56e6dd319ddc28289f7c95eb064eaf9684d5774fc3'
        previous = @('b06c151cc4275a7793fdb7891d7859715e602a676a553ea89e6e242578190183')
    }
}
$backup = $null
$stopped = $false
$oldPid = 0L
$bridgePath = Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'
$bridgeShaBefore = ''

function Hold([string]$reason) {
    Write-Output ('P2_TEXT_QA_OWNER=HOLD_' + $reason)
    throw 'P2_TEXT_QA_OWNER_HOLD'
}
function File([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_REPARSE'
    }
}
function Directory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_REPARSE'
    }
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
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
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function NoOpenP2 {
    $inbox = Join-Path $root 'inbox'
    Directory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    if (Test-Path -LiteralPath $stateRoot -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'active.lock').Count -gt 0) {
            Hold 'P2_ACTIVE_PROVIDER_JOB'
        }
        # The known unknown-effect batch remains untouched throughout install.
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight').Count -gt 1) {
            Hold 'UNEXPECTED_MULTIPLE_P2_MARKERS'
        }
    }
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function StopOwner {
    $task = Task
    if ([string]$task.State -cin @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -ceq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -cne 'Disabled') {
        Hold 'OWNER_UNEXPECTED_STATE'
    }
    for ($i=0; $i -lt 9; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenP2
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT' }
    $allowed = @((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matched = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matched.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Hold 'RESIDUAL_WORKER_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenP2
        if ([string](Task).State -cne 'Disabled') { Hold 'OWNER_REENABLED_DURING_STOP' }
        $live = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $who = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_WORKERS_STILL_RUNNING'
}
function StartOwner([long]$previousPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -cne 'Running' -or
            -not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { continue }
        try { $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json }
        catch { continue }
        if ($health.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $health.state -cne 'READY' -or $health.pid -isnot [ValueType] -or
            [long]$health.pid -le 0 -or [long]$health.pid -eq $previousPid -or
            $health.observed_utc_epoch -isnot [ValueType] -or
            [long]$health.observed_utc_epoch -lt ($since - 2)) { continue }
        $worker = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$health.pid) -ErrorAction SilentlyContinue
        if ($null -eq $worker -or
            [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') { continue }
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid) { return $true }
    }
    return $false
}
function ReplacePinned([string]$source,[string]$destination,[string]$digest) {
    File $source
    File $destination
    $temp = Join-Path (Split-Path -Parent $destination) (
        '.p2-gateway-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::Copy($source,$temp,$false)
    try {
        if ((Hash $temp) -cne $digest) { Hold 'STAGED_TEMP_HASH_DRIFT' }
        [IO.File]::Move($temp,$destination,$true)
        if ((Hash $destination) -cne $digest) { Hold 'INSTALLED_HASH_MISMATCH' }
    } finally {
        if (Test-Path -LiteralPath $temp) { [IO.File]::Delete($temp) }
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($root,$app,$stage)) { Directory $dir }
$bridgeShaBefore = Hash $bridgePath
$ownerTask = Task
if ([string]$ownerTask.State -cnotin @('Running','Ready')) { Hold 'OWNER_NOT_READY_TO_PATCH' }
NoOpenP2
foreach ($rel in $files.Keys) {
    $from = Join-Path $stage ($rel.Replace('/','\'))
    $to = Join-Path $app ($rel.Replace('/','\'))
    File $from
    File $to
    if ((Hash $from) -cne $files[$rel].new) { Hold 'STAGE_HASH_DRIFT' }
    $oldHash = Hash $to
    if ($oldHash -cne $files[$rel].new -and
        $oldHash -cnotin $files[$rel].previous) { Hold 'INSTALLED_VERSION_UNRECOGNIZED' }
}
if (@($files.Keys | Where-Object {
    (Hash (Join-Path $app ($_.Replace('/','\')))) -cne $files[$_].new
}).Count -eq 0) {
    Write-Output 'P2_TEXT_QA_OWNER=ALREADY_INSTALLED_EXACT_HASH'
    return
}

$recovery = Join-Path $root 'recovery'
if (-not (Test-Path -LiteralPath $recovery)) {
    New-Item -ItemType Directory -Path $recovery -ErrorAction Stop | Out-Null
}
Directory $recovery
$backup = Join-Path $recovery ('p2-gateway-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
$previous = [ordered]@{}
foreach ($rel in $files.Keys) {
    $to = Join-Path $app ($rel.Replace('/','\'))
    $saved = Join-Path $backup ($rel.Replace('/','\'))
    $parent = Split-Path -Parent $saved
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
    }
    [IO.File]::Copy($to,$saved,$false)
    $digest = Hash $to
    if ((Hash $saved) -cne $digest) { Hold 'BACKUP_HASH_MISMATCH' }
    $previous[$rel] = $digest
}
if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
    try {
        $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
        if ($health.pid -is [ValueType]) { $oldPid = [long]$health.pid }
    } catch { $oldPid = 0L }
}

try {
    $stopped = $true
    StopOwner
    NoOpenP2
    foreach ($rel in $files.Keys) {
        $to = Join-Path $app ($rel.Replace('/','\'))
        if ((Hash $to) -cne $previous[$rel]) { Hold 'INSTALLED_CHANGED_AFTER_BACKUP' }
        ReplacePinned (Join-Path $stage ($rel.Replace('/','\'))) $to $files[$rel].new
    }
    if (-not (StartOwner $oldPid)) { Hold 'NEW_OWNER_NOT_HEALTHY' }
    if ((Hash $bridgePath) -cne $bridgeShaBefore) { Hold 'OWNER_BRIDGE_DRIFT' }
    $stopped = $false
    Write-Output 'P2_TEXT_QA_OWNER=INSTALLED_HASH_VERIFIED_OWNER_RUNNING'
    Write-Output 'P2_TEXT_QA_P2_MARKERS=UNCHANGED'
    Write-Output 'P2_TEXT_QA_PROVIDER_TV=NOT_RUN'
} catch {
    if ($stopped) {
        # If any file was replaced, restore exactly the verified, private
        # pre-install bytes, then attempt to bring the old Owner back online.
        try {
            StopOwner
            foreach ($rel in $files.Keys) {
                $saved = Join-Path $backup ($rel.Replace('/','\'))
                $to = Join-Path $app ($rel.Replace('/','\'))
                if ((Hash $saved) -cne $previous[$rel]) { Hold 'ROLLBACK_BACKUP_DRIFT' }
                ReplacePinned $saved $to $previous[$rel]
            }
            if (StartOwner $oldPid) {
                Write-Output 'P2_TEXT_QA_OWNER=ROLLED_BACK_OLD_OWNER_RUNNING'
            } else {
                Write-Output 'P2_TEXT_QA_OWNER=HOLD_OLD_OWNER_RESTART_FAILED'
            }
        } catch {
            Write-Output 'P2_TEXT_QA_OWNER=HOLD_ROLLBACK_FAILED_OWNER_MAY_BE_DISABLED'
        }
    }
    throw 'P2_TEXT_QA_OWNER_INSTALL_FAILED_NO_RETRY'
}
