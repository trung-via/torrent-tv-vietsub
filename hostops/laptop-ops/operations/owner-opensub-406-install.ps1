# One Owner-interactive OwnerBridge HTTP-406 repair after exact P2 B11 quarantine.
# Three SHA-pinned Python modules only; no APK, paid API call or event replay.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCommit = '84b6b58fca7fd807d2bcac30db6ef60b8f6a09d5'
$files = [ordered]@{
    'automatic_vietsub_flow.py' = @{
        before = 'cdbc664eea7e7e53d6496e6595c1eca32695c414c938bdd5e0949f95d41b8382'
        desired = '7f0b644d2aad74e87d5559e0b1bbe95adb302072dcbeb7fefef640a0a083308d'
    }
    'opensubtitles.py' = @{
        before = '990640634fbe93763b8f08f1bcc02c26e8871f4bd4e4a58981ac914e1acbb2d9'
        desired = '3711dab1d40de9751d17cb3b5d9fbe485c644e6e2488b05e7d248cf5bb93a3f0'
    }
    'owner_session_bridge.py' = @{
        before = '1ced244ccc62e1ad54fe22d7eb2ff6d5a6cc2c9328a7d3f1beeeee060fa357cc'
        desired = 'e7924b6aaa1597e61eb23f9822dec348023f25ed252a1c6ad74366502d1c2406'
    }
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installed = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$health = Join-Path $ownerRoot 'agent-health.json'
$quarantineSha = '40f98035778158467cce7b8e2016166763a3f5085381c0b90e2349e19f7252c5'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Hold([string]$code) { throw ('OWNER_406_INSTALL_HOLD_' + $code) }
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function CheckFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Hold 'FILE_MISSING' }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint) { Hold 'REPARSE_PATH' }
}
function OwnerTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $ownerId = [string]$task.Principal.UserId
    if ($ownerId -notmatch '^S-\d+(?:-\d+){2,}$') {
        $ownerId = ([Security.Principal.NTAccount]::new($ownerId).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($ownerId -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('python.exe','pythonw.exe','py.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function AssertNoActiveP2 {
    $inbox = Join-Path $ownerRoot 'inbox'
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count) {
            Hold 'PENDING_OWNER_EVENT'
        }
    }
    if (Test-Path -LiteralPath $state -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $state -File -Recurse |
                Where-Object { $_.Name -like 'batch-*.inflight' -or
                               $_.Name -ceq 'active.lock' }).Count) {
            Hold 'P2_INFLIGHT_OR_ACTIVE_LOCK'
        }
    }
}
function AssertQuarantinedB11 {
    if (-not (Test-Path -LiteralPath $state -PathType Container)) { Hold 'P2_STATE_MISSING' }
    $archives = @(Get-ChildItem -LiteralPath $state -Recurse -File -Filter 'batch-0011.quarantined')
    if ($archives.Count -ne 1 -or (Hash $archives[0].FullName) -cne $quarantineSha) {
        Hold 'EXACT_B11_ARCHIVE_NOT_VERIFIED'
    }
    $ledger = Join-Path $archives[0].DirectoryName 'batch-0011.abandoned.json'
    CheckFile $ledger
    $record = Get-Content -LiteralPath $ledger -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($record.schema -cne 'TTV-P2-ABANDONED-UNKNOWN-EFFECT-V1' -or
        $record.version -ne 11 -or
        $record.job -cne $archives[0].Directory.Name -or
        $record.marker_sha256 -cne $quarantineSha -or
        $record.result -cne 'UNKNOWN_EFFECT_NO_RETRY') {
        Hold 'B11_NO_RETRY_LEDGER_INVALID'
    }
    AssertNoActiveP2
}
function StartOwner([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i = 0; $i -lt 35; $i++) {
        Start-Sleep -Seconds 1
        if ([string](OwnerTask).State -cne 'Running') { continue }
        try {
            $entry = Get-Content -LiteralPath $health -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($entry.state -cne 'READY' -or [long]$entry.pid -eq $oldPid -or
                [long]$entry.observed_utc_epoch -lt $since - 2) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [long]$entry.pid)
            if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
                continue
            }
            $identity = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($identity.ReturnValue -eq 0 -and $identity.Sid -ceq $sid) { return }
        } catch { continue }
    }
    Hold 'FRESH_OWNER_HEALTH_NOT_VERIFIED'
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20')) { Hold 'OWNER_INTERACTIVE_REQUIRED' }
foreach ($path in @($ownerRoot, $installed)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) { Hold 'OWNER_INSTALL_ROOT_INVALID' }
}
$task = OwnerTask
if ([string]$task.State -cne 'Disabled') { Hold 'POST_QUARANTINE_TASK_NOT_DISABLED' }
if (@(OwnerWorkers).Count -ne 0) { Hold 'OWNER_WORKERS_PRESENT' }
AssertQuarantinedB11

$stage = Join-Path $env:TEMP ('ttv-406-stage-' + [Guid]::NewGuid().ToString('N'))
$backup = Join-Path $ownerRoot ('backups\owner-406-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
$changed = [System.Collections.Generic.List[string]]::new()
$changedAny = $false
$restartAttempted = $false
$oldPid = 0L
if (Test-Path -LiteralPath $health -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
    catch { Hold 'PREVIOUS_HEALTH_UNREADABLE' }
}
try {
    $already = 0
    foreach ($name in $files.Keys) {
        $target = Join-Path $installed $name
        CheckFile $target
        $current = Hash $target
        if ($current -cne $files[$name].before -and
            $current -cne $files[$name].desired) { Hold 'INSTALLED_SOURCE_DRIFT' }
        if ($current -ceq $files[$name].desired) { $already++ }
        $source = Join-Path $stage $name
        $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
            $sourceCommit + '/poc/p2-sub-discovery/' + $name
        Invoke-WebRequest -Uri $uri -OutFile $source -ErrorAction Stop
        if ((Hash $source) -cne $files[$name].desired) { Hold 'SOURCE_HASH_MISMATCH' }
    }
    if ($already -eq $files.Count) {
        Write-Output 'OWNER_406_INSTALL=ALREADY_INSTALLED_HASH_VERIFIED_RESTART_REQUIRED'
    } else {
        AssertQuarantinedB11
        if (@(OwnerWorkers).Count -ne 0 -or [string](OwnerTask).State -cne 'Disabled') {
            Hold 'POST_QUARANTINE_CONCURRENCY_DRIFT'
        }
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        foreach ($name in $files.Keys) {
            $target = Join-Path $installed $name
            $safeCopy = Join-Path $backup $name
            Copy-Item -LiteralPath $target -Destination $safeCopy -ErrorAction Stop
            if ((Hash $safeCopy) -cne (Hash $target)) { Hold 'BACKUP_HASH_MISMATCH' }
        }
        foreach ($name in $files.Keys) {
            $target = Join-Path $installed $name
            $next = Join-Path $installed ('.owner406-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination $next -ErrorAction Stop
            # File.Replace requires an explicit third path on Windows.
            [IO.File]::Replace($next, $target, (Join-Path $backup ('atomic-' + $name)))
            $changedAny = $true
            $changed.Add($name)
            if ((Hash $target) -cne $files[$name].desired) { Hold 'INSTALLED_HASH_MISMATCH' }
        }
        Push-Location -LiteralPath $installed
        try {
            & py -3.14 -B -c 'import automatic_vietsub_flow, opensubtitles, owner_session_bridge' *> (Join-Path $backup 'import-check.log')
            if ($LASTEXITCODE -ne 0) { Hold 'OFFLINE_IMPORT_FAILED' }
        } finally { Pop-Location }
    }
    AssertQuarantinedB11
    $restartAttempted = $true
    StartOwner $oldPid
    foreach ($name in $files.Keys) {
        if ((Hash (Join-Path $installed $name)) -cne $files[$name].desired) {
            Hold 'POST_RESTART_SOURCE_HASH_DRIFT'
        }
    }
    Write-Output 'OWNER_406_INSTALL=INSTALLED_FRESH_OWNER_RUNNING'
    Write-Output 'OWNER_406_INSTALL_PROVIDER_POST=NOT_RUN'
    Write-Output 'OWNER_406_INSTALL_TV_APK=UNCHANGED'
    Write-Output ('OWNER_406_INSTALL_BACKUP=' + $backup)
} catch {
    $cause = $_.Exception.Message
    if ($changedAny -or $restartAttempted) {
        try {
            Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
            for ($i=0; $i -lt 8 -and @(OwnerWorkers).Count -ne 0; $i++) {
                Start-Sleep -Seconds 1
            }
            if (@(OwnerWorkers).Count -ne 0) { Hold 'ROLLBACK_OWNER_WORKERS_STILL_RUNNING' }
            if ($changedAny) {
                foreach ($name in $changed) {
                    $original = Join-Path $backup $name
                    Copy-Item -LiteralPath $original -Destination (Join-Path $installed $name) -Force -ErrorAction Stop
                    if ((Hash (Join-Path $installed $name)) -cne (Hash $original)) {
                        Hold 'ROLLBACK_HASH_MISMATCH'
                    }
                }
            }
            Write-Output 'OWNER_406_INSTALL=ROLLED_BACK_ORIGINAL_FILES_TASK_DISABLED'
        } catch { Write-Output 'OWNER_406_INSTALL=ROLLBACK_UNCERTAIN_TASK_DISABLED' }
    }
    throw $cause
} finally {
    # Leave durable Owner backup untouched; only temporary source staging is disposable.
    if (Test-Path -LiteralPath $stage -PathType Container) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
