# Owner-approved, single Ready -> Running recovery only. No cache, provider or P2 replay.
# The previous EN406 marker attempt stopped at MARKER_NOT_UNIQUE before mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$ownerRoot = Join-Path $root 'OwnerBridge'
$installed = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$healthPath = Join-Path $ownerRoot 'agent-health.json'
$p2Root = Join-Path $root 'P2\auto-lean120-state'
$inbox = Join-Path $ownerRoot 'inbox'
$desired = @{
    'automatic_vietsub_flow.py' = '7f0b644d2aad74e87d5559e0b1bbe95adb302072dcbeb7fefef640a0a083308d'
    'opensubtitles.py' = '3711dab1d40de9751d17cb3b5d9fbe485c644e6e2488b05e7d248cf5bb93a3f0'
    'owner_session_bridge.py' = 'e7924b6aaa1597e61eb23f9822dec348023f25ed252a1c6ad74366502d1c2406'
}
function Hold([string]$code) { throw ('OWNER_EN406_RESUME_HOLD_' + $code) }
function GetOwnerTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -cnotmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function AssertIdle {
    if (-not (Test-Path -LiteralPath $p2Root -PathType Container) -or
        -not (Test-Path -LiteralPath $inbox -PathType Container)) { Hold 'P2_ROOT_MISSING' }
    if (@(Get-ChildItem -LiteralPath $inbox -Force -File -Filter 'event-*.json').Count -ne 0) {
        Hold 'OWNER_PENDING_EVENT'
    }
    $locks = @(Get-ChildItem -LiteralPath $p2Root -File -Force -Recurse |
        Where-Object { $_.Name -ceq 'active.lock' -or
                       $_.Name -cmatch '^batch-[0-9]{4}\.inflight$' })
    if ($locks.Count -ne 0) { Hold 'P2_ACTIVE_OR_UNKNOWN' }
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($root,$ownerRoot,$installed,$p2Root,$inbox)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container) -or
        ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'ROOT_INVALID'
    }
}
if ([string](GetOwnerTask).State -cne 'Ready') { Hold 'OWNER_TASK_NOT_READY' }
AssertIdle
if (@(OwnerWorkers).Count -ne 0) { Hold 'OWNER_WORKERS_PRESENT' }
foreach ($file in $desired.Keys) {
    $path = Join-Path $installed $file
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $desired[$file]) {
        Hold 'INSTALLED_MODULE_HASH_DRIFT'
    }
}
$oldPid = 0L
if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json).pid }
    catch { Hold 'PREVIOUS_HEALTH_INVALID' }
}
AssertIdle
if ([string](GetOwnerTask).State -cne 'Ready' -or @(OwnerWorkers).Count -ne 0) {
    Hold 'PRESUME_CONCURRENCY_DRIFT'
}
Write-Output 'OWNER_EN406_RESUME=PREFLIGHT_READY_IDLE_HASH_VERIFIED'
$since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
for ($i=0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    if ([string](GetOwnerTask).State -cne 'Running') { continue }
    try {
        $h = Get-Content -LiteralPath $healthPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($h.state -cne 'READY' -or [long]$h.pid -le 0 -or
            [long]$h.pid -eq $oldPid -or [long]$h.observed_utc_epoch -lt $since - 2) { continue }
        $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [long]$h.pid)
        if ($null -eq $worker -or [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
            continue
        }
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($who.ReturnValue -eq 0 -and $who.Sid -ceq $identity.User.Value) {
            Write-Output 'OWNER_EN406_RESUME=FRESH_OWNER_RUNNING'
            Write-Output 'OWNER_EN406_RESUME_PROVIDER_REQUESTS=ZERO'
            Write-Output 'OWNER_EN406_RESUME_CACHE=UNMODIFIED'
            return
        }
    } catch { continue }
}
Hold 'FRESH_OWNER_HEALTH_NOT_VERIFIED'
