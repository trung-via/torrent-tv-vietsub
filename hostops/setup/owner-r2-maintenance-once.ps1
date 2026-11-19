# Owner-interactive one-shot R2 maintenance. Inspect is default; -ApplyR2
# requires a separate explicit Human action. Never executes in GitHub Actions,
# NETWORK_SERVICE, a background service session, or on a TV.
[CmdletBinding()]
param(
    [switch]$ApplyR2,
    [switch]$ResumeAfterStoppedTaskHold
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Hold([string]$reason) {
    Write-Output ('OWNER_R2_MAINTENANCE=HOLD_' + $reason)
    throw 'OWNER_R2_MAINTENANCE_HOLD'
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function RegularFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_REPARSE'
    }
}
function RegularDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_REPARSE'
    }
}
function OwnerWorkers {
    return @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $pending = @(Get-ChildItem -LiteralPath (Join-Path $ownerRoot 'inbox') -File -Filter 'event-*.json')
    if ($pending.Count -ne 0) { Hold 'PENDING_EVENTS' }
    if (Test-Path -LiteralPath $stateRoot) {
        RegularDirectory $stateRoot
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight').Count -ne 0) {
            Hold 'UNCERTAIN_P2_INFLIGHT'
        }
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'active.lock').Count -ne 0) {
            Hold 'ACTIVE_P2_LOCK'
        }
    }
}
function StopVerifiedResidualOwnerWorkers {
    # Scheduler may have stopped pwsh while leaving its py.exe/python.exe child
    # alive. Only the exact Owner-owned, installed bridge processes are eligible.
    # Validate the entire set BEFORE terminating any process.
    $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    if ([string]$current.State -cne 'Disabled') { Hold 'RESIDUAL_STOP_REQUIRES_DISABLED_TASK' }
    NoOpenWork
    $workers = @(OwnerWorkers)
    if ($workers.Count -eq 0) { return }
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT_UNEXPECTED' }
    $appDir = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
    $allowed = @(
        (Join-Path $appDir 'owner_p3_p4_entrypoint.py'),
        (Join-Path $appDir 'owner_session_bridge.py')
    )
    foreach ($worker in $workers) {
        $pathHits = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        if ($pathHits.Count -ne 1 -or $null -eq $worker.CreationDate) {
            Hold 'RESIDUAL_WORKER_PATH_OR_CREATION_UNVERIFIED'
        }
        $owner = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne $identity.User.Value) {
            Hold 'RESIDUAL_WORKER_OWNER_UNVERIFIED'
        }
    }
    $stopped = 0
    foreach ($worker in $workers) {
        NoOpenWork
        $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
        if ([string]$current.State -cne 'Disabled') {
            Hold 'RESIDUAL_TASK_STATE_CHANGED'
        }
        $live = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        if ([string]$live.CommandLine -cne [string]$worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate) {
            Hold 'RESIDUAL_WORKER_IDENTITY_CHANGED'
        }
        $owner = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne $identity.User.Value) {
            Hold 'RESIDUAL_WORKER_OWNER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
        $stopped++
    }
    Write-Output ('OWNER_R2_RESIDUAL_WORKERS_STOPPED=' + $stopped)
}
function StopOwnerForMaintenance {
    $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    if ([string]$current.State -ceq 'Running') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    } elseif ([string]$current.State -ceq 'Ready') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    } elseif ([string]$current.State -cne 'Disabled') {
        Hold 'UNEXPECTED_OWNER_TASK_STATE'
    }
    for ($i=0;$i -lt 5;$i++) {
        $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
        if ([string]$current.State -ceq 'Disabled' -and @(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    StopVerifiedResidualOwnerWorkers
    for ($i=0;$i -lt 10;$i++) {
        $current = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
        if ([string]$current.State -ceq 'Disabled' -and @(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_PROCESS_NOT_STOPPED_TASK_DISABLED'
}
function HealthyNewOwner([long]$oldPid) {
    for ($i=0;$i -lt 30;$i++) {
        Start-Sleep -Seconds 1
        $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
        if ([string]$task.State -cne 'Running') { continue }
        if (-not (Test-Path -LiteralPath $healthFile -PathType Leaf)) { continue }
        RegularFile $healthFile
        if ((Get-Item -LiteralPath $healthFile).Length -gt 512) { continue }
        try { $health = Get-Content -LiteralPath $healthFile -Raw | ConvertFrom-Json }
        catch { continue }
        if ($health.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $health.state -cne 'READY' -or
            $health.pid -isnot [ValueType] -or [long]$health.pid -le 0 -or
            [long]$health.pid -eq $oldPid -or
            $health.observed_utc_epoch -isnot [ValueType]) { continue }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$health.observed_utc_epoch
        if ($age -ge 0 -and $age -le 20) {
            $worker = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$health.pid) -ErrorAction SilentlyContinue
            if ($null -eq $worker -or
                [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') {
                continue
            }
            $owner = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
            if ($owner.ReturnValue -eq 0 -and $owner.Sid -ceq $identity.User.Value) {
                return $true
            }
        }
    }
    return $false
}
function StartOwnerAfterMaintenance([long]$oldPid) {
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    return (HealthyNewOwner $oldPid)
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
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$healthFile = Join-Path $ownerRoot 'agent-health.json'
$maintenance = Join-Path $ownerRoot 'Maintenance'
foreach ($path in @($ownerRoot,$maintenance,(Join-Path $ownerRoot 'inbox'))) {
    RegularDirectory $path
}
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
$taskSid = [string]$task.Principal.UserId
if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($taskSid -cne $identity.User.Value -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    -not [IO.Path]::GetFileName([string]$task.Actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    Hold 'OWNER_TASK_IDENTITY_DRIFT'
}
if ($ResumeAfterStoppedTaskHold -and -not $ApplyR2) {
    Hold 'RESUME_REQUIRES_APPLY_R2'
}
$applier = Join-Path $maintenance 'owner-r2-release-offline-apply.ps1'
$applierSHA = '2624d595277214bbdb95af104cffe972d382d2836aa5f8c38427dd4d9e1a2308'
$temp = Join-Path $env:TEMP ('ttv-owner-r2-applier-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        '87003ddd1ffa2b2ab2a7a05f95292f8d519a43cc/hostops/setup/owner-r2-release-offline-apply.ps1'
    Invoke-WebRequest -Uri $uri -OutFile $temp -ErrorAction Stop
    RegularFile $temp
    if ((Hash $temp) -cne $applierSHA) { Hold 'REVIEWED_APPLIER_HASH_MISMATCH' }
    if (Test-Path -LiteralPath $applier) {
        RegularFile $applier
        if ((Hash $applier) -cne $applierSHA) { Hold 'EXISTING_APPLIER_DRIFT' }
    } else {
        [IO.File]::Copy($temp,$applier,$false)
    }
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}

& pwsh -NoProfile -NonInteractive -File $applier
if ($LASTEXITCODE -ne 0) { Hold 'OWNER_R2_STAGE_INSPECTION_FAILED' }
Write-Output 'OWNER_R2_MAINTENANCE_PREFLIGHT=STAGE_VERIFIED'
if (-not $ApplyR2) {
    Write-Output 'OWNER_R2_MAINTENANCE=INSPECT_ONLY_OWNER_UNCHANGED'
    return
}
if ($ResumeAfterStoppedTaskHold) {
    if ([string]$task.State -cne 'Disabled') { Hold 'RESUME_REQUIRES_DISABLED_TASK' }
    # The reported hold occurred before -ApplyOffline or any recovery copy.
    # Do not resume an unknown or half-applied earlier release.
    $recovery = Join-Path $ownerRoot 'recovery'
    if (Test-Path -LiteralPath $recovery) {
        RegularDirectory $recovery
        if (@(Get-ChildItem -LiteralPath $recovery -Directory -Filter 'owner-r2-*').Count -ne 0) {
            Hold 'RESUME_AMBIGUOUS_R2_BACKUP_EXISTS'
        }
    }
} elseif ([string]$task.State -cne 'Running') {
    Hold 'OWNER_TASK_NOT_RUNNING_USE_EXPLICIT_RESUME_FOR_DISABLED_HOLD'
}
NoOpenWork
$oldPid = 0L
if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
    RegularFile $healthFile
    if ((Get-Item -LiteralPath $healthFile).Length -le 512) {
        try {
            $before = Get-Content -LiteralPath $healthFile -Raw | ConvertFrom-Json
            if ($before.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and
                $before.pid -is [ValueType]) { $oldPid = [long]$before.pid }
        } catch { $oldPid = 0L }
    }
}
StopOwnerForMaintenance
NoOpenWork
$result = @(& pwsh -NoProfile -NonInteractive -File $applier -ApplyOffline 2>&1)
$exit = $LASTEXITCODE
$installed = @($result | Where-Object { [string]$_ -ceq
    'OWNER_R2_APPLY=INSTALLED_HASH_VERIFIED_OWNER_STOPPED' }).Count -eq 1
$tokens = @($result | Where-Object { [string]$_ -match '^OWNER_R2_BACKUP_ID=owner-r2-[a-f0-9]{32}$' })
if ($exit -ne 0 -or -not $installed -or $tokens.Count -ne 1) {
    # A failed apply may leave an uncertain partial installation. Never restart
    # Owner on an unknown state; preserve private recovery for manual repair.
    Hold 'OFFLINE_APPLY_FAILED_OWNER_DISABLED'
}
$backupId = ([string]$tokens[0]).Split('=')[1]
if (StartOwnerAfterMaintenance $oldPid) {
    Write-Output 'OWNER_R2_MAINTENANCE=R2_ACTIVE_FRESH_OWNER_HEARTBEAT'
    Write-Output 'OWNER_R2_PROVIDER_TV=NOT_RUN_BY_MAINTENANCE'
    Write-Output 'OWNER_R2_REDMi=NOT_VERIFIED'
    return
}

# New Owner did not become freshly healthy. Only revert if it can be stopped,
# and the exact R2 module hashes and original private backups still match.
StopOwnerForMaintenance
$rolled = @(& pwsh -NoProfile -NonInteractive -File $applier -RollbackOffline -BackupId $backupId 2>&1)
$rollbackExit = $LASTEXITCODE
if ($rollbackExit -ne 0 -or
    @($rolled | Where-Object { [string]$_ -ceq
        'OWNER_R2_ROLLBACK=ORIGINAL_BYTES_RESTORED_OWNER_STOPPED' }).Count -ne 1) {
    Hold 'NEW_OWNER_UNHEALTHY_ROLLBACK_NOT_VERIFIED_TASK_DISABLED'
}
if (-not (StartOwnerAfterMaintenance $oldPid)) {
    Hold 'OLD_OWNER_ROLLBACK_VERIFIED_BUT_HEARTBEAT_FAILED'
}
Hold 'R2_STARTUP_FAILED_OLD_OWNER_RECOVERED'
