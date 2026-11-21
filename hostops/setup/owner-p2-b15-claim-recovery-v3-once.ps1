# One-shot Owner-interactive batch-0015 claim recovery V3. After V2's claim HOLD, a durable
# sanitized receipt is emitted BEFORE any private P2 preflight, so a failed
# preflight is observable by HostOps without another timeout/retry.
# No provider/TV call. An uncertain old paid job remains recoverable in a
# private archive, and a new translation requires a NEW explicit TV request.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$batch = 'batch-0015'
$markerSHA = '4158f5ac6b0922e2eb58b5c1ecf5e5d40c85a6e69bb484e579c242c517478ab5'
$homeRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$ownerRoot = Join-Path $homeRoot 'OwnerBridge'
$appRoot = Join-Path $ownerRoot 'app'
$inbox = Join-Path $ownerRoot 'inbox'
$stateRoot = Join-Path $homeRoot 'P2\auto-lean120-state'
$receiptRoot = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts'
$receipt = Join-Path $receiptRoot 'p2-batch15-claim-recovery-v3.json'
$oldReceipt = Join-Path $receiptRoot 'p2-batch15-fresh-start.json'
$v2Receipt = Join-Path $receiptRoot 'p2-batch15-fresh-start-v2.json'
$snapshot = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
$health = Join-Path $ownerRoot 'agent-health.json'
$stage = 'IDENTITY'
$mutationStarted = $false

function Hold([string]$code) { throw ('OWNER_P2_B15_V3_' + $code) }
function CheckDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_INVALID'
    }
}
function CheckFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_INVALID'
    }
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Receipt([string]$result) {
    $doc = [ordered]@{ schema='TTV-OWNER-P2-B15-CLAIM-RECOVERY-V3'; batch=$batch;
        marker_sha256=$markerSHA; result=$result;
        observed_utc_epoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
    $temp = $receipt + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($doc | ConvertTo-Json -Compress),
        [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp,$receipt,$true)
    Write-Output ('OWNER_P2_B15_V3=' + $result)
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function CheckWorkers($list) {
    if (@($list).Count -gt 4) { Hold 'TOO_MANY_WORKERS' }
    $allowed = @((Join-Path $appRoot 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
        (Join-Path $appRoot 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($p in $list) {
        if ($null -eq $p.CreationDate -or
            @($allowed | Where-Object { [string]$p.CommandLine -and
                $p.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -ne 1) {
            Hold 'WORKER_COMMAND_DRIFT'
        }
        $who = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
        if ($who.ReturnValue -ne 0 -or $who.Sid -cne $identity.User.Value) {
            Hold 'WORKER_OWNER_DRIFT'
        }
    }
}
function StopOwner {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    if ([string]$task.State -notin @('Running','Ready','Disabled')) { Hold 'TASK_STATE_DRIFT' }
    if ([string]$task.State -cne 'Disabled') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -ceq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $stuck = @(Workers)
    CheckWorkers $stuck
    foreach ($p in $stuck) {
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$p.ProcessId)
        if ($null -eq $live) { continue }
        if ([string]$live.CommandLine -cne [string]$p.CommandLine -or
            $live.CreationDate -ne $p.CreationDate) { Hold 'WORKER_CHANGED' }
        CheckWorkers @($live)
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'WORKER_NOT_STOPPED'
}
function StateJob {
    CheckDir $stateRoot
    $jobs = @(Get-ChildItem -LiteralPath $stateRoot -Force -ErrorAction Stop)
    if ($jobs.Count -gt 64) { Hold 'JOB_COUNT_INVALID' }
    $markers = @()
    foreach ($job in $jobs) {
        if (-not $job.PSIsContainer -or $job.Name -cnotmatch '^[0-9a-f]{64}$') {
            Hold 'STATE_ENTRY_UNEXPECTED'
        }
        CheckDir $job.FullName
        $children = @(Get-ChildItem -LiteralPath $job.FullName -Force)
        if ($children.Count -gt 256) { Hold 'JOB_FILES_UNBOUNDED' }
        foreach ($child in $children) {
            if ($child.PSIsContainer -or
                ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                $child.Length -gt 4194304) { Hold 'JOB_CHILD_INVALID' }
            if ($child.Name -clike 'batch-*.inflight') { $markers += $child }
        }
    }
    if ($markers.Count -ne 1 -or $markers[0].Name -cne ($batch + '.inflight')) {
        Hold 'MARKER_COUNT_OR_BATCH_DRIFT'
    }
    $marker = $markers[0].FullName
    CheckFile $marker
    if ((Get-Item -LiteralPath $marker).Length -gt 4096 -or (Hash $marker) -cne $markerSHA) {
        Hold 'MARKER_HASH_DRIFT'
    }
    $jobFolder = Split-Path -Parent $marker
    $doc = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($doc.Keys).Count -ne 3 -or $doc.schema -cne 'TTV-P2-INFLIGHT-V1' -or
        $doc.job -cne (Split-Path -Leaf $jobFolder) -or $doc.version -isnot [ValueType] -or
        [long]$doc.version -ne 15) { Hold 'MARKER_SCHEMA_DRIFT' }
    if (Test-Path -LiteralPath (Join-Path $jobFolder ($batch + '.json'))) {
        Hold 'CHECKPOINT15_EXISTS'
    }
    $lock = Join-Path $jobFolder 'active.lock'
    CheckFile $lock
    if ([IO.File]::ReadAllText($lock) -cne "TTV-P2-LOCK-V1`n") { Hold 'LOCK_DRIFT' }
    return $jobFolder
}
function PendingEvent {
    CheckDir $inbox
    $events = @(Get-ChildItem -LiteralPath $inbox -Filter 'event-*.json' -File -Force)
    if ($events.Count -ne 1) { Hold 'PENDING_COUNT_DRIFT' }
    $event = $events[0]
    CheckFile $event.FullName
    $match = [regex]::Match($event.Name,'^event-([0-9a-f]{32})\.json$')
    if (-not $match.Success -or $event.Length -gt 768) { Hold 'PENDING_FILE_INVALID' }
    $id = $match.Groups[1].Value
    $doc = Get-Content -LiteralPath $event.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($doc.Keys).Count -ne 5 -or $doc.schema -cne 'TTV-OWNER-VIDEO-EVENT-V3' -or
        $doc.event_id -cne $id -or $doc.source_fingerprint -cnotmatch '^[0-9a-f]{64}$' -or
        $doc.tv_session_id -cnotmatch '^[A-Za-z0-9_-]{1,128}$' -or
        $doc.selected_video_filename -isnot [string] -or
        [string]::IsNullOrWhiteSpace($doc.selected_video_filename) -or
        $doc.selected_video_filename.Length -gt 255 -or
        $doc.selected_video_filename -match '[/\\]') { Hold 'PENDING_SCHEMA_DRIFT' }
    $claim = Join-Path $inbox ('claim-' + $id)
    CheckFile $claim
    if ((Get-Item -LiteralPath $claim).Length -ne 27 -or
        [IO.File]::ReadAllText($claim) -cne "CLAIMED_DO_NOT_AUTO_REPLAY`n") {
        Hold 'CLAIM_CONTENT_DRIFT'
    }
    # A claim is an uncertain provider-effect marker, not evidence of a
    # completed or free API request. Archive its exact bytes WITH the old
    # request. Never remove the claim while the event remains replayable.
    return [pscustomobject]@{
        EventPath = $event.FullName
        EventSha256 = (Hash $event.FullName)
        ClaimPath = $claim
        ClaimSha256 = (Hash $claim)
    }
}
function FreshOwner([long]$oldPID) {
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 45; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Running') { continue }
        if (-not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        CheckFile $health
        if ((Get-Item -LiteralPath $health).Length -gt 512) { continue }
        try { $h = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json -AsHashtable }
        catch { continue }
        if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or $h.state -cne 'READY' -or
            $h.pid -isnot [ValueType] -or [long]$h.pid -eq $oldPID -or
            [long]$h.pid -le 0 -or $h.observed_utc_epoch -isnot [ValueType]) { continue }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { continue }
        $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid) -ErrorAction SilentlyContinue
        if ($null -eq $p -or [string]$p.CommandLine -notmatch
            'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') { continue }
        CheckWorkers @($p)
        return $true
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($PSVersionTable.PSVersion.Major -ne 7 -or $env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
CheckDir $receiptRoot
if (Test-Path -LiteralPath $receipt) { Hold 'ALREADY_ATTEMPTED_NO_REPLAY' }
if (Test-Path -LiteralPath $oldReceipt) { Hold 'V1_RECEIPT_PRESENT_MANUAL_REVIEW' }

# All ordinary private preflights now occur AFTER this durable receipt.
Receipt 'PREFLIGHT_STARTED'
try {
    $stage = 'V2_RECEIPT'
    CheckFile $v2Receipt
    if ((Get-Item -LiteralPath $v2Receipt).Length -gt 1024) {
        Hold 'V2_RECEIPT_SIZE_DRIFT'
    }
    $prior = Get-Content -LiteralPath $v2Receipt -Raw -Encoding UTF8 |
        ConvertFrom-Json -AsHashtable
    if (@($prior.Keys).Count -ne 5 -or
        $prior.schema -cne 'TTV-OWNER-P2-B15-FRESH-START-V2' -or
        $prior.batch -cne $batch -or
        $prior.marker_sha256 -cne $markerSHA -or
        $prior.result -cne 'PREFLIGHT_HOLD_PRIVATE_EVENT_PENDING_CLAIMED' -or
        $prior.observed_utc_epoch -isnot [ValueType] -or
        [long]$prior.observed_utc_epoch -le 0 -or
        [long]$prior.observed_utc_epoch -gt [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
        Hold 'V2_RECEIPT_NOT_EXPECTED_HOLD'
    }
    $stage = 'OWNER_TASK'
    foreach ($dir in @($homeRoot,$ownerRoot,$appRoot,$stateRoot,$inbox)) { CheckDir $dir }
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne $identity.User.Value -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        -not [IO.Path]::GetFileName([string]$task.Actions[0].Execute).Equals(
            'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'ORIGINAL_TASK_DRIFT'
    }
    $originalState = [string]$task.State
    if ($originalState -notin @('Running','Ready','Disabled')) {
        Hold 'ORIGINAL_TASK_UNSUPPORTED_STATE'
    }
    $stage = 'SNAPSHOT'
    CheckFile $snapshot
    if ((Get-Item -LiteralPath $snapshot).Length -gt 4096) { Hold 'SNAPSHOT_SIZE_INVALID' }
    $s = Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$s.snapshot_utc_epoch
    if ($s.schema -notin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V2',
            'TTV-HOSTOPS-OWNER-SNAPSHOT-V3') -or
        $s.status -cne 'READY_FRESH' -or $s.p3_state -cne 'FRESH_OFF' -or
        $age -lt 0 -or
        $s.p2.status -cne 'UNKNOWN_EFFECT_HOLD' -or
        $s.p2.pending_events -ne 1 -or $s.p2.inflight_count -ne 1 -or
        $s.p2.batch -cne $batch -or $s.p2.marker_sha256 -cne $markerSHA -or
        $s.p2.checkpoint_present -cne 'NO' -or
        $s.p2.active_lock_present -cne 'YES' -or
        $s.p2.installed_no_retry_worker_match -cne 'YES') { Hold 'OBSERVED_P2_DRIFT' }
    # A deliberately stopped Owner cannot refresh this snapshot. For Ready or
    # Disabled, the old FRESH_OFF observation is historical evidence only;
    # private marker/event identity and ZERO live workers are rechecked below.
    # A running Owner still requires a recent, current-TV-OFF observation.
    if ($originalState -ceq 'Running' -and $age -gt 30) {
        Hold 'RUNNING_OWNER_SNAPSHOT_STALE'
    }
    $stage = 'PRIVATE_JOB'
    $oldJob = StateJob
    $stage = 'PRIVATE_EVENT'
    $oldEvent = PendingEvent
    $stage = 'WORKERS'
    $observedWorkers = @(Workers)
    CheckWorkers $observedWorkers
    if ($originalState -cne 'Running' -and $observedWorkers.Count -ne 0) {
        Hold 'STOPPED_OWNER_WITH_LIVE_WORKER'
    }
    $oldPID = 0L
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        try { $h = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json -AsHashtable
            if ($h.pid -is [ValueType]) { $oldPID = [long]$h.pid } }
        catch { $oldPID = 0L }
    }
    Receipt 'PREFLIGHT_PASS_NO_MUTATION'
    $stage = 'STOP'
    $mutationStarted = $true
    StopOwner
    if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Disabled' -or
        @(Workers).Count -ne 0) { Hold 'OWNER_NOT_STOPPED' }
    $stage = 'REVALIDATE'
    $nowEvent = PendingEvent
    if ((StateJob) -cne $oldJob -or
        $nowEvent.EventPath -cne $oldEvent.EventPath -or
        $nowEvent.EventSha256 -cne $oldEvent.EventSha256 -or
        $nowEvent.ClaimPath -cne $oldEvent.ClaimPath -or
        $nowEvent.ClaimSha256 -cne $oldEvent.ClaimSha256) {
        Hold 'PRIVATE_STATE_CHANGED'
    }
    $stage = 'ARCHIVE'
    $jobRecovery = Join-Path $homeRoot 'P2\recovery'
    $eventRecovery = Join-Path $ownerRoot 'recovery'
    foreach ($dir in @($jobRecovery,$eventRecovery)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
        }
        CheckDir $dir
    }
    $transaction = [Guid]::NewGuid().ToString('N')
    $eventDestination = Join-Path $eventRecovery ('p2-b15-v3-' + $transaction)
    New-Item -ItemType Directory -Path $eventDestination -ErrorAction Stop | Out-Null
    CheckDir $eventDestination
    $eventId = ([regex]::Match((Split-Path -Leaf $oldEvent.EventPath),
        '^event-([0-9a-f]{32})\.json$')).Groups[1].Value
    $retry = Join-Path $inbox ('preprovider-retry-' + $eventId + '.json')
    if (Test-Path -LiteralPath $retry) {
        CheckFile $retry
        if ((Get-Item -LiteralPath $retry).Length -gt 1024) { Hold 'RETRY_FILE_INVALID' }
        [IO.File]::Move($retry,(Join-Path $eventDestination (Split-Path -Leaf $retry)))
    }
    $claimDestination = Join-Path $eventDestination (Split-Path -Leaf $oldEvent.ClaimPath)
    $eventFileDestination = Join-Path $eventDestination (Split-Path -Leaf $oldEvent.EventPath)
    [IO.File]::Move($oldEvent.ClaimPath,$claimDestination)
    [IO.File]::Move($oldEvent.EventPath,$eventFileDestination)
    if ((Hash $claimDestination) -cne $oldEvent.ClaimSha256 -or
        (Hash $eventFileDestination) -cne $oldEvent.EventSha256) {
        Hold 'ARCHIVE_CLAIM_EVENT_HASH_DRIFT'
    }
    $jobDestination = Join-Path $jobRecovery ('batch15-v3-' + $transaction)
    [IO.Directory]::Move($oldJob,$jobDestination)
    CheckDir $jobDestination
    if ((Hash (Join-Path $jobDestination ($batch + '.inflight'))) -cne $markerSHA) {
        Hold 'ARCHIVE_MARKER_DRIFT'
    }
    if (@(Get-ChildItem -LiteralPath $inbox -Filter 'event-*.json' -File -Force).Count -ne 0) {
        Hold 'PENDING_REMAINS'
    }
    if (Test-Path -LiteralPath $oldEvent.ClaimPath) { Hold 'OLD_CLAIM_REMAINS' }
    foreach ($remaining in @(Get-ChildItem -LiteralPath $stateRoot -Directory -Force)) {
        if (@(Get-ChildItem -LiteralPath $remaining.FullName -Filter 'batch-*.inflight' -File).Count -gt 0 -or
            (Test-Path -LiteralPath (Join-Path $remaining.FullName 'active.lock'))) {
            Hold 'ACTIVE_JOB_REMAINS'
        }
    }
    Receipt 'ARCHIVED_OWNER_STOPPED'
    $stage = 'RESTART'
    if (-not (FreshOwner $oldPID)) { Hold 'NEW_OWNER_NOT_HEALTHY' }
    Receipt 'ARCHIVED_OWNER_RUNNING_WAIT_NEW_TV_REQUEST'
} catch {
    $message = [string]$_.Exception.Message
    $reason = if ($message -cmatch '^OWNER_P2_B15_V3_([A-Z0-9_]+)$') {
        $Matches[1] } else { 'UNCLASSIFIED' }
    if (-not $mutationStarted) {
        Receipt ('PREFLIGHT_HOLD_' + $stage + '_' + $reason)
    } else {
        try { StopOwner } catch { }
        Receipt ('HOLD_OWNER_DISABLED_' + $stage + '_' + $reason)
    }
    throw
}
