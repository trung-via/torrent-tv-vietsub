# Offline Owner-only R2 install from a previously verified, private STAGE_ONLY
# release. Inspect is the default. This script never stops/starts Owner,
# calls a provider/TV, alters P2 state, or authorizes an old inflight replay.
[CmdletBinding()]
param([switch]$ApplyOffline)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Hold([string]$reason) {
    Write-Output ('OWNER_R2_OFFLINE=HOLD_' + $reason)
    throw 'OWNER_R2_OFFLINE_HOLD'
}
function Directory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_REPARSE'
    }
}
function File([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_REPARSE'
    }
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function AtomicReplace([string]$source,[string]$destination,[string]$tag) {
    if (-not [IO.Path]::GetDirectoryName($source).Equals(
            [IO.Path]::GetDirectoryName($destination),[StringComparison]::OrdinalIgnoreCase)) {
        Hold 'REPLACE_NOT_IN_SAME_DIRECTORY'
    }
    $displaced = Join-Path ([IO.Path]::GetDirectoryName($destination)) (
        '.' + $tag + '-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::Replace($source,$destination,$displaced)
}
function AssertOwnerStopped {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
    if ([string]$task.State -cne 'Disabled') { Hold 'OWNER_TASK_NOT_DISABLED' }
    $workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
    if ($workers.Count -ne 0) { Hold 'OWNER_PROCESS_STILL_RUNNING' }
}
function AssertNoOpenP2Work([string]$ownerRoot) {
    $inbox = Join-Path $ownerRoot 'inbox'
    Directory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0) {
        Hold 'PENDING_OWNER_EVENTS'
    }
    $state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    if (Test-Path -LiteralPath $state) {
        Directory $state
        if (@(Get-ChildItem -LiteralPath $state -File -Recurse -Filter 'batch-*.inflight').Count -ne 0) {
            Hold 'P2_UNCERTAIN_INFLIGHT'
        }
        if (@(Get-ChildItem -LiteralPath $state -File -Recurse -Filter 'active.lock').Count -ne 0) {
            Hold 'P2_ACTIVE_LOCK'
        }
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$interactive = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($interactive) -or
    -not $identity.Name.Equals($interactive,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$stage = Join-Path $root 'staged-releases\owner-r2-rolling-175-90b8c18f343f'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
foreach ($dir in @($root,$app,$stage)) { Directory $dir }
File $launcher
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
$ownerSid = [string]$task.Principal.UserId
if ($ownerSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $ownerSid = ([Security.Principal.NTAccount]::new($ownerSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($ownerSid -cne $identity.User.Value -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    -not [IO.Path]::GetFileName([string]$task.Actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    Hold 'ORIGINAL_OWNER_TASK_IDENTITY_DRIFT'
}

# Exact raw-Git bytes pinned by the already successful Stage receipt.
# No manifest-, filename- or destination-controlled code execution.
$files = [ordered]@{
    'poc/p2-aisub/paired_activation.py' = 'c8714306f96cd4fdbfa748b01795991d045f108476aea830b366486e68012ca8'
    'poc/p2-sub-discovery/owner_hostops_snapshot_v3.py' = '2d3c3b3417f11b3e426c5060ab6a97ec22f907be352b7b74ae18d3a0c215d0a9'
    'poc/p2-sub-discovery/owner_p3_p4_entrypoint.py' = '6704086141e0823b5024661ee0183542ac6445da0a04939ca79f4cf5189f3b7b'
    'poc/p2-sub-discovery/owner_p3_p4_policy_r0.py' = 'f52e5ce0fd41fd6bbd593d9dd11265aaf0f8334d85dd99f0ebb075238d918121'
    'poc/p2-sub-discovery/owner_p3_p4_runtime.py' = 'b03a3b8fb204dabc431bca3fdcec2e62b5462d11fa9c541d16489dbec2b6efd2'
    'poc/p2-sub-discovery/owner_r2_progressive_registry.py' = '8946dfd48e63d318cd9bb327d786411a10f01552f073d62187939f4658cd9cc7'
    'poc/p2-sub-discovery/owner_r2_progressive_worker.py' = 'f024ac97d6989876975a2c32bffdf3d0dccf51bbbc964b4e0bd29e4e4e3e8457'
    'poc/p2-sub-discovery/owner_r2_verified_processor.py' = 'f8a4aec4ed350488e92821b6400eb40782d9603141c07099b023abfd1effff13'
    'poc/p2-sub-discovery/owner_session_bridge.py' = '6a8af62e4ff33806b7fd3c2deb66df08283302d3441c51edd65da02d1633ce31'
    'poc/p2-sub-discovery/p3_owner_current_redmi.py' = '42a15e926d515c6779e54cbef8bff45a9e46d70467ba60b7189d3500b637f98e'
    'poc/p2-sub-discovery/p3_owner_state_wiring_r0.py' = '149a914127d3aff5636ecb23d7d5ae1128e28a5b219c868098663bc0510d734b'
    'poc/p2-sub-discovery/p3_owner_state_wiring_r2.py' = '89ee220d2526a11a4baead89839c27df3601fb299923bf8ed966bc3833e1e596'
    'poc/p2-sub-discovery/p3_p4_shared_https_route_r0.py' = '45be5172e6e360af583f7eabc0df13d36a3e9f1fb92ccc17ca2777a14b44de91'
    'poc/p2-sub-discovery/verified_v3_processor.py' = 'e20d3d0aa8176692c6dedcfa107a71f384cfdb11ca734e95d8b857940a2956d3'
}
foreach ($rel in $files.Keys) {
    $relative = $rel.Replace('/','\')
    $source = Join-Path $stage $relative
    $destination = Join-Path $app $relative
    File $source
    Directory (Split-Path -Parent $destination)
    if ((Hash $source) -cne $files[$rel]) { Hold 'STAGED_SOURCE_BYTES_DRIFT' }
    if (Test-Path -LiteralPath $destination) { File $destination }
}
Write-Output 'OWNER_R2_STAGE_FILES=14_HASH_VERIFIED'
Write-Output ('OWNER_R2_OWNER_TASK=' + [string]$task.State)
if (-not $ApplyOffline) {
    Write-Output 'OWNER_R2_OFFLINE=READ_ONLY_INSPECT_PASS'
    Write-Output 'OWNER_R2_INSTALLED=NOT_CHANGED'
    return
}

# No task/process mutation here. A separately authorized Owner maintenance
# window must already have disabled/stopped the old Owner Task.
AssertOwnerStopped
AssertNoOpenP2Work $root
$recovery = Join-Path $root 'recovery'
if (-not (Test-Path -LiteralPath $recovery)) {
    New-Item -ItemType Directory -Path $recovery -ErrorAction Stop | Out-Null
}
Directory $recovery
$backupId = 'owner-r2-' + [Guid]::NewGuid().ToString('N')
$backup = Join-Path $recovery $backupId
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
$previous = [ordered]@{}
foreach ($rel in $files.Keys) {
    AssertOwnerStopped
    AssertNoOpenP2Work $root
    $destination = Join-Path $app ($rel.Replace('/','\'))
    if (Test-Path -LiteralPath $destination) {
        File $destination
        $saved = Join-Path $backup ($rel.Replace('/','\'))
        $parent = Split-Path -Parent $saved
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }
        [IO.File]::Copy($destination,$saved,$false)
        if ((Hash $saved) -cne (Hash $destination)) { Hold 'PRIVATE_BACKUP_HASH_MISMATCH' }
        $previous[$rel] = (Hash $saved)
    } else {
        $previous[$rel] = 'ABSENT'
    }
}
$ledger = Join-Path $backup 'ledger.json'
$record = [ordered]@{
    schema = 'TTV-OWNER-R2-ROLLBACK-V1'
    source_commit = '90b8c18f343fc37bbfcee8752eec9d6890490d78'
    previous = $previous
}
[IO.File]::WriteAllText($ledger,($record | ConvertTo-Json -Depth 5),
    [Text.UTF8Encoding]::new($false))
File $ledger
Write-Output 'OWNER_R2_PRIVATE_BACKUP=VERIFIED'

$attempted = [Collections.Generic.List[string]]::new()
try {
    foreach ($rel in $files.Keys) {
        AssertOwnerStopped
        AssertNoOpenP2Work $root
        $destination = Join-Path $app ($rel.Replace('/','\'))
        $source = Join-Path $stage ($rel.Replace('/','\'))
        if ((Hash $source) -cne $files[$rel]) { Hold 'SOURCE_CHANGED_DURING_APPLY' }
        if ($previous[$rel] -ceq 'ABSENT') {
            if (Test-Path -LiteralPath $destination) { Hold 'NEW_FILE_CONFLICT' }
        } elseif (-not (Test-Path -LiteralPath $destination) -or
            (Hash $destination) -cne $previous[$rel]) {
            Hold 'BASELINE_CHANGED_DURING_APPLY'
        }
        $temporary = Join-Path (Split-Path -Parent $destination) (
            '.r2-new-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy($source,$temporary,$false)
        if ((Hash $temporary) -cne $files[$rel]) { Hold 'TEMP_HASH_MISMATCH' }
        $attempted.Add($rel)
        if ($previous[$rel] -ceq 'ABSENT') {
            [IO.File]::Move($temporary,$destination)
        } else {
            AtomicReplace $temporary $destination 'r2-original'
        }
        if ((Hash $destination) -cne $files[$rel]) { Hold 'POST_APPLY_HASH_MISMATCH' }
    }
} catch {
    Write-Output 'OWNER_R2_APPLY=ERROR_ATTEMPTING_ROLLBACK'
    try {
        foreach ($rel in $attempted) {
            AssertOwnerStopped
            AssertNoOpenP2Work $root
            $destination = Join-Path $app ($rel.Replace('/','\'))
            if ($previous[$rel] -ceq 'ABSENT') {
                if (Test-Path -LiteralPath $destination) {
                    File $destination
                    if ((Hash $destination) -cne $files[$rel]) { Hold 'NEW_FILE_DRIFT_DURING_ROLLBACK' }
                    [IO.File]::Delete($destination)
                }
                continue
            }
            $saved = Join-Path $backup ($rel.Replace('/','\'))
            File $saved
            if ((Hash $saved) -cne $previous[$rel]) { Hold 'BACKUP_DRIFT_DURING_ROLLBACK' }
            $temporary = Join-Path (Split-Path -Parent $destination) (
                '.r2-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy($saved,$temporary,$false)
            if (Test-Path -LiteralPath $destination) {
                File $destination
                AtomicReplace $temporary $destination 'r2-displaced'
            } else {
                [IO.File]::Move($temporary,$destination)
            }
        }
        foreach ($rel in $files.Keys) {
            $destination = Join-Path $app ($rel.Replace('/','\'))
            if ($previous[$rel] -ceq 'ABSENT') {
                if (Test-Path -LiteralPath $destination) { Hold 'ADDED_FILE_REMAINS' }
            } elseif (-not (Test-Path -LiteralPath $destination) -or
                (Hash $destination) -cne $previous[$rel]) {
                Hold 'BASELINE_ROLLBACK_NOT_VERIFIED'
            }
        }
    } catch {
        Hold 'ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY'
    }
    Hold 'APPLY_FAILED_ROLLBACK_VERIFIED'
}
Write-Output 'OWNER_R2_APPLY=INSTALLED_HASH_VERIFIED_OWNER_STOPPED'
Write-Output ('OWNER_R2_BACKUP_ID=' + $backupId)
Write-Output 'OWNER_R2_OWNER_RESTART=NOT_RUN'
Write-Output 'OWNER_R2_PROVIDER_TV=NOT_RUN'
Write-Output 'OWNER_R2_P2_CHECKPOINTS=NOT_CHANGED'
