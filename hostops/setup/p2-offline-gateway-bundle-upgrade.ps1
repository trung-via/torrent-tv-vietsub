# P2-F4: inspect and stage an exact, cohesive P2 module set on the Owner PC.
# Default is read-only. Install and restore require a separately quiesced
# Windows Owner; no task/process, provider, queue, secret or .inflight actions.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Install')][switch]$InstallOffline,
    [Parameter(ParameterSetName = 'Install', Mandatory = $true)]
    [string]$ExpectedInstalledInventorySha256,
    [Parameter(ParameterSetName = 'Restore')][switch]$RestoreOffline,
    [Parameter(ParameterSetName = 'Restore', Mandatory = $true)]
    [string]$BackupFolder
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# All transitive P2 imports in the automatic worker's translation path.
# Canonical UTF-8/LF hashes are pinned to the exact reviewed PR source.
$reviewed = [ordered]@{
    'automatic_lean120_worker.py' = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
    'assumed_source_handoff.py' = '2a3071202746d1026121dba521d8fd8f89e5d00e043400a248aa9e5cadb13615'
    'cue_pipeline.py' = 'caa28afbdfacf9acf2b6298fe295fc2802999a736cfceb856814e3c4b01c726f'
    'lean120_api.py' = 'bffeea72e9138a144d56dccafe2c41abe3dda801188e5cb20893967fb5224487'
    'translator_gateway.py' = 'b06c151cc4275a7793fdb7891d7859715e602a676a553ea89e6e242578190183'
    'progressive_handoff.py' = 'd17551aa8bd77e9da93c56f323a863b5f9555d1fc49add7eb9bbb3a617cfcc99'
    'translator_profile.json' = '43a7e2234e1c0a407f4e821ac4ddfb342daa2eb3d9166a5f9d0aec706ac62394'
    'lan_revision_feed.py' = '952e8b55e546b907839c2491c6de6311671889e1f824a1ad1723f043ce738bc4'
    'revision_delivery.py' = '2eefdb3e144eaa8e83148f31eb4b5b98d3dbd168bd659fd32f9bb3f830e1d0ca'
}
$sourceRoot = Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) 'poc\p2-aisub'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installedRoot = Join-Path $ownerRoot 'app\poc\p2-aisub'
$backupsRoot = Join-Path $ownerRoot 'backups\p2-gateway-f4'
$inbox = Join-Path $ownerRoot 'inbox'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'P2_F4_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_F4_WRONG_OWNER_ACCOUNT'
}

function Assert-Ordinary([string]$Path, [bool]$Directory) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -ne $Directory -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P2_F4_UNSAFE_FILE_OR_DIRECTORY'
    }
}
function Sha-Bytes([byte[]]$Bytes) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Canonical-Bytes([string]$Path) {
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $value = $utf8.GetString([IO.File]::ReadAllBytes($Path)) }
    catch { throw 'P2_F4_INVALID_UTF8_SOURCE_OR_INSTALLED' }
    if ($value.StartsWith([char]0xFEFF) -or
        $value.Replace("`r`n", "`n").Contains("`r")) {
        throw 'P2_F4_INVALID_LINE_ENDINGS_OR_BOM'
    }
    return ,($utf8.GetBytes($value.Replace("`r`n", "`n")))
}
function Write-New([string]$Path, [byte[]]$Bytes) {
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}
function Write-Json([string]$Path, [object]$Data) {
    $json = ConvertTo-Json -InputObject $Data -Depth 8 -Compress
    Write-New $Path ([Text.UTF8Encoding]::new($false).GetBytes($json))
}
function Installed-Inventory() {
    $items = [ordered]@{}
    foreach ($name in $reviewed.Keys) {
        $file = Join-Path $installedRoot $name
        if (Test-Path -LiteralPath $file) {
            Assert-Ordinary $file $false
            $items[$name] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        } else {
            $items[$name] = 'MISSING'
        }
    }
    return $items
}
function Inventory-Sha([System.Collections.IDictionary]$Inventory) {
    $lines = foreach ($name in $reviewed.Keys) { $name + '=' + $Inventory[$name] }
    return Sha-Bytes ([Text.Encoding]::UTF8.GetBytes(($lines -join "`n") + "`n"))
}
function Assert-Owner-Offline() {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    $workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe', 'python.exe', 'pythonw.exe') -and
        $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
    $pending = @()
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        $pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
    }
    $locks = @()
    $markers = @()
    if (Test-Path -LiteralPath $stateRoot -PathType Container) {
        $locks = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'active.lock' -Recurse)
        $markers = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse)
    }
    Write-Host ('P2_F4_TASK_STATE=' + [string]$task.State)
    Write-Host ('P2_F4_OWNER_PROCESS_COUNT=' + $workers.Count)
    Write-Host ('P2_F4_PENDING_EVENT_COUNT=' + $pending.Count)
    Write-Host ('P2_F4_ACTIVE_LOCK_COUNT=' + $locks.Count)
    Write-Host ('P2_F4_PRESERVED_INFLIGHT_COUNT=' + $markers.Count)
    if ([string]$task.State -cne 'Disabled' -or $workers.Count -ne 0 -or
        $pending.Count -ne 0 -or $locks.Count -ne 0 -or $markers.Count -gt 1) {
        throw 'P2_F4_OWNER_NOT_QUIESCENT'
    }
    $guards = Join-Path (Join-Path $PSScriptRoot '..\..') 'poc\p2-sub-discovery'
    . (Join-Path $guards 'owner-task-principal-identity.ps1')
    . (Join-Path $guards 'owner-task-action-identity.ps1')
    $launcher = Join-Path $ownerRoot 'start-owner-session-agent.ps1'
    if (-not (Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $identity.User.Value) -or
        -not (Get-TTVOwnerTaskActionState -Task $task `
            -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) `
            -ExpectedLauncher $launcher).Accepted) {
        throw 'P2_F4_TASK_IDENTITY_MISMATCH'
    }
}
function Assert-No-Tombstones() {
    if (Test-Path -LiteralPath $stateRoot -PathType Container) {
        $found = @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse |
            Where-Object { $_.Name -match '^batch-\d{4}\.(abandoned\.json|quarantined)$' })
        if ($found.Count -gt 0) { throw 'P2_F4_LEGACY_ROLLBACK_AFTER_QUARANTINE_REFUSED' }
    }
}

Assert-Ordinary $ownerRoot $true
Assert-Ordinary (Join-Path $ownerRoot 'app') $true
Assert-Ordinary (Join-Path $ownerRoot 'app\poc') $true
Assert-Ordinary $installedRoot $true
$sources = [ordered]@{}
foreach ($name in $reviewed.Keys) {
    $path = Join-Path $sourceRoot $name
    Assert-Ordinary $path $false
    [byte[]]$bytes = Canonical-Bytes $path
    if ((Sha-Bytes $bytes) -cne $reviewed[$name]) {
        throw ('P2_F4_SOURCE_PIN_MISMATCH_' + $name)
    }
    $sources[$name] = $bytes
}
$inventory = Installed-Inventory
$inventorySha = Inventory-Sha $inventory
Write-Host ('P2_F4_INSTALLED_INVENTORY_SHA256=' + $inventorySha)
$changed = 0
foreach ($name in $reviewed.Keys) {
    $path = Join-Path $installedRoot $name
    $status = if ($inventory[$name] -ceq 'MISSING') { 'MISSING' }
        elseif ((Sha-Bytes (Canonical-Bytes $path)) -ceq $reviewed[$name]) { 'MATCH' }
        else { 'MISMATCH' }
    if ($status -cne 'MATCH') { $changed++ }
    Write-Host ('P2_F4_MODULE=' + $name + ' STATUS=' + $status)
}
Write-Host ('P2_F4_FILES_TO_UPDATE=' + $changed)
if (-not $InstallOffline -and -not $RestoreOffline) {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    Write-Host ('P2_F4_INSPECT_TASK_STATE=' + [string]$task.State)
    Write-Host 'P2_F4_RESULT=INSPECT_ONLY_NO_CHANGES'
    return
}
Assert-Owner-Offline
if ($InstallOffline) {
    if ($ExpectedInstalledInventorySha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or
        $inventorySha -cne $ExpectedInstalledInventorySha256.ToLowerInvariant()) {
        throw 'P2_F4_EXPECTED_INVENTORY_HASH_MISMATCH'
    }
    if ($changed -eq 0) {
        Write-Host 'P2_F4_RESULT=ALREADY_INSTALLED_NO_CHANGES'
        return
    }
    # Do not overwrite an installed profile containing local custom fields
    # (including a credential). Old three-field models are expected.
    $profilePath = Join-Path $installedRoot 'translator_profile.json'
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        try {
            $profile = [IO.File]::ReadAllText($profilePath) | ConvertFrom-Json -ErrorAction Stop
            $fields = @($profile.PSObject.Properties.Name | Sort-Object)
            if (($fields -join ',') -cne 'model,provider,thinking_level') {
                throw 'P2_F4_UNEXPECTED_INSTALLED_PROFILE_FIELDS'
            }
        } catch { throw 'P2_F4_INSTALLED_PROFILE_SCHEMA_HOLD' }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ownerRoot 'backups'))) {
        New-Item -ItemType Directory -Path (Join-Path $ownerRoot 'backups') -ErrorAction Stop | Out-Null
    }
    if (-not (Test-Path -LiteralPath $backupsRoot)) {
        New-Item -ItemType Directory -Path $backupsRoot -ErrorAction Stop | Out-Null
    }
    Assert-Ordinary (Join-Path $ownerRoot 'backups') $true
    Assert-Ordinary $backupsRoot $true
    $folder = Join-Path $backupsRoot ('p2f4-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') +
        '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
    $records = @()
    foreach ($name in $reviewed.Keys) {
        $isPresent = $inventory[$name] -cne 'MISSING'
        $records += @{name = $name; original_sha256 = $inventory[$name];
            source_sha256 = $reviewed[$name]; present = $isPresent}
        if ($isPresent) {
            $original = [IO.File]::ReadAllBytes((Join-Path $installedRoot $name))
            if ((Sha-Bytes $original) -cne $inventory[$name]) {
                throw 'P2_F4_SOURCE_CHANGED_DURING_BACKUP'
            }
            $copy = Join-Path $folder ('original-' + $name)
            Write-New $copy $original
            if ((Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash.ToLowerInvariant() -cne $inventory[$name]) {
                throw 'P2_F4_BACKUP_HASH_MISMATCH'
            }
        }
    }
    Write-Json (Join-Path $folder 'manifest.json') @{
        schema = 'TTV-P2-F4-OFFLINE-BUNDLE-V1'; inventory_sha256 = $inventorySha;
        files = $records; created_utc = [DateTime]::UtcNow.ToString('o')
    }
    Write-Host ('P2_F4_BACKUP_FOLDER=' + $folder)
    # Stage all bytes in the same Owner volume before any target changes.
    foreach ($name in $reviewed.Keys) {
        $installedFile = Join-Path $installedRoot $name
        if ((Test-Path -LiteralPath $installedFile -PathType Leaf) -and
            (Sha-Bytes (Canonical-Bytes $installedFile)) -ceq $reviewed[$name]) { continue }
        Write-New (Join-Path $folder ('stage-' + $name)) $sources[$name]
    }
    Assert-Owner-Offline
    if ((Inventory-Sha (Installed-Inventory)) -cne $inventorySha) {
        throw 'P2_F4_INSTALLED_CHANGED_BEFORE_COMMIT'
    }
    foreach ($name in $reviewed.Keys) {
        $target = Join-Path $installedRoot $name
        $staged = Join-Path $folder ('stage-' + $name)
        if (-not (Test-Path -LiteralPath $staged)) { continue }
        try {
            if (Test-Path -LiteralPath $target -PathType Leaf) {
                [IO.File]::Replace($staged, $target, (Join-Path $folder ('displaced-' + $name)))
            } else {
                [IO.File]::Move($staged, $target)
            }
            if ((Sha-Bytes (Canonical-Bytes $target)) -cne $reviewed[$name]) {
                throw 'P2_F4_INSTALLED_REVIEWED_BYTES_MISMATCH'
            }
        } catch {
            Write-Host ('P2_F4_PARTIAL_INSTALL_BACKUP_FOLDER=' + $folder)
            throw 'P2_F4_INSTALL_INTERRUPTED_KEEP_OWNER_DISABLED_RESTORE_OFFLINE'
        }
    }
    Write-Host 'P2_F4_RESULT=BUNDLE_INSTALLED_VERIFIED_OWNER_STILL_DISABLED'
    Write-Host 'P2_F4_UNCERTAIN_BATCH=UNCHANGED'
    return
}

# Restore may recover a partially interrupted install, but cannot restore an
# old, no-retry-unaware worker after an .inflight has been quarantined.
Assert-No-Tombstones
$resolved = [IO.Path]::GetFullPath($BackupFolder)
if (-not [IO.Path]::GetDirectoryName($resolved).Equals(
    [IO.Path]::GetFullPath($backupsRoot), [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolved) -cnotmatch '^p2f4-\d{8}T\d{6}Z-[a-f0-9]{32}$') {
    throw 'P2_F4_BACKUP_OUTSIDE_OWNER_ROOT'
}
Assert-Ordinary $backupsRoot $true
Assert-Ordinary $resolved $true
$manifestPath = Join-Path $resolved 'manifest.json'
Assert-Ordinary $manifestPath $false
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($manifest.schema -cne 'TTV-P2-F4-OFFLINE-BUNDLE-V1' -or
    @($manifest.files).Count -ne $reviewed.Count) {
    throw 'P2_F4_INVALID_BACKUP_MANIFEST'
}
# Check every backup before changing any installed file.
foreach ($row in $manifest.files) {
    if (-not $reviewed.Contains([string]$row.name) -or
        [string]$row.source_sha256 -cne $reviewed[[string]$row.name] -or
        [string]$row.original_sha256 -cnotmatch '^([0-9a-f]{64}|MISSING)$') {
        throw 'P2_F4_INVALID_BACKUP_MANIFEST_ROW'
    }
    if ($row.present) {
        $backup = Join-Path $resolved ('original-' + [string]$row.name)
        Assert-Ordinary $backup $false
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            [string]$row.original_sha256) {
            throw 'P2_F4_BACKUP_CORRUPT'
        }
    }
    $target = Join-Path $installedRoot ([string]$row.name)
    if (Test-Path -LiteralPath $target) {
        Assert-Ordinary $target $false
        $sha = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        $canonical = Sha-Bytes (Canonical-Bytes $target)
        if ($sha -cne [string]$row.original_sha256 -and
            $canonical -cne [string]$row.source_sha256) {
            throw 'P2_F4_UNEXPECTED_INSTALLED_VERSION_BEFORE_RESTORE'
        }
    } elseif ($row.present) {
        throw 'P2_F4_ORIGINAL_FILE_MISSING_BEFORE_RESTORE'
    }
}
Assert-Owner-Offline
foreach ($row in $manifest.files) {
    $target = Join-Path $installedRoot ([string]$row.name)
    if ($row.present) {
        $originalSha = [string]$row.original_sha256
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $originalSha) {
            continue
        }
        $stage = Join-Path $resolved ('restore-' + [Guid]::NewGuid().ToString('N') + '.stage')
        Write-New $stage ([IO.File]::ReadAllBytes((Join-Path $resolved ('original-' + $row.name))))
        [IO.File]::Replace($stage, $target,
            (Join-Path $resolved ('restore-displaced-' + $row.name)))
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $originalSha) {
            throw 'P2_F4_RESTORE_HASH_MISMATCH_KEEP_OWNER_DISABLED'
        }
    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
        [IO.File]::Delete($target) # Exact known newly introduced file only.
    }
}
Write-Host 'P2_F4_RESULT=ORIGINAL_BUNDLE_RESTORED_OWNER_STILL_DISABLED'
Write-Host 'P2_F4_UNCERTAIN_BATCH=UNCHANGED'
