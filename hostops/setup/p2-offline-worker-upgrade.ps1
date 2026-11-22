# P2-F3: Owner-private, reversible upgrade of one LEAN120 Python worker.
# Inspect by default. No task toggling, process control, provider call, state
# marker move, secret access, checkout operation or other module replacement.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Install')][switch]$InstallOffline,
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [string]$ExpectedInstalledSha256,
    [Parameter(ParameterSetName = 'Restore')][switch]$RestoreOffline,
    [Parameter(ParameterSetName = 'Restore', Mandatory = $true)]
    [string]$BackupFolder
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$newSha = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$backupRoot = Join-Path $ownerRoot 'backups\p2-worker-f3'
$destination = Join-Path $ownerRoot 'app\poc\p2-aisub\automatic_lean120_worker.py'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source = Join-Path $repo 'poc\p2-aisub\automatic_lean120_worker.py'
$inbox = Join-Path $ownerRoot 'inbox'
$state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'P2_F3_INTERACTIVE_WINDOWS_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_F3_WRONG_WINDOWS_OWNER'
}

function Assert-LocalRegular([string]$Path, [bool]$Directory) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -ne $Directory -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P2_F3_NONREGULAR_OR_REPARSE_PATH'
    }
}
function Get-ShaBytes([byte[]]$Bytes) {
    $digest = [Security.Cryptography.SHA256]::HashData($Bytes)
    return [BitConverter]::ToString($digest).Replace('-', '').ToLowerInvariant()
}
function Read-CanonicalWorker([string]$Path) {
    # Git on Windows may materialize CRLF. The installed reviewed file is
    # canonical UTF-8/LF and byte-pinned to the Git source, not checkout EOL.
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $value = $utf8.GetString([IO.File]::ReadAllBytes($Path)) }
    catch { throw 'P2_F3_SOURCE_UTF8_INVALID' }
    if ($value.StartsWith([char]0xFEFF) -or
        $value.Replace("`r`n", "`n").Contains("`r")) {
        throw 'P2_F3_SOURCE_LINE_ENDINGS_INVALID'
    }
    return ,($utf8.GetBytes($value.Replace("`r`n", "`n")))
}
function Write-NewBytes([string]$Path, [byte[]]$Bytes) {
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
}
function Write-NewJson([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 6 -Compress
    Write-NewBytes $Path ([Text.UTF8Encoding]::new($false).GetBytes($json))
}
function Assert-WorkerDependencies() {
    # A worker-only swap is safe only when its existing runtime imports and
    # selected CLI profile already match the reviewed branch. Older Owner
    # installations must instead receive a separately reviewed P2 bundle.
    foreach ($name in @('assumed_source_handoff.py', 'cue_pipeline.py',
            'lean120_api.py', 'translator_gateway.py',
            'progressive_handoff.py', 'translator_profile.json')) {
        $expected = Join-Path $repo ('poc\p2-aisub\' + $name)
        $actual = Join-Path $destinationDir $name
        Assert-LocalRegular $expected $false
        Assert-LocalRegular $actual $false
        [byte[]]$expectedBytes = Read-CanonicalWorker $expected
        [byte[]]$installedBytes = Read-CanonicalWorker $actual
        if ((Get-ShaBytes $expectedBytes) -cne (Get-ShaBytes $installedBytes)) {
            Write-Host ('P2_F3_DEPENDENCY_MISMATCH=' + $name)
            throw 'P2_F3_INSTALLED_GATEWAY_DEPENDENCIES_NOT_READY'
        }
    }
    Write-Host 'P2_F3_GATEWAY_DEPENDENCIES=REVIEWED_MATCH'
}
function Assert-Offline() {
    # Every install/restore call is readmitted just before replacing bytes.
    $currentTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    $currentProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe', 'python.exe', 'pythonw.exe') -and
        $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
    $currentPending = @()
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        $currentPending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
    }
    $currentLocks = @()
    $currentMarkers = @()
    if (Test-Path -LiteralPath $state -PathType Container) {
        $currentLocks = @(Get-ChildItem -LiteralPath $state -File -Filter 'active.lock' -Recurse)
        $currentMarkers = @(Get-ChildItem -LiteralPath $state -File -Filter '*.inflight' -Recurse)
    }
    Write-Host ('P2_F3_TASK_STATE=' + [string]$currentTask.State)
    Write-Host ('P2_F3_OWNER_PROCESS_COUNT=' + $currentProcesses.Count)
    Write-Host ('P2_F3_PENDING_EVENT_COUNT=' + $currentPending.Count)
    Write-Host ('P2_F3_ACTIVE_LOCK_COUNT=' + $currentLocks.Count)
    Write-Host ('P2_F3_INFLIGHT_PRESERVED_COUNT=' + $currentMarkers.Count)
    if ([string]$currentTask.State -cne 'Disabled' -or
        $currentProcesses.Count -ne 0 -or $currentPending.Count -ne 0 -or
        $currentLocks.Count -ne 0 -or $currentMarkers.Count -gt 1) {
        throw 'P2_F3_OWNER_NOT_QUIESCENT'
    }
    $guards = Join-Path $repo 'poc\p2-sub-discovery'
    . (Join-Path $guards 'owner-task-principal-identity.ps1')
    . (Join-Path $guards 'owner-task-action-identity.ps1')
    $launcher = Join-Path $ownerRoot 'start-owner-session-agent.ps1'
    if (-not (Test-TTVOwnerTaskPrincipal -Principal $currentTask.Principal `
        -ExpectedSid $identity.User.Value) -or
        -not (Get-TTVOwnerTaskActionState -Task $currentTask `
            -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) `
            -ExpectedLauncher $launcher).Accepted) {
        throw 'P2_F3_TASK_IDENTITY_MISMATCH'
    }
}

Assert-LocalRegular $ownerRoot $true
Assert-LocalRegular (Join-Path $ownerRoot 'app') $true
Assert-LocalRegular (Join-Path $ownerRoot 'app\poc') $true
Assert-LocalRegular (Join-Path $ownerRoot 'app\poc\p2-aisub') $true
Assert-LocalRegular $destination $false
Assert-LocalRegular $source $false
[byte[]]$reviewed = Read-CanonicalWorker $source
if ((Get-ShaBytes $reviewed) -cne $newSha) { throw 'P2_F3_REVIEWED_WORKER_HASH_MISMATCH' }
$currentSha = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
$destinationDir = [IO.Path]::GetDirectoryName($destination)
Write-Host ('P2_F3_REVIEWED_WORKER_SHA256=' + $newSha)
Write-Host ('P2_F3_INSTALLED_WORKER_SHA256=' + $currentSha)

if (-not $InstallOffline -and -not $RestoreOffline) {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    Write-Host ('P2_F3_INSPECT_TASK_STATE=' + [string]$task.State)
    Write-Host ('P2_F3_INSPECT_INSTALLED_MATCH=' + ($currentSha -ceq $newSha))
    try {
        Assert-WorkerDependencies
        Write-Host 'P2_F3_INSPECT_GATEWAY_COMPATIBILITY=PASS'
    } catch {
        Write-Host 'P2_F3_INSPECT_GATEWAY_COMPATIBILITY=HOLD'
    }
    Write-Host 'P2_F3_RESULT=INSPECT_ONLY_NO_CHANGES'
    return
}

Assert-Offline
if ($InstallOffline) {
    if ($ExpectedInstalledSha256 -cnotmatch '^[a-fA-F0-9]{64}$' -or
        $currentSha -cne $ExpectedInstalledSha256.ToLowerInvariant()) {
        throw 'P2_F3_EXPECTED_INSTALLED_HASH_REQUIRED'
    }
    if ($currentSha -ceq $newSha) {
        Write-Host 'P2_F3_RESULT=ALREADY_INSTALLED_NO_CHANGES'
        return
    }
    Assert-WorkerDependencies
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force -ErrorAction Stop | Out-Null
    }
    Assert-LocalRegular (Join-Path $ownerRoot 'backups') $true
    Assert-LocalRegular $backupRoot $true
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $backupDir = Join-Path $backupRoot ('p2f3-' + $stamp + '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop | Out-Null
    [byte[]]$before = [IO.File]::ReadAllBytes($destination)
    if ((Get-ShaBytes $before) -cne $currentSha) { throw 'P2_F3_INSTALLED_CHANGED_BEFORE_BACKUP' }
    $backupFile = Join-Path $backupDir 'original-worker.py'
    Write-NewBytes $backupFile $before
    if ((Get-FileHash -LiteralPath $backupFile -Algorithm SHA256).Hash.ToLowerInvariant() -cne $currentSha) {
        throw 'P2_F3_BACKUP_VERIFY_FAILED'
    }
    Write-NewJson (Join-Path $backupDir 'manifest.json') @{
        schema = 'TTV-P2-F3-OFFLINE-UPGRADE-V1'
        previous_sha256 = $currentSha
        reviewed_sha256 = $newSha
        backup_name = 'original-worker.py'
        created_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-Host ('P2_F3_BACKUP_FOLDER=' + $backupDir)
    Assert-Offline
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $currentSha) {
        throw 'P2_F3_INSTALLED_CHANGED_BEFORE_REPLACE'
    }
    $staged = Join-Path $destinationDir ('.p2f3-' + [Guid]::NewGuid().ToString('N') + '.stage')
    Write-NewBytes $staged $reviewed
    if ((Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newSha) {
        throw 'P2_F3_STAGED_BYTES_MISMATCH'
    }
    [IO.File]::Replace($staged, $destination, (Join-Path $backupDir 'displaced-worker.py'))
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newSha) {
        throw 'P2_F3_INSTALLED_HASH_MISMATCH_BACKUP_RETAINED'
    }
    Write-NewJson (Join-Path $backupDir 'installed.json') @{
        schema = 'TTV-P2-F3-INSTALLED-V1'
        installed_sha256 = $newSha
        backup_name = 'original-worker.py'
    }
    Write-Host 'P2_F3_RESULT=INSTALLED_HASH_VERIFIED_OWNER_STILL_DISABLED'
    Write-Host 'P2_F3_UNCERTAIN_BATCH=UNCHANGED'
    return
}

# Explicit rollback of this upgrade only, from a directly parented owner-local
# backup with an exact manifest and independently verified original bytes.
$resolved = [IO.Path]::GetFullPath($BackupFolder)
$backupParent = [IO.Path]::GetDirectoryName($resolved)
if (-not $backupParent.Equals(
    [IO.Path]::GetFullPath($backupRoot), [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolved) -cnotmatch '^p2f3-\d{8}T\d{6}Z-[a-f0-9]{32}$') {
    throw 'P2_F3_BACKUP_FOLDER_OUTSIDE_OWNER_ROOT'
}
Assert-LocalRegular $backupRoot $true
Assert-LocalRegular $resolved $true
$manifestFile = Join-Path $resolved 'manifest.json'
$backupFile = Join-Path $resolved 'original-worker.py'
Assert-LocalRegular $manifestFile $false
Assert-LocalRegular $backupFile $false
$manifest = Get-Content -LiteralPath $manifestFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ($manifest.schema -cne 'TTV-P2-F3-OFFLINE-UPGRADE-V1' -or
    $manifest.reviewed_sha256 -cne $newSha -or
    $manifest.backup_name -cne 'original-worker.py' -or
    [string]$manifest.previous_sha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'P2_F3_BACKUP_MANIFEST_INVALID'
}
[byte[]]$original = [IO.File]::ReadAllBytes($backupFile)
if ((Get-ShaBytes $original) -cne $manifest.previous_sha256) {
    throw 'P2_F3_ORIGINAL_BACKUP_BYTES_MISMATCH'
}
if ($currentSha -cne $newSha) { throw 'P2_F3_ROLLBACK_EXPECTED_CURRENT_VERSION_REQUIRED' }
# A restored legacy worker might ignore an already acknowledged tombstone.
# Never permit rollback after the first irreversible semantic reconciliation.
if (Test-Path -LiteralPath $state -PathType Container) {
    $noRetryEvidence = @(Get-ChildItem -LiteralPath $state -File -Recurse |
        Where-Object { $_.Name -match '^batch-\d{4}\.(abandoned\.json|quarantined)$' })
    if ($noRetryEvidence.Count -ne 0) { throw 'P2_F3_ROLLBACK_AFTER_QUARANTINE_REFUSED' }
}
Assert-Offline
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $newSha) {
    throw 'P2_F3_INSTALLED_CHANGED_BEFORE_ROLLBACK'
}
$staged = Join-Path $destinationDir ('.p2f3-rollback-' + [Guid]::NewGuid().ToString('N') + '.stage')
Write-NewBytes $staged $original
[IO.File]::Replace($staged, $destination,
    (Join-Path $resolved ('rollback-displaced-' + [Guid]::NewGuid().ToString('N') + '.py')))
if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne
    $manifest.previous_sha256) {
    throw 'P2_F3_ROLLBACK_HASH_MISMATCH'
}
Write-Host 'P2_F3_RESULT=ROLLBACK_HASH_VERIFIED_OWNER_STILL_DISABLED'
Write-Host 'P2_F3_UNCERTAIN_BATCH=UNCHANGED'
