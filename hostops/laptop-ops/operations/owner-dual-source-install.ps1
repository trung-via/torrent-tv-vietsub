# One-shot, exact-source Owner upgrade through the enrolled Owner-interactive
# laptop HostOps task. Never deletes P2 checkpoints, requests or subtitle files.
# Fetch/verify first; require idle P2; preserve old Owner and rollback on error.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = '07fa06200cdb22074aee5b306a9c18d93895b8de'
$pinned = [ordered]@{
    'poc/p2-aisub/paired_activation.py' = '605330ccccaa5092cf97fdcaf3a75dd349cc1ed23eeb2852e3a03259b3dcda85'
    'poc/p2-sub-discovery/owner_hostops_snapshot_v3.py' = '2d3c3b3417f11b3e426c5060ab6a97ec22f907be352b7b74ae18d3a0c215d0a9'
    'poc/p2-sub-discovery/owner_hostops_snapshot.py' = '91e1c3400cfdca347c0cd15c5da9ee942d2a189a095e4ab7cb583a1d7664eb4f'
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = '3febeac9f8ee5f3c0719894e1fb9ba67c91af4439970adbafdcbc8df28d9f953'
    'poc/p2-sub-discovery/owner_p3_p4_policy_r0.py' = 'f52e5ce0fd41fd6bbd593d9dd11265aaf0f8334d85dd99f0ebb075238d918121'
    'poc/p2-sub-discovery/owner_p3_p4_private_policy.py' = '3804a2afa1b66889488a8a515472609b0b4b476f85876f9456a73e2e1bf842c5'
    'poc/p2-sub-discovery/owner_p3_p4_runtime.py' = 'e0f2f4011b0dfabc31855cc351214224128b8a852345d687a9a227b8e28c3116'
    'poc/p2-sub-discovery/owner_r2_progressive_registry.py' = 'd155a5513605e76b676294b6333ec9dac79061761e74426e373a465f58a67710'
    'poc/p2-sub-discovery/owner_r2_progressive_worker.py' = 'f024ac97d6989876975a2c32bffdf3d0dccf51bbbc964b4e0bd29e4e4e3e8457'
    'poc/p2-sub-discovery/owner_r2_verified_processor.py' = '24d653ebe39dcf73c4b80b6b93872cd3af4c1ee4a27973bbae5b4d21031e433f'
    'poc/p2-sub-discovery/owner_session_bridge.py' = '1ced244ccc62e1ad54fe22d7eb2ff6d5a6cc2c9328a7d3f1beeeee060fa357cc'
    'poc/p2-sub-discovery/owner_torrserver_ffp_tracks.py' = '0ebcea4ad6a1d08da12539f06fd7db5a3a4f654ca7697277f868e8ea124a437a'
    'poc/p2-sub-discovery/p3_owner_current_redmi.py' = '69f4da5b2cdc94781b672c9858d4adf2b03837580d78045becf768ec42fb96a0'
    'poc/p2-sub-discovery/p3_owner_state_wiring_r0.py' = '149a914127d3aff5636ecb23d7d5ae1128e28a5b219c868098663bc0510d734b'
    'poc/p2-sub-discovery/p3_owner_state_wiring_r2.py' = 'ee39b7a2a1a04734aa387ba333b2bd4f0e299ac7333f321e5292e2934180578d'
    'poc/p2-sub-discovery/p3_p4_shared_https_route_r0.py' = '7358cfafa901fa0a74743450302d99cb7ee370561c28fa336a73535498a7dadf'
    'poc/p2-sub-discovery/verified_v3_processor.py' = 'a1805198e62df2f3dbf5d3146bc83a33e08545e01bfe09a6609b72090b5ce42c'
    'poc/p2-sub-discovery/automatic_vietsub_flow.py' = 'cdbc664eea7e7e53d6496e6595c1eca32695c414c938bdd5e0949f95d41b8382'
    'poc/p2-sub-discovery/dual_subtitle_catalog.py' = 'cfbb491cd39d4b8ed4a8bb459d3ec79af91298c386381c1b2d56e4702e681b1b'
    'poc/p2-sub-discovery/matcher.py' = '18df6d45786caff6d5c97a11f6d463afeb21820f5766a4d944c3e2f6a1418b83'
    'poc/p2-sub-discovery/opensubtitles.py' = '990640634fbe93763b8f08f1bcc02c26e8871f4bd4e4a58981ac914e1acbb2d9'
    'poc/p2-sub-discovery/owner_en_single_trial.py' = 'd2a47ae5b42080634adb8ed804db9564f34f69f57944f411b37ca31cc1ae5052'
    'poc/p2-sub-discovery/p3_p4_ready_registry.py' = 'd06fb93bc186788c553253e7e1c47bdb5e11f4e091b9a945f36cc2638e444375'
    'poc/p2-sub-discovery/vi_en_fallback.py' = 'ce7323bb3ad2c1e19213be8ef6b43fb27de3a8a87f92d5b2b045380e37f85500'
}

$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$inbox = Join-Path $root 'inbox'
$p2state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$health = Join-Path $root 'agent-health.json'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$interactive = [string](Get-CimInstance Win32_ComputerSystem).UserName

function Hold([string]$phase) {
    Write-Output ('OWNER_DUAL_INSTALL=HOLD_' + $phase)
    throw ('OWNER_DUAL_INSTALL_HOLD_' + $phase)
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function CheckTask {
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
    return $task
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function NoOpenWork {
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0) {
            Hold 'OWNER_PENDING_EVENT'
        }
    }
    if (Test-Path -LiteralPath $p2state -PathType Container) {
        foreach ($pattern in @('batch-*.inflight','active.lock')) {
            if (@(Get-ChildItem -LiteralPath $p2state -File -Recurse -Filter $pattern).Count -ne 0) {
                Hold 'P2_ACTIVE_OR_UNCERTAIN'
            }
        }
    }
}
function StartAndVerify([long]$oldPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0; $i -lt 35; $i++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -ne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $beat = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($beat.state -cne 'READY' -or [long]$beat.pid -eq $oldPid -or
                [long]$beat.observed_utc_epoch -lt ($since - 2)) { continue }
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$beat.pid)
            if (-not $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
            if ($owner.ReturnValue -eq 0 -and $owner.Sid -ceq $sid) { return $true }
        } catch { continue }
    }
    return $false
}
function StopOwner {
    NoOpenWork
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -ne 'Disabled') { Hold 'OWNER_TASK_STATE_UNKNOWN' }
    for ($i=0; $i -lt 5; $i++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $left = @(Workers)
    if ($left.Count -gt 4) { Hold 'WORKER_COUNT_UNEXPECTED' }
    foreach ($worker in $left) {
        $owner = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        $cmd = [string]$worker.CommandLine
        $entry = Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'
        $bridge = Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid -or
            $null -eq $worker.CreationDate -or
            ($cmd.IndexOf($entry,[StringComparison]::OrdinalIgnoreCase) -lt 0 -and
             $cmd.IndexOf($bridge,[StringComparison]::OrdinalIgnoreCase) -lt 0)) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $left) {
        NoOpenWork
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $owner = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $owner.ReturnValue -ne 0 -or $owner.Sid -cne $sid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(Workers).Count -ne 0) { Hold 'WORKERS_STILL_RUNNING' }
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($interactive) -or
    -not ([Security.Principal.WindowsIdentity]::GetCurrent().Name).Equals(
        $interactive,[StringComparison]::OrdinalIgnoreCase)) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
if (-not (Test-Path -LiteralPath $app -PathType Container)) { Hold 'OWNER_APP_MISSING' }
$task = CheckTask
$oldPid = 0L
if (Test-Path -LiteralPath $health -PathType Leaf) {
    try { $oldPid = [long](Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid }
    catch { $oldPid = 0L }
}

$backupRoot = Join-Path $root ('backups\owner-dual-' + [Guid]::NewGuid().ToString('N'))
$stage = Join-Path $backupRoot 'staged'
$previous = Join-Path $backupRoot 'previous'
[IO.Directory]::CreateDirectory($stage) | Out-Null
[IO.Directory]::CreateDirectory($previous) | Out-Null
$paths = [System.Collections.Generic.List[string]]::new()
$changed = [System.Collections.Generic.List[string]]::new()
$wasStopped = $false
$completed = $false
try {
    # Pinned exact Git source, downloaded before stopping the real Owner.
    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $target = Join-Path $stage $native
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        Invoke-WebRequest -Uri ('https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
            $source + '/' + $rel) -OutFile $target -ErrorAction Stop
        if ((Hash $target) -cne $pinned[$rel]) { Hold 'PINNED_BYTES_MISMATCH' }
        $paths.Add((Join-Path $app $native))
    }
    Write-Output 'OWNER_DUAL_STAGE=24_EXACT_SHA256_PASS'
    NoOpenWork
    $wasStopped = $true
    StopOwner
    NoOpenWork

    # Existing bytes are backed up individually, including an ABSENT marker
    # for a newly introduced module, before any destination is replaced.
    $before = [ordered]@{}
    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $target = Join-Path $app $native
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $target) -PathType Container)) {
            Hold 'DESTINATION_FOLDER_MISSING'
        }
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $saved = Join-Path $previous $native
            [IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
            [IO.File]::Copy($target,$saved,$false)
            if ((Hash $target) -cne (Hash $saved)) { Hold 'BACKUP_HASH_MISMATCH' }
            $before[$rel] = (Hash $saved)
        } elseif (Test-Path -LiteralPath $target) { Hold 'DESTINATION_NOT_FILE' }
        else { $before[$rel] = 'ABSENT' }
    }
    ([ordered]@{schema='TTV-OWNER-DUAL-ROLLBACK-V1';source_commit=$source;
        previous=$before} | ConvertTo-Json -Depth 5) |
        Set-Content -LiteralPath (Join-Path $backupRoot 'rollback-ledger.json') -Encoding utf8

    foreach ($rel in $pinned.Keys) {
        $native = $rel.Replace('/','\')
        $dest = Join-Path $app $native
        $new = Join-Path (Split-Path -Parent $dest) ('.owner-dual-' +
            [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy((Join-Path $stage $native),$new,$false)
        if ((Hash $new) -cne $pinned[$rel]) { Hold 'TEMP_HASH_MISMATCH' }
        if ($before[$rel] -ceq 'ABSENT') { [IO.File]::Move($new,$dest) }
        else {
            $displaced = Join-Path (Split-Path -Parent $dest) ('.owner-dual-before-' +
                [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Replace($new,$dest,$displaced)
        }
        $changed.Add($rel)
        if ((Hash $dest) -cne $pinned[$rel]) { Hold 'INSTALLED_HASH_MISMATCH' }
    }
    # Syntax smoke, without executing Owner imports or calling an AI provider.
    & py -3 -B -c 'import ast,sys,pathlib; [ast.parse(pathlib.Path(p).read_text(encoding="utf-8")) for p in sys.argv[1:]]' @paths
    if ($LASTEXITCODE -ne 0) { Hold 'OFFLINE_PYTHON_AST_FAILED' }
    if (-not (StartAndVerify $oldPid)) { Hold 'FRESH_OWNER_NOT_READY' }
    $completed = $true
    Write-Output 'OWNER_DUAL_INSTALL=24_FILES_INSTALLED_FRESH_OWNER_RUNNING'
    Write-Output ('OWNER_DUAL_SOURCE=' + $source)
    Write-Output ('OWNER_DUAL_ROLLBACK_BACKUP=' + $backupRoot)
    Write-Output 'OWNER_DUAL_P2_CHECKPOINTS=UNMODIFIED'
} catch {
    $failure = $_
    if ($changed.Count -ne 0) {
        try {
            StopOwner
            foreach ($rel in $changed) {
                $dest = Join-Path $app ($rel.Replace('/','\'))
                if (-not (Test-Path -LiteralPath $dest -PathType Leaf) -or
                    (Hash $dest) -cne $pinned[$rel]) { throw 'ROLLBACK_DESTINATION_DRIFT' }
                if ($before[$rel] -ceq 'ABSENT') { [IO.File]::Delete($dest) }
                else {
                    $saved = Join-Path $previous ($rel.Replace('/','\'))
                    if ((Hash $saved) -cne $before[$rel]) { throw 'ROLLBACK_BACKUP_DRIFT' }
                    $restore = Join-Path (Split-Path -Parent $dest) ('.owner-dual-restore-' +
                        [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Copy($saved,$restore,$false)
                    $displaced = Join-Path (Split-Path -Parent $dest) ('.owner-dual-failed-' +
                        [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Replace($restore,$dest,$displaced)
                }
            }
            Write-Output 'OWNER_DUAL_ROLLBACK=OLD_BYTES_RESTORED'
        } catch { Write-Output 'OWNER_DUAL_ROLLBACK=FAILED_PRIVATE_MANUAL_RECOVERY_REQUIRED'; throw }
    }
    if ($wasStopped) {
        if (-not (StartAndVerify $oldPid)) { Hold 'OLD_OWNER_RECOVERY_FAILED' }
        Write-Output 'OWNER_DUAL_OLD_OWNER=RECOVERED_RUNNING'
    }
    throw $failure
} finally {
    # Keep backup/ledger and failed staged evidence private for recovery.
    if (-not $completed) { Write-Output 'OWNER_DUAL_INSTALL=NOT_CONFIRMED' }
}
