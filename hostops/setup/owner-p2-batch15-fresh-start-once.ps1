# Fixed, once-only Owner-interactive cleanup of the observed P2 batch-0015
# unknown-effect hold. This DOES NOT call any provider or TV API. The entire
# historical job and its matching unclaimed event are moved to private,
# recoverable archives, outside the worker's active state and queue roots.
# A new translation is possible only after a subsequent on-TV viewer request.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$batch = 'batch-0015'
$markerSha = '4158f5ac6b0922e2eb58b5c1ecf5e5d40c85a6e69bb484e579c242c517478ab5'
$workerBlob = '69245ba65db167a63643ddcd6a4ce4a81a38a1e2'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$homeRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$ownerRoot = Join-Path $homeRoot 'OwnerBridge'
$app = Join-Path $ownerRoot 'app'
$stateRoot = Join-Path $homeRoot 'P2\auto-lean120-state'
$jobArchiveRoot = Join-Path $homeRoot 'P2\recovery'
$inbox = Join-Path $ownerRoot 'inbox'
$eventArchiveRoot = Join-Path $ownerRoot 'recovery'
$healthPath = Join-Path $ownerRoot 'agent-health.json'
$receiptDir = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts'
$receiptPath = Join-Path $receiptDir 'p2-batch15-fresh-start.json'

function Hold([string]$code) { throw ('OWNER_P2_FRESH_START_HOLD_' + $code) }
function PlainDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_REPARSE'
    }
}
function PlainFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_REPARSE'
    }
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function WriteReceipt([string]$result) {
    $doc = [ordered]@{schema='TTV-OWNER-P2-BATCH15-FRESH-START-V1'; batch=$batch;
        marker_sha256=$markerSha; result=$result;
        observed_utc_epoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
    $temp = $receiptPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($temp,($doc | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp,$receiptPath,$true)
    Write-Output ('OWNER_P2_FRESH_START=' + $result)
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertWorkers($list) {
    if (@($list).Count -gt 4) { Hold 'TOO_MANY_WORKERS' }
    $allowed = @((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
        (Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($p in $list) {
        if ($null -eq $p.CreationDate -or
            @($allowed | Where-Object { [string]$p.CommandLine -and
                $p.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count -ne 1) {
            Hold 'UNKNOWN_WORKER_COMMAND'
        }
        $workerOwner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
        if ($workerOwner.ReturnValue -ne 0 -or $workerOwner.Sid -cne $identity.User.Value) {
            Hold 'WORKER_OWNER_MISMATCH'
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
    for ($i=0;$i -lt 10;$i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $stuck = @(Workers)
    AssertWorkers $stuck
    foreach ($p in $stuck) {
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$p.ProcessId)
        if ($null -eq $live) { continue }
        if ([string]$live.CommandLine -cne [string]$p.CommandLine -or
            $live.CreationDate -ne $p.CreationDate) { Hold 'WORKER_CHANGED' }
        AssertWorkers @($live)
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0;$i -lt 10;$i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'WORKER_NOT_STOPPED'
}
function VerifyNewOwner([long]$oldPid) {
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0;$i -lt 45;$i++) {
        Start-Sleep -Seconds 1
        if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Running') { continue }
        if (-not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { continue }
        PlainFile $healthPath
        if ((Get-Item -LiteralPath $healthPath).Length -gt 512) { continue }
        try { $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json -AsHashtable }
        catch { continue }
        if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
            $h.state -cne 'READY' -or $h.pid -isnot [ValueType] -or
            [long]$h.pid -le 0 -or [long]$h.pid -eq $oldPid -or
            $h.observed_utc_epoch -isnot [ValueType]) { continue }
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($age -lt 0 -or $age -gt 20) { continue }
        $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid) -ErrorAction SilentlyContinue
        if ($null -eq $p -or [string]$p.CommandLine -notmatch
            'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') { continue }
        AssertWorkers @($p)
        return $true
    }
    return $false
}
function InspectState {
    PlainDir $stateRoot
    $jobs = @(Get-ChildItem -LiteralPath $stateRoot -Force -ErrorAction Stop)
    if ($jobs.Count -gt 64) { Hold 'UNBOUNDED_JOB_COUNT' }
    $markers = @()
    foreach ($job in $jobs) {
        if (-not $job.PSIsContainer -or $job.Name -cnotmatch '^[0-9a-f]{64}$') {
            Hold 'UNEXPECTED_STATE_ENTRY'
        }
        PlainDir $job.FullName
        foreach ($child in @(Get-ChildItem -LiteralPath $job.FullName -Force)) {
            if ($child.PSIsContainer -or
                ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Hold 'UNEXPECTED_JOB_ENTRY'
            }
            if ($child.Name -clike 'batch-*.inflight') { $markers += $child }
        }
    }
    if ($markers.Count -ne 1 -or $markers[0].Name -cne ($batch + '.inflight')) {
        Hold 'MARKER_COUNT_OR_BATCH_DRIFT'
    }
    $marker = $markers[0].FullName
    PlainFile $marker
    if ((Get-Item -LiteralPath $marker).Length -gt 4096 -or (Hash $marker) -cne $markerSha) {
        Hold 'MARKER_SHA_DRIFT'
    }
    $jobFolder = Split-Path -Parent $marker
    $jobName = Split-Path -Leaf $jobFolder
    $data = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($data.Keys).Count -ne 3 -or $data.schema -cne 'TTV-P2-INFLIGHT-V1' -or
        $data.job -cne $jobName -or $data.version -isnot [ValueType] -or
        [long]$data.version -ne 15) { Hold 'MARKER_SCHEMA_DRIFT' }
    if (Test-Path -LiteralPath (Join-Path $jobFolder ($batch + '.json'))) {
        Hold 'BATCH15_CHECKPOINT_EXISTS'
    }
    $lock = Join-Path $jobFolder 'active.lock'
    PlainFile $lock
    if ([IO.File]::ReadAllText($lock) -cne "TTV-P2-LOCK-V1`n") { Hold 'LOCK_CONTENT_DRIFT' }
    $children = @(Get-ChildItem -LiteralPath $jobFolder -Force)
    if ($children.Count -gt 256 -or
        @($children | Where-Object { $_.Length -gt 4194304 }).Count -gt 0) {
        Hold 'UNBOUNDED_JOB_FILES'
    }
    return $jobFolder
}
function InspectPendingEvent {
    PlainDir $inbox
    $pending = @(Get-ChildItem -LiteralPath $inbox -Filter 'event-*.json' -File -Force)
    if ($pending.Count -ne 1) { Hold 'PENDING_EVENT_COUNT_DRIFT' }
    $eventFile = $pending[0]
    PlainFile $eventFile.FullName
    $eventMatch = [regex]::Match($eventFile.Name,'^event-([0-9a-f]{32})\.json$')
    if (-not $eventMatch.Success -or
        $eventFile.Length -gt 768) { Hold 'EVENT_FILE_INVALID' }
    $eventId = $eventMatch.Groups[1].Value
    $doc = Get-Content -LiteralPath $eventFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    if (@($doc.Keys).Count -ne 5 -or $doc.schema -cne 'TTV-OWNER-VIDEO-EVENT-V3' -or
        $doc.event_id -cne $eventId -or
        $doc.source_fingerprint -cnotmatch '^[0-9a-f]{64}$' -or
        $doc.tv_session_id -cnotmatch '^[A-Za-z0-9_-]{1,128}$' -or
        $doc.selected_video_filename -isnot [string] -or
        [string]::IsNullOrWhiteSpace($doc.selected_video_filename) -or
        $doc.selected_video_filename.Length -gt 255 -or
        $doc.selected_video_filename -match '[/\\]') { Hold 'EVENT_SCHEMA_DRIFT' }
    if (Test-Path -LiteralPath (Join-Path $inbox ('claim-' + $eventId))) {
        Hold 'PENDING_EVENT_CLAIMED'
    }
    if (Test-Path -LiteralPath (Join-Path $inbox ('preprovider-retry-' + $eventId + '.json'))) {
        Hold 'PENDING_EVENT_RETRY_PRESENT'
    }
    # Match a prior already-blocked event *inside the Owner's private inbox*.
    # No video name or fingerprint is copied into public source or HostOps.
    $matched = $false
    foreach ($old in @(Get-ChildItem -LiteralPath $inbox -Filter 'event-*.blocked' -File -Force)) {
        PlainFile $old.FullName
        if ($old.Length -gt 768) { continue }
        try { $blocked = Get-Content -LiteralPath $old.FullName -Raw -Encoding UTF8 |
                ConvertFrom-Json -AsHashtable }
        catch { continue }
        if ($blocked.schema -ceq 'TTV-OWNER-VIDEO-EVENT-V3' -and
            $blocked.source_fingerprint -ceq $doc.source_fingerprint -and
            $blocked.selected_video_filename -ceq $doc.selected_video_filename) {
            $matched = $true; break
        }
    }
    if (-not $matched) { Hold 'PENDING_EVENT_NOT_PROVEN_SAME_MEDIA' }
    return $eventFile.FullName
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($PSVersionTable.PSVersion.Major -ne 7 -or $env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_PWSH7_REQUIRED'
}
foreach ($dir in @($homeRoot,$ownerRoot,$app,$stateRoot,$inbox,$receiptDir)) { PlainDir $dir }
if (Test-Path -LiteralPath $receiptPath) { Hold 'ALREADY_ATTEMPTED_NO_REPLAY' }
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
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
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1' -or
    [string]$task.State -cne 'Running') { Hold 'ORIGINAL_OWNER_TASK_DRIFT' }

$snapshot = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
PlainFile $snapshot
if ((Get-Item -LiteralPath $snapshot).Length -gt 4096) { Hold 'SNAPSHOT_TOO_LARGE' }
$s = Get-Content -LiteralPath $snapshot -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$s.snapshot_utc_epoch
if ($s.schema -cne 'TTV-HOSTOPS-OWNER-SNAPSHOT-V2' -or
    $s.status -cne 'READY_FRESH' -or $s.p3_state -cne 'FRESH_OFF' -or
    $age -lt 0 -or $age -gt 30 -or
    $s.p2.status -cne 'UNKNOWN_EFFECT_HOLD' -or
    $s.p2.pending_events -ne 1 -or $s.p2.inflight_count -ne 1 -or
    $s.p2.batch -cne $batch -or $s.p2.marker_sha256 -cne $markerSha -or
    $s.p2.checkpoint_present -cne 'NO' -or
    $s.p2.active_lock_present -cne 'YES' -or
    $s.p2.installed_no_retry_worker_match -cne 'YES') { Hold 'FRESH_TV_OFF_P2_PREFLIGHT_DRIFT' }

$workerPath = Join-Path $app 'poc\p2-aisub\automatic_lean120_worker.py'
PlainFile $workerPath
$source = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($workerPath)).Replace("`r`n","`n")
if ($source.StartsWith([char]0xfeff) -or $source.Contains("`r")) { Hold 'WORKER_BYTES_DRIFT' }
$workerBytes = [Text.UTF8Encoding]::new($false).GetBytes($source)
$prefix = [Text.Encoding]::ASCII.GetBytes("blob $($workerBytes.Length)`0")
$blob = [byte[]]::new($prefix.Length + $workerBytes.Length)
[Array]::Copy($prefix,0,$blob,0,$prefix.Length)
[Array]::Copy($workerBytes,0,$blob,$prefix.Length,$workerBytes.Length)
if ([Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($blob)).ToLowerInvariant() -cne $workerBlob) {
    Hold 'NO_RETRY_WORKER_NOT_INSTALLED'
}

$beforeJob = InspectState
$beforeEvent = InspectPendingEvent
AssertWorkers @(Workers)
$oldPid = 0L
if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
    try { $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json -AsHashtable
        if ($h.pid -is [ValueType]) { $oldPid = [long]$h.pid } }
    catch { $oldPid = 0L }
}

# STARTED is a durable no-retry sentinel, written before any mutation.
# Any partial failure leaves the original Owner Task disabled for review.
WriteReceipt 'STARTED_NO_PROVIDER_REPLAY'
try {
    StopOwner
    if ([string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -cne 'Disabled' -or
        @(Workers).Count -ne 0) { Hold 'OWNER_NOT_STOPPED' }
    $job = InspectState
    $event = InspectPendingEvent
    if ($job -cne $beforeJob -or $event -cne $beforeEvent) { Hold 'STATE_CHANGED_DURING_STOP' }
    foreach ($dir in @($jobArchiveRoot,$eventArchiveRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -ErrorAction Stop | Out-Null
        }
        PlainDir $dir
    }
    $transaction = [Guid]::NewGuid().ToString('N')
    $eventArchive = Join-Path $eventArchiveRoot ('p2-batch15-' + $transaction)
    New-Item -ItemType Directory -Path $eventArchive -ErrorAction Stop | Out-Null
    PlainDir $eventArchive
    [IO.File]::Move($event,(Join-Path $eventArchive (Split-Path -Leaf $event)))
    $jobDestination = Join-Path $jobArchiveRoot ('batch15-' + $transaction)
    [IO.Directory]::Move($job,$jobDestination)
    PlainDir $jobDestination
    if (-not (Test-Path -LiteralPath (Join-Path $jobDestination ($batch + '.inflight')) -PathType Leaf)) {
        # Marker lives one level down? The destination IS the job directory.
        Hold 'ARCHIVED_MARKER_MISSING'
    }
    if ((Hash (Join-Path $jobDestination ($batch + '.inflight'))) -cne $markerSha) {
        Hold 'ARCHIVED_MARKER_HASH_CHANGED'
    }
    if (@(Get-ChildItem -LiteralPath $inbox -Filter 'event-*.json' -File -Force).Count -ne 0) {
        Hold 'NEW_PENDING_EVENT_DURING_ARCHIVE'
    }
    foreach ($remaining in @(Get-ChildItem -LiteralPath $stateRoot -Directory -Force)) {
        if (@(Get-ChildItem -LiteralPath $remaining.FullName -Filter 'batch-*.inflight' -File).Count -gt 0 -or
            (Test-Path -LiteralPath (Join-Path $remaining.FullName 'active.lock'))) {
            Hold 'ACTIVE_JOB_REMAINS'
        }
    }
    WriteReceipt 'PRIVATE_ARCHIVE_COMPLETE_OWNER_STOPPED'
    if (-not (VerifyNewOwner $oldPid)) { Hold 'RESTART_NOT_FRESH' }
    WriteReceipt 'ARCHIVED_OWNER_RESTARTED_WAIT_NEW_VIEWER_REQUEST'
} catch {
    # Never auto-rollback the uncertain paid effect, automatically replay an
    # archived request, or start a task whose state cannot be attested.
    try { StopOwner } catch { }
    WriteReceipt 'HOLD_OWNER_DISABLED_RECOVERY_PRESERVED'
    throw
}
