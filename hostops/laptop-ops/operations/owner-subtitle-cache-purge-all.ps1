# Human explicitly requested removal of ALL old downloaded/AI-translated subtitle
# cache across films. Move exactly two active data roots into private recoverable
# quarantine; preserve Owner application, pairing, keys and event audit trail.
# No provider request, P2 job replay, TV action or APK change.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$owner = Join-Path $base 'OwnerBridge'
$cache = Join-Path $base 'subtitle-trials'
$p2 = Join-Path $base 'P2\auto-lean120-state'
$inbox = Join-Path $owner 'inbox'
$healthFile = Join-Path $owner 'agent-health.json'
$archives = Join-Path $base 'CacheArchives'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Hold([string]$code) { throw ('OWNER_CACHE_PURGE_HOLD_' + $code) }
function AssertDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { Hold 'ROOT_MISSING' }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint) { Hold 'ROOT_REPARSE' }
}
function OwnerTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -cnotmatch '^S-\d+(?:-\d+){2,}$') {
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
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertIdle {
    if (@(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json').Count -ne 0) {
        Hold 'PENDING_OWNER_EVENT'
    }
    $locks = @(Get-ChildItem -LiteralPath $p2 -File -Force -Recurse |
        Where-Object { $_.Name -ceq 'active.lock' -or
                       $_.Name -cmatch '^batch-[0-9]{4}\.inflight$' })
    if ($locks.Count -ne 0) { Hold 'P2_ACTIVE_OR_UNKNOWN_EFFECT' }
}
function StopVerifiedWorkers {
    for ($i=0; $i -lt 8; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'UNEXPECTED_WORKERS' }
    $app = Join-Path $owner 'app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matches = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid -ErrorAction Stop
        if ($matches.Count -ne 1 -or $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Hold 'WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        AssertIdle
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(OwnerWorkers).Count -ne 0) { Hold 'WORKERS_STILL_RUNNING' }
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        if ([string](OwnerTask).State -cne 'Running') { continue }
        try {
            $h = Get-Content -LiteralPath $healthFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($h.state -cne 'READY' -or [long]$h.pid -le 0 -or
                [long]$h.pid -eq $oldPid -or [long]$h.observed_utc_epoch -lt $since - 2) {
                continue
            }
            $worker = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [long]$h.pid)
            if ($null -eq $worker -or [string]$worker.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                continue
            }
            $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
            if ($who.ReturnValue -eq 0 -and $who.Sid -ceq $sid) { return }
        } catch { continue }
    }
    Hold 'FRESH_OWNER_NOT_VERIFIED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
foreach ($dir in @($base,$owner,$cache,$p2,$inbox)) { AssertDir $dir }
$state = [string](OwnerTask).State
if ($state -cnotin @('Running','Ready')) { Hold 'OWNER_TASK_NOT_RUNNABLE' }
AssertIdle
if (Test-Path -LiteralPath $archives) { AssertDir $archives }
else { [IO.Directory]::CreateDirectory($archives) | Out-Null }
$oldPid = 0L
if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $healthFile -Raw -Encoding UTF8 | ConvertFrom-Json).pid }
    catch { Hold 'PREVIOUS_HEALTH_INVALID' }
}
$cacheFiles = @(Get-ChildItem -LiteralPath $cache -File -Recurse -Force).Count
$p2Files = @(Get-ChildItem -LiteralPath $p2 -File -Recurse -Force).Count
$archive = Join-Path $archives ('purge-all-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $archive) { Hold 'ARCHIVE_ALREADY_EXISTS' }
Write-Output 'OWNER_CACHE_PURGE=PREFLIGHT_IDLE_TWO_ROOTS'
$disabled = $false
$movedCache = $false
$movedP2 = $false
try {
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $disabled = $true
    if ($state -ceq 'Running') {
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    }
    StopVerifiedWorkers
    AssertIdle
    [IO.Directory]::CreateDirectory($archive) | Out-Null
    Move-Item -LiteralPath $cache -Destination (Join-Path $archive 'subtitle-trials') -ErrorAction Stop
    $movedCache = $true
    Move-Item -LiteralPath $p2 -Destination (Join-Path $archive 'auto-lean120-state') -ErrorAction Stop
    $movedP2 = $true
    [IO.Directory]::CreateDirectory($cache) | Out-Null
    [IO.Directory]::CreateDirectory($p2) | Out-Null
    if (@(Get-ChildItem -LiteralPath $cache -Force).Count -ne 0 -or
        @(Get-ChildItem -LiteralPath $p2 -Force).Count -ne 0 -or
        @(Get-ChildItem -LiteralPath (Join-Path $archive 'subtitle-trials') -File -Recurse -Force).Count -ne $cacheFiles -or
        @(Get-ChildItem -LiteralPath (Join-Path $archive 'auto-lean120-state') -File -Recurse -Force).Count -ne $p2Files) {
        Hold 'ARCHIVE_VERIFY_FAILED'
    }
    Write-Output 'OWNER_CACHE_PURGE=ACTIVE_SUBTITLE_AND_TRANSLATION_CACHE_EMPTY'
    StartOwner $oldPid
    Write-Output 'OWNER_CACHE_PURGE=COMPLETE_FRESH_OWNER_RUNNING'
    Write-Output ('OWNER_CACHE_PURGE_SUBTITLE_FILES=' + $cacheFiles)
    Write-Output ('OWNER_CACHE_PURGE_P2_FILES=' + $p2Files)
    Write-Output 'OWNER_CACHE_PURGE_SOURCE_CODE_PAIRING_KEYS=UNCHANGED'
    Write-Output 'OWNER_CACHE_PURGE_PROVIDER_CALLS=ZERO'
    Write-Output 'OWNER_CACHE_PURGE_OLD_FILES=QUARANTINED_OUTSIDE_ACTIVE_CACHE'
} catch {
    if ($disabled) {
        Write-Output ('OWNER_CACHE_PURGE_HOLD=OWNER_TASK_DISABLED_CACHE_' +
                      $(if ($movedCache) { 'MOVED' } else { 'ORIGINAL' }) +
                      '_P2_' + $(if ($movedP2) { 'MOVED' } else { 'ORIGINAL' }))
    }
    throw
}
