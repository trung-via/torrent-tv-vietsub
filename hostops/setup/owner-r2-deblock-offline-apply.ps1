# Exact three-module R2 Owner hotfix. Inspect is the default. -ApplyOffline
# requires the existing OwnerAgent to be disabled/stopped separately.
# No LAN, TV, provider, Windows task mutation, or old P2 batch replay.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [switch]$ApplyOffline
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Hold([string]$reason) {
    Write-Output ('OWNER_DEBLOCK_OFFLINE=HOLD_' + $reason)
    throw 'OWNER_DEBLOCK_OFFLINE_HOLD'
}
function RequireDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_MISSING_OR_REPARSE'
    }
}
function RequireFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_MISSING_OR_REPARSE'
    }
}
function Hash([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function RequireStopped {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    if ([string]$task.State -cne 'Disabled') { Hold 'OWNER_TASK_NOT_DISABLED' }
    $workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
    if ($workers.Count -ne 0) { Hold 'OWNER_WORKERS_NOT_STOPPED' }
}
function RequireIdle {
    $inbox = Join-Path $ownerRoot 'inbox'
    RequireDirectory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'PENDING_OWNER_EVENTS'
    }
    $p2 = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    if (Test-Path -LiteralPath $p2) {
        RequireDirectory $p2
        if (@(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter 'batch-*.inflight').Count -gt 0 -or
            @(Get-ChildItem -LiteralPath $p2 -File -Recurse -Filter 'active.lock').Count -gt 0) {
            Hold 'ACTIVE_OR_UNCERTAIN_P2_JOB'
        }
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$loggedIn = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($loggedIn) -or
    -not $identity.Name.Equals($loggedIn,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $ownerRoot 'app'
$stage = Join-Path $ownerRoot ('staged-releases\owner-r2-deblock-175-' + $SourceCommit.Substring(0,12))
foreach ($directory in @($ownerRoot,$app,$stage)) { RequireDirectory $directory }
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
$taskSid = [string]$task.Principal.UserId
if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($taskSid -cne $identity.User.Value -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    Hold 'OWNER_TASK_IDENTITY_DRIFT'
}

# Old bytes are exactly the installed R2 release, not a generic root/branch.
$files = [ordered]@{
    'owner_session_bridge.py' = @('6a8af62e4ff33806b7fd3c2deb66df08283302d3441c51edd65da02d1633ce31',
                                  '5727ac9f71a5b736c198ce5697714d6a66fcf5b20feb4331a2db905ce1e8b997')
    'verified_v3_processor.py' = @('e20d3d0aa8176692c6dedcfa107a71f384cfdb11ca734e95d8b857940a2956d3',
                                    'e3fc95986247f928cdc651fdc6afc94bbdcaca49cb62f0b7a6382da2fbb32d43')
    'owner_r2_verified_processor.py' = @('f8a4aec4ed350488e92821b6400eb40782d9603141c07099b023abfd1effff13',
                                          '8eb8579d82a710aff28380cf5cae146393a69fecb4fa2ecbd3d11e1ff4b466ae')
}
$directory = 'poc\p2-sub-discovery'
$installedDir = Join-Path $app $directory
$stagedDir = Join-Path $stage $directory
foreach ($dir in @($installedDir,$stagedDir)) { RequireDirectory $dir }
$statuses = @()
foreach ($name in $files.Keys) {
    $candidate = Join-Path $stagedDir $name
    $installed = Join-Path $installedDir $name
    RequireFile $candidate
    RequireFile $installed
    if ((Hash $candidate) -cne $files[$name][1]) { Hold 'STAGE_HASH_MISMATCH' }
    $current = Hash $installed
    if ($current -ceq $files[$name][0]) { $statuses += 'OLD' }
    elseif ($current -ceq $files[$name][1]) { $statuses += 'NEW' }
    else { Hold 'INSTALLED_BASELINE_UNEXPECTED' }
}
Write-Output 'OWNER_DEBLOCK_STAGE=3_FILES_HASH_VERIFIED'
if (@($statuses | Select-Object -Unique).Count -ne 1) {
    Hold 'MIXED_INSTALLED_STATE'
}
if ($statuses[0] -ceq 'NEW') {
    Write-Output 'OWNER_DEBLOCK_OFFLINE=ALREADY_INSTALLED'
    return
}
if (-not $ApplyOffline) {
    Write-Output 'OWNER_DEBLOCK_OFFLINE=INSPECT_PASS_OLD_OWNER_UNCHANGED'
    return
}

RequireStopped
RequireIdle
$recovery = Join-Path $ownerRoot 'recovery'
if (-not (Test-Path -LiteralPath $recovery)) {
    New-Item -ItemType Directory -Path $recovery -ErrorAction Stop | Out-Null
}
RequireDirectory $recovery
$backupId = 'owner-deblock-' + [Guid]::NewGuid().ToString('N')
$backup = Join-Path $recovery $backupId
New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
foreach ($name in $files.Keys) {
    $original = Join-Path $installedDir $name
    $copy = Join-Path $backup $name
    [IO.File]::Copy($original,$copy,$false)
    if ((Hash $copy) -cne $files[$name][0]) { Hold 'BACKUP_HASH_MISMATCH' }
}
Write-Output 'OWNER_DEBLOCK_BACKUP=3_OLD_FILES_VERIFIED'
$changed = [Collections.Generic.List[string]]::new()
try {
    foreach ($name in $files.Keys) {
        RequireStopped
        RequireIdle
        $installed = Join-Path $installedDir $name
        if ((Hash $installed) -cne $files[$name][0]) { Hold 'BASELINE_CHANGED' }
        $temp = Join-Path $installedDir ('.deblock-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy((Join-Path $stagedDir $name),$temp,$false)
        if ((Hash $temp) -cne $files[$name][1]) { Hold 'COPY_HASH_MISMATCH' }
        [IO.File]::Move($temp,$installed,$true)
        $changed.Add($name)
        if ((Hash $installed) -cne $files[$name][1]) { Hold 'INSTALLED_HASH_MISMATCH' }
    }
} catch {
    # Recover exactly our own changed files; do not resume on partial state.
    foreach ($name in $changed) {
        $installed = Join-Path $installedDir $name
        $temp = Join-Path $installedDir ('.deblock-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::Copy((Join-Path $backup $name),$temp,$false)
        [IO.File]::Move($temp,$installed,$true)
        if ((Hash $installed) -cne $files[$name][0]) { Hold 'ROLLBACK_HASH_MISMATCH' }
    }
    Hold 'INSTALL_FAILED_OLD_BYTES_RESTORED_OWNER_STOPPED'
}
Write-Output 'OWNER_DEBLOCK_OFFLINE=APPLIED_HASH_VERIFIED_OWNER_STOPPED'
Write-Output ('OWNER_DEBLOCK_BACKUP_ID=' + $backupId)
Write-Output 'OWNER_DEBLOCK_OWNER_RESTART=NOT_RUN'
Write-Output 'OWNER_DEBLOCK_P2_CHECKPOINTS=NOT_CHANGED'
