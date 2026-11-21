# One authorized fresh start for the single failed P2 batch-0002 job.
# Move its entire source/checkpoint/uncertain-marker folder to a private
# recoverable archive. Never replay an event or invoke the AI provider/TV.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $ownerRoot 'app'
$inbox = Join-Path $ownerRoot 'inbox'
$healthPath = Join-Path $ownerRoot 'agent-health.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$archiveRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\ArchivedRetryJobs'
$gateway = Join-Path $app 'poc\p2-aisub\translator_gateway.py'
$expectedGatewaySha = 'd63c468a6417fab87d6c9e56e6dd319ddc28289f7c95eb064eaf9684d5774fc3'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$oldPid = 0L
$disabled = $false
$moved = $false
$destination = ''

function Hold([string]$reason) {
    Write-Output ('P2_BATCH2_ARCHIVE=HOLD_' + $reason)
    throw 'P2_BATCH2_ARCHIVE_NO_RETRY'
}
function Plain([string]$path, [bool]$directory) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        [bool]$item.PSIsContainer -ne $directory) { Hold 'PATH_NOT_PLAIN' }
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
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
    $task
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertIdle {
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json' -ErrorAction Stop).Count -ne 0 -or
        @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'active.lock' -ErrorAction Stop).Count -ne 0) {
        Hold 'P2_BUSY_OR_PENDING_EVENT'
    }
}
function StopOwner {
    $task = Task
    if ([string]$task.State -cne 'Running') { Hold 'OWNER_NOT_RUNNING' }
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $script:disabled = $true
    Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i = 0; $i -lt 12; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    AssertIdle
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT' }
    $allowed = @((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $match = @($allowed | Where-Object {
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $who = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($match.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $who.ReturnValue -ne 0 -or $who.Sid -cne $sid) {
            Hold 'RESIDUAL_WORKER_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        AssertIdle
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
    for ($i = 0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKERS_STILL_RUNNING'
}
function StartOwner([long]$previousPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $script:disabled = $false
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i = 0; $i -lt 30; $i++) {
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
    $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'OWNER_INTERACTIVE_REQUIRED'
}
foreach ($path in @($ownerRoot,$app,$inbox,$stateRoot)) { Plain $path $true }
Plain $gateway $false
if ((Hash $gateway) -cne $expectedGatewaySha) { Hold 'PATCH_NOT_INSTALLED' }
if ([string](Task).State -cne 'Running') { Hold 'OWNER_NOT_RUNNING' }
AssertIdle
$markers = @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight' -ErrorAction Stop)
if ($markers.Count -ne 1 -or $markers[0].Name -cne 'batch-0002.inflight') {
    Hold 'EXACT_BATCH2_NOT_UNIQUE'
}
$marker = $markers[0]
$folder = $marker.Directory.FullName
if ($marker.Directory.Name -cnotmatch '^[0-9a-f]{64}$' -or
    -not $marker.Directory.Parent.FullName.Equals($stateRoot,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'JOB_FOLDER_NOT_DIRECT_CHILD'
}
Plain $folder $true
Plain $marker.FullName $false
$checkpoint = Join-Path $folder 'batch-0001.json'
Plain $checkpoint $false
if (Test-Path -LiteralPath (Join-Path $folder 'batch-0002.json')) {
    Hold 'BATCH2_ALREADY_CHECKPOINTED'
}
$markerDoc = Get-Content -LiteralPath $marker.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
$checkpointDoc = Get-Content -LiteralPath $checkpoint -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if (@($markerDoc.Keys | Sort-Object) -join ',' -cne 'job,schema,version' -or
    $markerDoc.schema -cne 'TTV-P2-INFLIGHT-V1' -or
    $markerDoc.job -cne $marker.Directory.Name -or $markerDoc.version -ne 2 -or
    @($checkpointDoc.Keys | Sort-Object) -join ',' -cne 'job,payload_sha256,schema,translations,version' -or
    $checkpointDoc.schema -cne 'TTV-P2-LEAN120-CHECKPOINT-V1' -or
    $checkpointDoc.job -cne $marker.Directory.Name -or $checkpointDoc.version -ne 1 -or
    [string]$checkpointDoc.payload_sha256 -cnotmatch '^[0-9a-f]{64}$' -or
    @($checkpointDoc.translations).Count -le 0) {
    Hold 'JOB_CHECKPOINT_SCHEMA_MISMATCH'
}
if (@(Get-ChildItem -LiteralPath $folder -Force | Where-Object {
    $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
}).Count -ne 0) { Hold 'JOB_CHILD_PATH_UNTRUSTED' }
$markerSha = Hash $marker.FullName
$checkpointSha = Hash $checkpoint
if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
    try {
        $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
        if ($health.pid -is [ValueType]) { $oldPid = [long]$health.pid }
    } catch { $oldPid = 0L }
}

try {
    StopOwner
    AssertIdle
    $afterStop = @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight')
    if ($afterStop.Count -ne 1 -or $afterStop[0].FullName -cne $marker.FullName -or
        (Hash $marker.FullName) -cne $markerSha -or
        (Hash $checkpoint) -cne $checkpointSha) { Hold 'JOB_CHANGED_DURING_STOP' }
    if (-not (Test-Path -LiteralPath $archiveRoot)) {
        New-Item -ItemType Directory -Path $archiveRoot -ErrorAction Stop | Out-Null
    }
    Plain $archiveRoot $true
    $destination = Join-Path $archiveRoot ('batch2-fresh-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::Move($folder,$destination)
    $moved = $true
    if ((Test-Path -LiteralPath $folder) -or
        (Hash (Join-Path $destination 'batch-0002.inflight')) -cne $markerSha -or
        (Hash (Join-Path $destination 'batch-0001.json')) -cne $checkpointSha) {
        Hold 'ARCHIVE_VERIFY_FAILED'
    }
    if (-not (StartOwner $oldPid)) { Hold 'OWNER_RESTART_UNHEALTHY' }
    Write-Output 'P2_BATCH2_ARCHIVE=ARCHIVED_RECOVERABLY_OWNER_READY'
    Write-Output 'P2_BATCH2_ARCHIVE_PROVIDER=NOT_RUN'
    Write-Output 'P2_BATCH2_ARCHIVE_TV=NOT_RUN'
    Write-Output 'P2_BATCH2_ARCHIVE_EVENT_REPLAY=NOT_RUN'
} catch {
    if ($moved) {
        try {
            if (@(Workers).Count -eq 0 -and -not (Test-Path -LiteralPath $folder) -and
                (Hash (Join-Path $destination 'batch-0002.inflight')) -ceq $markerSha -and
                (Hash (Join-Path $destination 'batch-0001.json')) -ceq $checkpointSha) {
                [IO.Directory]::Move($destination,$folder)
                Write-Output 'P2_BATCH2_ARCHIVE=ROLLED_BACK_JOB_FOLDER'
            }
        } catch { Write-Output 'P2_BATCH2_ARCHIVE=HOLD_ROLLBACK_FAILED' }
    }
    if ($disabled) {
        try {
            Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
            if (@(Workers).Count -eq 0) { Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop }
        } catch { Write-Output 'P2_BATCH2_ARCHIVE=HOLD_OWNER_RECOVERY_FAILED' }
    }
    throw 'P2_BATCH2_ARCHIVE_FAILED_NO_RETRY'
}
