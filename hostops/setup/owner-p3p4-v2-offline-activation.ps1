# Owner-only guarded offline V1->V2 overlay. NEVER stops/starts the task.
# Modes: inspect (default), -Backup, -ApplyOffline with -BackupFolder.
# All actions require exact interactive Windows Owner + original task identity.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Backup')][switch]$Backup,
    [Parameter(ParameterSetName = 'Apply')][switch]$ApplyOffline,
    [Parameter(ParameterSetName = 'Apply', Mandatory = $true)][string]$BackupFolder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Hold([string]$reason) {
    Write-Host ('TTV_OWNER_V2_OFFLINE=HOLD_' + $reason)
    throw 'TTV_OWNER_V2_OFFLINE_PRECONDITION_FAILED'
}
function SafeItem([string]$path, [bool]$directory) {
    if (-not (Test-Path -LiteralPath $path)) { Hold 'REQUIRED_PATH_MISSING' }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.PSIsContainer -ne $directory -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'REPARSE_OR_TYPE_CONFLICT'
    }
}
function ExactHash([string]$path) {
    # The *installed/staged* files are checked as raw canonical LF bytes.
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function V1CanonicalHash([string]$path) {
    # The older Windows installer copied directly from the local checkout.
    # A legitimate V1 installation may therefore be CRLF while the reviewed
    # Git blob is LF; compare canonical source, but BACK UP original bytes.
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $source = $utf8.GetString([IO.File]::ReadAllBytes($path)) }
    catch { Hold 'V1_SOURCE_ENCODING_INVALID' }
    if ($source.StartsWith([char]0xFEFF) -or
        $source.Replace("`r`n", "`n").Contains("`r")) {
        Hold 'V1_SOURCE_LINE_ENDINGS_INVALID'
    }
    $bytes = $utf8.GetBytes($source.Replace("`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function InvokeTTVAtomicReplacement([string]$source, [string]$destination, [string]$backupKind) {
    # File.Replace's third argument must be a real, nonempty path on the
    # Owner's PowerShell/.NET runtime. A $null backup failed with
    # ArgumentException(path) on the supervised Windows V1->V2 attempt.
    if ([string]::IsNullOrWhiteSpace($source) -or
        [string]::IsNullOrWhiteSpace($destination) -or
        $backupKind -cnotin @('v2-original', 'v1-displaced')) {
        throw 'TTV_ATOMIC_REPLACE_ARGUMENT_INVALID'
    }
    $src = [IO.Path]::GetFullPath($source)
    $dst = [IO.Path]::GetFullPath($destination)
    $sourceDirectory = [IO.Path]::GetDirectoryName($src)
    $destinationDirectory = [IO.Path]::GetDirectoryName($dst)
    if (-not $sourceDirectory.Equals($destinationDirectory, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.File]::Exists($src) -or -not [IO.File]::Exists($dst)) {
        throw 'TTV_ATOMIC_REPLACE_PRECONDITION_FAILED'
    }
    $previous = Join-Path $destinationDirectory ('.' + $backupKind + '-' +
                [Guid]::NewGuid().ToString('N') + '.tmp')
    if (Test-Path -LiteralPath $previous) { throw 'TTV_ATOMIC_REPLACE_BACKUP_CONFLICT' }
    [IO.File]::Replace($src, $dst, $previous)
    # This private backup stays available as forensic evidence. The verified
    # V1 recovery directory is independent and never overwritten here.
    return $previous
}
function NoOpenWork([string]$root) {
    $inbox = Join-Path $root 'inbox'
    SafeItem $inbox $true
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json' -ErrorAction Stop)
    $state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    $inflight = @()
    if (Test-Path -LiteralPath $state) {
        SafeItem $state $true
        $inflight = @(Get-ChildItem -LiteralPath $state -File -Filter '*.inflight' -Recurse -ErrorAction Stop)
    }
    Write-Host ('TTV_OWNER_V2_PENDING_EVENTS=' + $pending.Count)
    Write-Host ('TTV_OWNER_V2_PROVIDER_INFLIGHT=' + $inflight.Count)
    if ($pending.Count -ne 0 -or $inflight.Count -ne 0) {
        Hold 'PENDING_OR_UNCERTAIN_JOB'
    }
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    Hold 'OWNER_INTERACTIVE_SESSION_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
    Hold 'SERVICE_ACCOUNT'
}
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    Hold 'WRONG_WINDOWS_OWNER'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$stage = Join-Path $root 'staged-releases\p3p4-ingress-v2-f7fdb024'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
foreach ($path in @($root, $app, $stage)) { SafeItem $path $true }
SafeItem $launcher $false

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$guards = Join-Path $repo 'poc\p2-sub-discovery'
. (Join-Path $guards 'owner-task-principal-identity.ps1')
. (Join-Path $guards 'owner-task-action-identity.ps1')
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
if (-not (Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $identity.User.Value) -or
    -not (Get-TTVOwnerTaskActionState -Task $task `
        -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) `
        -ExpectedLauncher $launcher).Accepted) {
    Hold 'TASK_IDENTITY_MISMATCH'
}
Write-Host 'TTV_OWNER_V2_TASK_IDENTITY=VERIFIED'
Write-Host ('TTV_OWNER_V2_TASK_STATE=' + [string]$task.State)

# Baseline is the exact V1 source from Draft #164; V2 is exact Draft #165.
$baseline = [ordered]@{
    'owner_p3_p4_diagnostics.py' = 'bfcea3975b92a34e6378785919ba5d079865933f9117476f04f39bf1bc8f0f69'
    'p3_owner_state_wiring.py' = '5129cea28781ab9f0e6aa22895769f1eb7074ce0703fc34c706dc9145432e740'
    'p3_p4_shared_https_route.py' = '65c0f5fd8c909091230bf69be954cdbab3b604a8f6a4fe60053a565341157189'
}
$v2 = [ordered]@{
    'owner_p3_p4_diagnostics.py' = 'a30bc451c4d8d0c38d9899773c9c33a9c0e0ba7e0bf98cd0f351c2f873877886'
    'p3_owner_state_wiring.py' = '4bbafda8444413a2d7e907f10aa2cce904be03e8bcb1075f39e01fa4bd60e73a'
    'p3_p4_shared_https_route.py' = 'ab9deb57a7d568c1a5141a50a18afe5831577242d0e8e7723f569dec4ef27d2e'
    'p3_ingress_telemetry.py' = '69f6711496575dd61ba82d3260d39726232b761bc395e22c10435d917c405b69'
}
foreach ($name in $v2.Keys) {
    $src = Join-Path $stage $name
    SafeItem $src $false
    if ((ExactHash $src) -cne $v2[$name]) { Hold 'STAGED_BYTES_MISMATCH' }
}
Write-Host 'TTV_OWNER_V2_STAGED_BYTES=VERIFIED'

if (-not $Backup -and -not $ApplyOffline) {
    Write-Host 'TTV_OWNER_V2_OFFLINE=READ_ONLY_INSPECT_PASS'
    Write-Host 'TTV_OWNER_V2_RUNTIME=UNCHANGED'
    exit 0
}

if ($Backup) {
    foreach ($name in $baseline.Keys) {
        $src = Join-Path $app $name
        SafeItem $src $false
        if ((V1CanonicalHash $src) -cne $baseline[$name]) { Hold 'INSTALLED_V1_BASELINE_MISMATCH' }
    }
    if (Test-Path -LiteralPath (Join-Path $app 'p3_ingress_telemetry.py')) {
        Hold 'UNEXPECTED_INSTALLED_TELEMETRY'
    }
    $recover = Join-Path $root 'recovery'
    if (-not (Test-Path -LiteralPath $recover)) {
        New-Item -ItemType Directory -Path $recover -ErrorAction Stop | Out-Null
    }
    SafeItem $recover $true
    $folder = Join-Path $recover ('p3p4-v1-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
    foreach ($name in $baseline.Keys) {
        $dest = Join-Path $folder $name
        $bytes = [IO.File]::ReadAllBytes((Join-Path $app $name))
        $stream = [IO.File]::Open($dest, [IO.FileMode]::CreateNew,
                                  [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        if ((V1CanonicalHash $dest) -cne $baseline[$name]) { Hold 'BACKUP_HASH_MISMATCH' }
    }
    # Print only a non-sensitive backup token, not private absolute paths.
    Write-Host ('TTV_OWNER_V2_BACKUP_ID=' + (Split-Path $folder -Leaf))
    Write-Host 'TTV_OWNER_V2_BACKUP=VERIFIED_PRIVATE'
    Write-Host 'TTV_OWNER_V2_RUNTIME=UNCHANGED'
    exit 0
}

# Offline install ONLY. The owner must have DISABLED and then stopped the
# task in a separately authorized maintenance window. Merely seeing Ready is
# not a maintenance lock: the Scheduler could restart V1 during file updates.
function AssertMaintenanceLock {
    $current = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    if ([string]$current.State -cne 'Disabled') { Hold 'TASK_MUST_BE_DISABLED_AND_STOPPED' }
}
AssertMaintenanceLock
$health = Join-Path $root 'agent-health.json'
SafeItem $health $false
if ((Get-Item -LiteralPath $health).Length -gt 512) { Hold 'HEALTH_INVALID' }
try { $doc = Get-Content -LiteralPath $health -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
catch { Hold 'HEALTH_INVALID' }
if ($doc.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
    $doc.pid -isnot [int] -and $doc.pid -isnot [long] -or
    $doc.pid -le 0) { Hold 'HEALTH_PID_INVALID' }
function AssertNoOwnerProcess {
    # A stale V1 heartbeat cannot exclude a separately launched Owner worker.
    # Fail closed on ambiguous Python processes rather than risking a live patch.
    if ($null -ne (Get-Process -Id $doc.pid -ErrorAction SilentlyContinue)) {
        Hold 'OWNER_PID_STILL_ALIVE'
    }
    $pythonProcesses = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
    foreach ($process in $pythonProcesses) {
        if ([string]::IsNullOrWhiteSpace([string]$process.CommandLine)) {
            Hold 'UNINSPECTABLE_PYTHON_PROCESS'
        }
        if ([string]$process.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') {
            Hold 'OWNER_PROCESS_STILL_ALIVE'
        }
    }
}
AssertNoOwnerProcess
NoOpenWork $root

$recover = Join-Path $root 'recovery'
SafeItem $recover $true
$expectedPrefix = [IO.Path]::GetFullPath($recover).TrimEnd('\') + '\'
$resolved = [IO.Path]::GetFullPath($BackupFolder)
if (-not $resolved.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path $resolved -Leaf) -cnotmatch '^p3p4-v1-[0-9a-f]{32}$') {
    Hold 'BACKUP_PATH_INVALID'
}
SafeItem $resolved $true
foreach ($name in $baseline.Keys) {
    $old = Join-Path $app $name
    $saved = Join-Path $resolved $name
    SafeItem $old $false
    SafeItem $saved $false
    if ((V1CanonicalHash $old) -cne $baseline[$name] -or
        (V1CanonicalHash $saved) -cne $baseline[$name]) {
        Hold 'BASELINE_OR_BACKUP_MISMATCH'
    }
}
if (Test-Path -LiteralPath (Join-Path $app 'p3_ingress_telemetry.py')) {
    Hold 'TELEMETRY_FILE_ALREADY_INSTALLED'
}
Write-Host 'TTV_OWNER_V2_OFFLINE_PREPARE=VERIFIED_DISABLED_STOPPED_AND_BACKED_UP'

# Check the maintenance lock again immediately before the first byte change.
AssertMaintenanceLock
AssertNoOwnerProcess
NoOpenWork $root
$attempted = @()
$applyStep = 'PREPARE_V2_TEMP'
try {
    foreach ($name in $v2.Keys) {
        AssertMaintenanceLock
        AssertNoOwnerProcess
        $dest = Join-Path $app $name
        $temp = Join-Path $app ('.v2-update-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllBytes($temp, [IO.File]::ReadAllBytes((Join-Path $stage $name)))
        if ((ExactHash $temp) -cne $v2[$name]) { Hold 'TEMP_FILE_HASH_MISMATCH' }
        # Record the attempted destination BEFORE the file operation: a
        # mid-operation exception must not hide a partially changed module.
        $attempted += $name
        if (Test-Path -LiteralPath $dest) {
            $applyStep = 'REPLACE_V2_MODULE'
            InvokeTTVAtomicReplacement $temp $dest 'v2-original' | Out-Null
        } else {
            $applyStep = 'CREATE_V2_TELEMETRY'
            [IO.File]::Move($temp, $dest)
        }
    }
    $applyStep = 'VERIFY_INSTALLED_V2'
    foreach ($name in $v2.Keys) {
        if ((ExactHash (Join-Path $app $name)) -cne $v2[$name]) {
            Hold 'POSTINSTALL_HASH_MISMATCH'
        }
    }
} catch {
    Write-Host ('TTV_OWNER_V2_APPLY_FAILED_STEP=' + $applyStep)
    try {
        # Do not modify files during recovery if the maintenance lock was
        # lost. Any recovery exception is a manual-recovery HOLD, never PASS.
        AssertMaintenanceLock
        AssertNoOwnerProcess
        foreach ($name in $attempted) {
            AssertMaintenanceLock
            AssertNoOwnerProcess
            $dest = Join-Path $app $name
            if ($baseline.Contains($name)) {
                $saved = Join-Path $resolved $name
                SafeItem $saved $false
                if ((V1CanonicalHash $saved) -cne $baseline[$name]) {
                    Hold 'RECOVERY_BACKUP_HASH_MISMATCH'
                }
                $temporary = Join-Path $app ('.v1-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy($saved, $temporary)
                if (Test-Path -LiteralPath $dest) {
                    InvokeTTVAtomicReplacement $temporary $dest 'v1-displaced' | Out-Null
                } else {
                    [IO.File]::Move($temporary, $dest)
                }
            } elseif (Test-Path -LiteralPath $dest) {
                if ((ExactHash $dest) -cne $v2[$name]) {
                    Hold 'UNRECOGNIZED_TELEMETRY_STATE'
                }
                [IO.File]::Delete($dest) # Only exact V2 telemetry added by this attempt.
            }
        }
        foreach ($name in $baseline.Keys) {
            if ((V1CanonicalHash (Join-Path $app $name)) -cne $baseline[$name]) {
                Hold 'ROLLBACK_BASELINE_MISMATCH'
            }
        }
        if (Test-Path -LiteralPath (Join-Path $app 'p3_ingress_telemetry.py')) {
            Hold 'ROLLBACK_TELEMETRY_REMAINS'
        }
    } catch {
        Hold 'ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY'
    }
    Hold 'APPLY_FAILED_ROLLBACK_VERIFIED'
}
Write-Host 'TTV_OWNER_V2_OFFLINE=INSTALLED_HASH_VERIFIED'
Write-Host 'TTV_OWNER_V2_RESTART=NOT_PERFORMED'
Write-Host 'TTV_OWNER_V2_RUNTIME=NOT_YET_LOADED'
