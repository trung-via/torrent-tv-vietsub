# One Owner-approved, exact-one-marker recovery after the observed EN 406.
# No provider request, no subtitle/cache deletion, no replay of blocked events.
# An ambiguous marker or active P2 job is a hard HOLD before any mutation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$base = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$ownerRoot = Join-Path $base 'OwnerBridge'
$cache = Join-Path $base 'subtitle-trials'
$stateRoot = Join-Path $base 'P2\auto-lean120-state'
$inbox = Join-Path $ownerRoot 'inbox'
$health = Join-Path $ownerRoot 'agent-health.json'
$diagLog = Join-Path $ownerRoot 'diagnostics\owner-full.log'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$ownerSid = $identity.User.Value

function Hold([string]$code) { throw ('OWNER_EN406_QUARANTINE_HOLD_' + $code) }
function Hash([string]$file) {
    (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function CheckFolder([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { Hold 'ROOT_MISSING' }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Hold 'ROOT_REPARSE_POINT'
    }
}
function CheckFile([string]$path, [long]$max) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Hold 'FILE_MISSING' }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Length -le 0 -or $item.Length -gt $max -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Hold 'FILE_UNTRUSTED' }
}
function OwnerTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $taskSid = [string]$task.Principal.UserId
    if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($taskSid -cne $ownerSid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
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
function IdleP2 {
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.json')
    if ($pending.Count -ne 0) { Hold 'PENDING_OWNER_EVENT' }
    $active = @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Force |
        Where-Object { $_.Name -match '^batch-[0-9]{4}\.inflight$' -or
                       $_.Name -ceq 'active.lock' })
    if ($active.Count -ne 0) { Hold 'P2_UNKNOWN_OR_ACTIVE_EFFECT' }
}
function StopOwnerWorkers {
    for ($i=0; $i -lt 8; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $remaining = @(OwnerWorkers)
    if ($remaining.Count -gt 4) { Hold 'UNEXPECTED_WORKER_COUNT' }
    $app = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $app 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'owner_session_bridge.py'))
    foreach ($worker in $remaining) {
        $matchesPath = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid -ErrorAction Stop
        if ($matchesPath.Count -ne 1 -or $who.ReturnValue -ne 0 -or
            $who.Sid -cne $ownerSid -or $null -eq $worker.CreationDate) {
            Hold 'OWNER_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $remaining) {
        IdleP2
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(OwnerWorkers).Count -ne 0) { Hold 'WORKERS_STILL_RUNNING' }
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 1
        if ([string](OwnerTask).State -cne 'Running') { continue }
        try {
            $h = Get-Content -LiteralPath $health -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($h.state -cne 'READY' -or [long]$h.pid -eq $oldPid -or
                [long]$h.observed_utc_epoch -lt $since - 2) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [long]$h.pid)
            if ($null -eq $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                continue
            }
            $who = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($who.ReturnValue -eq 0 -and $who.Sid -ceq $ownerSid) { return }
        } catch { continue }
    }
    Hold 'RESTART_NEW_OWNER_NOT_VERIFIED'
}

$loggedUser = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($loggedUser) -or
    -not $identity.Name.Equals($loggedUser,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
foreach ($dir in @($base,$ownerRoot,$cache,$stateRoot,$inbox)) { CheckFolder $dir }
if ([string](OwnerTask).State -cne 'Running') { Hold 'OWNER_TASK_NOT_RUNNING' }
IdleP2

# Error EN_DOWNLOAD_ALREADY_ATTEMPTED can only refer to the exact claim it
# wanted to create. If there is more than one active claim, do not guess one.
$markers = @(Get-ChildItem -LiteralPath $cache -File -Force -Filter '.en-once-*' |
    Where-Object { $_.Name -cmatch '^\.en-once-[0-9a-f]{64}$' })
if ($markers.Count -ne 1) { Hold 'MARKER_NOT_UNIQUE' }
$marker = $markers[0]
CheckFile $marker.FullName 64
if ([IO.File]::ReadAllText($marker.FullName,[Text.Encoding]::ASCII) -cne "ONE_POST_CLAIMED`n") {
    Hold 'MARKER_CONTENT_CHANGED'
}
$markerSha = Hash $marker.FullName
$blocked = @(Get-ChildItem -LiteralPath $inbox -File -Force -Filter 'event-*.blocked' |
    Sort-Object LastWriteTimeUtc -Descending)
if ($blocked.Count -eq 0) { Hold 'BLOCKED_EVENT_NOT_FOUND' }
$eventFile = $blocked[0]
CheckFile $eventFile.FullName 768
$eventSha = Hash $eventFile.FullName
$now = [DateTime]::UtcNow
$ageSeconds = ($now - $eventFile.LastWriteTimeUtc).TotalSeconds
if ($ageSeconds -lt 0 -or $ageSeconds -gt 3600) { Hold 'BLOCKED_EVENT_NOT_RECENT' }
if ($blocked.Count -gt 1 -and
    ($eventFile.LastWriteTimeUtc - $blocked[1].LastWriteTimeUtc).TotalSeconds -lt 90) {
    Hold 'MULTIPLE_RECENT_BLOCKED_EVENTS'
}
$eventId = $eventFile.Name -replace '^event-','' -replace '\.blocked$',''
$event = Get-Content -LiteralPath $eventFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
if ($event.schema -cne 'TTV-OWNER-VIDEO-EVENT-V4' -or
    $event.event_id -cne $eventId -or $eventId -cnotmatch '^[a-f0-9]{32}$' -or
    $event.source_fingerprint -cnotmatch '^[a-f0-9]{64}$' -or
    [string]::IsNullOrWhiteSpace([string]$event.tv_session_id)) {
    Hold 'LATEST_BLOCKED_EVENT_NOT_BOUND'
}
$claim = Join-Path $inbox ('claim-' + $eventId)
CheckFile $claim 128
if ([IO.File]::ReadAllText($claim,[Text.Encoding]::ASCII) -cne "CLAIMED_DO_NOT_AUTO_REPLAY`n") {
    Hold 'OWNER_EVENT_CLAIM_INVALID'
}
if ($marker.LastWriteTimeUtc -gt $eventFile.LastWriteTimeUtc) { Hold 'MARKER_NEWER_THAN_EVENT' }
$aiIndex = Join-Path $cache ('.dual-source-' + $event.source_fingerprint + '-ai_en.json')
if (Test-Path -LiteralPath $aiIndex) { Hold 'CURRENT_AI_EN_ALREADY_CACHED' }
$legacy = Join-Path $cache ('.auto-source-' + $event.source_fingerprint + '.json')
if (Test-Path -LiteralPath $legacy) {
    CheckFile $legacy 512
    $legacyEntry = Get-Content -LiteralPath $legacy -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($legacyEntry.language -cne 'vi') { Hold 'CURRENT_LEGACY_EN_ALREADY_CACHED' }
}
CheckFile $diagLog 268435456
$trace = Get-Content -LiteralPath $diagLog -Tail 1000 -Encoding UTF8 | Out-String
if (-not $trace.Contains($eventId) -or
    -not $trace.Contains('OWNER_BRIDGE_BLOCK_REASON=EN_DOWNLOAD_ALREADY_ATTEMPTED')) {
    Hold 'CURRENT_FAILURE_TRACE_NOT_PROVEN'
}
Write-Output 'OWNER_EN406_PREFLIGHT=ONE_ACTIVE_MARKER_ONE_RECENT_BLOCKED_EN_FAILURE'

$oldPid = 0L
if (Test-Path -LiteralPath $health -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
    catch { Hold 'HEALTH_NOT_READABLE' }
}
$taskDisabled = $false
$moved = $false
try {
    # Fence new Owner claims first. A failed transaction leaves the task off.
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $taskDisabled = $true
    Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    StopOwnerWorkers
    IdleP2
    CheckFile $marker.FullName 64
    if ((Hash $marker.FullName) -cne $markerSha -or
        (Hash $eventFile.FullName) -cne $eventSha) {
        Hold 'PREMOVE_CLAIM_DRIFT'
    }
    $quarantine = Join-Path $cache ($marker.Name + '.quarantined-' + [Guid]::NewGuid().ToString('N'))
    Move-Item -LiteralPath $marker.FullName -Destination $quarantine -ErrorAction Stop
    $moved = $true
    if ((Hash $quarantine) -cne $markerSha) { Hold 'ARCHIVED_BYTES_MISMATCH' }
    Write-Output 'OWNER_EN406_MARKER=QUARANTINED_ORIGINAL_BYTES_PRESERVED'
    StartOwner $oldPid
    Write-Output 'OWNER_EN406=QUARANTINED_FRESH_OWNER_RUNNING'
    Write-Output 'OWNER_EN406_PROVIDER_REQUESTS=ZERO'
    Write-Output 'OWNER_EN406_OTHER_CACHE=UNCHANGED'
} catch {
    if ($taskDisabled) {
        Write-Output ('OWNER_EN406_HOLD=TASK_DISABLED_MARKER_' + $(if ($moved) {'ARCHIVED'} else {'ORIGINAL'}))
    }
    throw
}
