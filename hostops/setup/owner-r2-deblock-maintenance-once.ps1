# One-click, Owner-interactive R2 hotfix maintenance. Inspect unless -Apply.
# Never runs in HostOps/CI. Stops only the installed Owner workers, installs
# three hash-pinned files, then verifies a fresh Owner heartbeat. No P2 replay.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')][string]$HotfixCommit,
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stageCommit = '1687fb327803c916af047c5fa13183ff9e79f92c'
$applierHash = 'ad50b7f7f5f6d4646136323639fb3ec3a8d026793aece8b88aeab782b37031d2'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$healthPath = Join-Path $ownerRoot 'agent-health.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Hold([string]$reason) {
    Write-Output ('OWNER_DEBLOCK_MAINTENANCE=HOLD_' + $reason)
    throw 'OWNER_DEBLOCK_MAINTENANCE_HOLD'
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    $inbox = Join-Path $ownerRoot 'inbox'
    if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Hold 'OWNER_INBOX_MISSING' }
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    if (Test-Path -LiteralPath $stateRoot) {
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight').Count -gt 0 -or
            @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'active.lock').Count -gt 0) {
            Hold 'P2_UNCERTAIN_OR_ACTIVE'
        }
    }
}
function RequireTask {
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
function StopOwner {
    $task = RequireTask
    if ([string]$task.State -ceq 'Running') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    } elseif ([string]$task.State -ceq 'Ready') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    } elseif ([string]$task.State -cne 'Disabled') {
        Hold 'OWNER_TASK_UNEXPECTED_STATE'
    }
    for ($i=0; $i -lt 5; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'OWNER_WORKER_COUNT_UNEXPECTED' }
    $installed = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matched = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matched.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenWork
        if ([string](RequireTask).State -cne 'Disabled') { Hold 'TASK_REENABLED_DURING_STOP' }
        $live = Get-CimInstance Win32_Process -Filter ("ProcessId=" + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $identity = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKERS_STILL_RUNNING'
}
function StartAndVerify([long]$previousPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if ([string](RequireTask).State -cne 'Running' -or
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
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($identity.ReturnValue -eq 0 -and $identity.Sid -cne $ownerSid) { continue }
        if ($identity.ReturnValue -eq 0) { return $true }
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
$task = RequireTask
NoOpenWork
$temp = Join-Path $env:TEMP ('ttv-owner-deblock-applier-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $HotfixCommit + '/hostops/setup/owner-r2-deblock-offline-apply.ps1') -OutFile $temp -ErrorAction Stop
    if ((Hash $temp) -cne $applierHash) { Hold 'PINNED_APPLIER_HASH_MISMATCH' }
    $inspect = @(& pwsh -NoProfile -File $temp -SourceCommit $stageCommit 2>&1)
    if ($LASTEXITCODE -ne 0) { Hold 'STAGED_RELEASE_INSPECT_FAILED' }
    if (@($inspect | Where-Object { [string]$_ -ceq 'OWNER_DEBLOCK_OFFLINE=ALREADY_INSTALLED' }).Count -eq 1) {
        Write-Output 'OWNER_DEBLOCK_MAINTENANCE=ALREADY_INSTALLED'
        return
    }
    if (@($inspect | Where-Object { [string]$_ -ceq 'OWNER_DEBLOCK_OFFLINE=INSPECT_PASS_OLD_OWNER_UNCHANGED' }).Count -ne 1) {
        Hold 'UNEXPECTED_RELEASE_STATE'
    }
    Write-Output 'OWNER_DEBLOCK_MAINTENANCE_PREFLIGHT=3_STAGED_FILES_VERIFIED'
    if (-not $Apply) { Write-Output 'OWNER_DEBLOCK_MAINTENANCE=INSPECT_ONLY'; return }

    $oldPid = 0L
    if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
        try {
            $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
            if ($health.pid -is [ValueType]) { $oldPid = [long]$health.pid }
        } catch { $oldPid = 0L }
    }
    StopOwner
    NoOpenWork
    $applied = @(& pwsh -NoProfile -File $temp -SourceCommit $stageCommit -ApplyOffline 2>&1)
    if ($LASTEXITCODE -ne 0 -or
        @($applied | Where-Object { [string]$_ -ceq 'OWNER_DEBLOCK_OFFLINE=APPLIED_HASH_VERIFIED_OWNER_STOPPED' }).Count -ne 1) {
        Hold 'OFFLINE_APPLY_FAILED_OWNER_DISABLED'
    }
    $token = @($applied | Where-Object { [string]$_ -match '^OWNER_DEBLOCK_BACKUP_ID=owner-deblock-[a-f0-9]{32}$' })
    if ($token.Count -ne 1) { Hold 'BACKUP_RECEIPT_MISSING_OWNER_DISABLED' }
    $backupId = ([string]$token[0]).Split('=')[1]
    if (StartAndVerify $oldPid) {
        Write-Output 'OWNER_DEBLOCK_MAINTENANCE=NEW_OWNER_ACTIVE_FRESH_HEARTBEAT'
        Write-Output 'OWNER_DEBLOCK_PROVIDER_TV=NOT_RUN'
        return
    }
    StopOwner
    NoOpenWork
    $rolled = @(& pwsh -NoProfile -File $temp -SourceCommit $stageCommit `
        -RollbackOffline -BackupId $backupId 2>&1)
    if ($LASTEXITCODE -ne 0 -or
        @($rolled | Where-Object { [string]$_ -ceq 'OWNER_DEBLOCK_ROLLBACK=ORIGINAL_BYTES_RESTORED_OWNER_STOPPED' }).Count -ne 1) {
        Hold 'NEW_OWNER_UNHEALTHY_ROLLBACK_NOT_VERIFIED_DISABLED'
    }
    if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RECOVERY_HEARTBEAT_FAILED' }
    Hold 'NEW_OWNER_UNHEALTHY_OLD_OWNER_RECOVERED'
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
