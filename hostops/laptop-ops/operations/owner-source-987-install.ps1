# One-time Owner-interactive, source-pinned fix for PR #178 subtitle-source selection.
# The two changed modules must ALREADY be SHA-verified by the separate Owner stage task.
# Nothing touches P2 caches, subtitles, TV, provider credentials, or movie data.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCommit = '9ff74b31672ea6c90b6aba1b2c234b0fe0aa26fa'
$moduleHashes = [ordered]@{
    'automatic_vietsub_flow.py' = 'caba20a16c98b041b10fd24fac33645a967b34f00186280b39a5d0c5a611336c'
    'matcher.py' = 'cf77148a39ea87e7e958b7a2a00b32a75d6e4703a038fef09aa92b93562f86af'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $root 'app\poc\p2-sub-discovery'
$stage = Join-Path $root ('staged-releases\owner-r2-sidecar-178-' + $sourceCommit.Substring(0,12) + '\poc\p2-sub-discovery')
$health = Join-Path $root 'agent-health.json'
$p2state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$touched = $false
$backup = $null
$previous = @{}
$changed = [Collections.Generic.List[string]]::new()
$oldPid = 0L

function Hold([string]$reason) {
    Write-Output ('OWNER_SOURCE_987=HOLD_' + $reason)
    throw ('OWNER_SOURCE_987_HOLD_' + $reason)
}
function ExactFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_LINK'
    }
}
function ExactDir([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_LINK'
    }
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    ExactDir $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    if (Test-Path -LiteralPath $p2state) {
        ExactDir $p2state
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2state -File -Recurse -Filter $pattern).Count -ne 0) {
                Hold 'P2_JOB_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function Task {
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
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function StopOwner {
    $task = Task
    NoOpenWork
    if ([string]$task.State -eq 'Running') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    } elseif ([string]$task.State -eq 'Ready') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    } elseif ([string]$task.State -ne 'Disabled') {
        Hold 'OWNER_TASK_UNEXPECTED_STATE'
    }
    for ($i=0; $i -lt 6; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT_UNVERIFIED' }
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $matching = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($matching.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenWork
        if ([string](Task).State -ne 'Disabled') { Hold 'TASK_REENABLED_UNEXPECTEDLY' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $identity = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0; $i -lt 10; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKER_STILL_RUNNING'
}
function VerifyStopped {
    if ([string](Task).State -ne 'Disabled' -or @(Workers).Count -ne 0) {
        Hold 'OWNER_NOT_QUIESCENT'
    }
    NoOpenWork
}
function StartAndVerify([long]$priorPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 35; $i++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -ne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $record = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($record.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
                $record.state -cne 'READY' -or
                [long]$record.pid -le 0 -or [long]$record.pid -eq $priorPid -or
                [long]$record.observed_utc_epoch -lt ($since - 2)) { continue }
            $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$record.pid)
            if (-not $process -or
                [string]$process.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $identity = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($identity.ReturnValue -eq 0 -and $identity.Sid -ceq $ownerSid) { return $true }
        } catch { continue }
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
ExactDir $installed
ExactDir $stage
$task = Task
if ([string]$task.State -ne 'Running') { Hold 'OWNER_TASK_NOT_RUNNING' }
NoOpenWork
foreach ($name in $moduleHashes.Keys) {
    $file = Join-Path $stage $name
    ExactFile $file
    if ((Get-Item -LiteralPath $file).Length -gt 1048576 -or
        (Hash $file) -cne $moduleHashes[$name]) { Hold 'STAGED_BYTES_DRIFT' }
    $target = Join-Path $installed $name
    if (Test-Path -LiteralPath $target) { ExactFile $target }
}
$missing = @($moduleHashes.Keys | Where-Object {
    $target = Join-Path $installed $_
    -not (Test-Path -LiteralPath $target -PathType Leaf) -or
        (Hash $target) -cne $moduleHashes[$_]
})
if ($missing.Count -eq 0) {
    Write-Output 'OWNER_SOURCE_987=ALREADY_INSTALLED_NO_RESTART'
    return
}
if (Test-Path -LiteralPath $health) {
    try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
    catch { $oldPid = 0L }
}

try {
    $touched = $true
    StopOwner
    VerifyStopped
    $backup = Join-Path $root ('backups\owner-source-987-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backup) | Out-Null
    foreach ($name in $moduleHashes.Keys) {
        $target = Join-Path $installed $name
        if (Test-Path -LiteralPath $target) {
            $saved = Join-Path $backup $name
            [IO.File]::Copy($target,$saved,$false)
            if ((Hash $saved) -cne (Hash $target)) { Hold 'BACKUP_HASH_MISMATCH' }
            $previous[$name] = (Hash $saved)
        } else { $previous[$name] = 'ABSENT' }
    }
    $receipt = [ordered]@{
        schema='TTV-OWNER-SIDECAR-178-RECOVERY-V1'; source_commit=$sourceCommit
        previous=$previous; utc_epoch=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    [IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
        ($receipt | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
    foreach ($name in $moduleHashes.Keys) {
        VerifyStopped
        $target = Join-Path $installed $name
        if ($previous[$name] -ne 'ABSENT' -and (Hash $target) -cne $previous[$name]) {
            Hold 'BASELINE_CHANGED_BEFORE_SWAP'
        }
        $temp = Join-Path $installed ('.sidecar-178-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy((Join-Path $stage $name),$temp,$false)
        if ((Hash $temp) -cne $moduleHashes[$name]) { Hold 'TEMP_SOURCE_DRIFT' }
        if ($previous[$name] -eq 'ABSENT') {
            if (Test-Path -LiteralPath $target) { Hold 'NEW_FILE_PATH_CONFLICT' }
            [IO.File]::Move($temp,$target)
        } else {
            [IO.File]::Replace($temp,$target,(Join-Path $backup ('displaced-' + $name)))
        }
        $changed.Add($name)
        if ((Hash $target) -cne $moduleHashes[$name]) { Hold 'INSTALLED_HASH_DRIFT' }
    }
    VerifyStopped
    Push-Location -LiteralPath $installed
    try {
        & py -3 -B -c 'import automatic_vietsub_flow; import owner_torrserver_subs; import p3_owner_state_wiring; print("OWNER_SOURCE_987_IMPORT_PASS")' `
            *> (Join-Path $backup 'import-smoke.log')
        if ($LASTEXITCODE -ne 0) { Hold 'OFFLINE_IMPORT_FAILED' }
    } finally { Pop-Location }
    Write-Output 'OWNER_SOURCE_987=OFFLINE_IMPORT_PASS'
    if (-not (StartAndVerify $oldPid)) { Hold 'FRESH_OWNER_HEALTH_FAILED' }
    Write-Output 'OWNER_SOURCE_987=INSTALLED_FRESH_OWNER_RUNNING'
    Write-Output 'OWNER_SOURCE_987=P2_CACHE_UNCHANGED_PROVIDER_TV_NOT_CALLED'
} catch {
    $failure = $_
    Write-Output 'OWNER_SOURCE_987=INSTALL_FAILED_ROLLBACK_START'
    if ($null -ne $backup) {
        @($failure.Exception.ToString(),$failure.ScriptStackTrace) |
            Set-Content -LiteralPath (Join-Path $backup 'failure-private.log') -Encoding utf8
    }
    if ($touched) {
        StopOwner
        VerifyStopped
        $reverse = $changed.ToArray()
        [array]::Reverse($reverse)
        foreach ($name in $reverse) {
            $target = Join-Path $installed $name
            if ((Hash $target) -cne $moduleHashes[$name]) { Hold 'ROLLBACK_TARGET_DRIFT' }
            if ($previous[$name] -eq 'ABSENT') {
                [IO.File]::Delete($target)
            } else {
                $saved = Join-Path $backup $name
                if ((Hash $saved) -cne $previous[$name]) { Hold 'ROLLBACK_BACKUP_DRIFT' }
                $temp = Join-Path $installed ('.sidecar-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy($saved,$temp,$false)
                [IO.File]::Replace($temp,$target,(Join-Path $backup ('failed-' + $name)))
                if ((Hash $target) -cne $previous[$name]) { Hold 'RESTORE_HASH_DRIFT' }
            }
        }
        if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RECOVERY_FAILED' }
    }
    Hold 'INSTALL_FAILED_OLD_OWNER_RECOVERED'
}
