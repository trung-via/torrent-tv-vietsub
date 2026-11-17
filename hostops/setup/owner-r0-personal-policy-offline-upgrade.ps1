# Owner-only R0 personal one-tap policy overlay. NEVER stops or starts Owner.
# Inspect by default; -ApplyOffline requires Disabled task, zero Owner workers,
# zero pending/inflight jobs, exact reviewed old/new policy source and backup.
[CmdletBinding()]
param([switch]$ApplyOffline)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Hold([string]$reason) {
    throw ('R0_PERSONAL_POLICY_HOLD_' + $reason)
}
function RegularFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Hold 'FILE_NOT_FOUND'
    }
    $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Hold 'FILE_REPARSE_POINT'
    }
}
function RegularDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
        Hold 'DIRECTORY_NOT_FOUND'
    }
    $entry = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Hold 'DIRECTORY_REPARSE_POINT'
    }
}
function HashFile([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function CanonicalHash([string]$path) {
    # Legacy installer could copy the same reviewed Python source as CRLF.
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $source = $utf8.GetString([IO.File]::ReadAllBytes($path)) }
    catch { Hold 'SOURCE_ENCODING_INVALID' }
    if ($source.StartsWith([char]0xFEFF) -or
        $source.Replace("`r`n", "`n").Contains("`r")) {
        Hold 'SOURCE_LINE_ENDINGS_INVALID'
    }
    $bytes = $utf8.GetBytes($source.Replace("`r`n", "`n"))
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    Hold 'INTERACTIVE_WINDOWS_OWNER_REQUIRED'
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

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$source = Join-Path $repo 'poc\p2-sub-discovery\owner_p3_p4_private_policy.py'
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installedDir = Join-Path $owner 'app\poc\p2-sub-discovery'
$installed = Join-Path $installedDir 'owner_p3_p4_private_policy.py'
$launcher = Join-Path $owner 'start-owner-session-agent.ps1'
RegularDirectory $owner
RegularDirectory $installedDir
RegularFile $source
RegularFile $installed
RegularFile $launcher

# These pins correspond to original R0 Draft #172 and this source-only fix.
$oldSha = '74e981c0194c68e3731d5c24fb50108440279e84dc7cbe8eb69ee2365b182d30'
$newSha = '3804a2afa1b66889488a8a515472609b0b4b476f85876f9456a73e2e1bf842c5'
if ((HashFile $source) -cne $newSha) { Hold 'REVIEWED_SOURCE_HASH_MISMATCH' }

. (Join-Path $repo 'poc\p2-sub-discovery\owner-task-principal-identity.ps1')
. (Join-Path $repo 'poc\p2-sub-discovery\owner-task-action-identity.ps1')
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
if (-not (Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $identity.User.Value) -or
    -not (Get-TTVOwnerTaskActionState -Task $task `
        -ExpectedExecutable (Get-TTVOwnerCurrentPwshExecutable) `
        -ExpectedLauncher $launcher).Accepted) {
    Hold 'TASK_IDENTITY_MISMATCH'
}
Write-Host ('R0_PERSONAL_TASK_STATE=' + [string]$task.State)

$installedHash = CanonicalHash $installed
if ($installedHash -ceq $newSha) {
    Write-Host 'R0_PERSONAL_INSTALLED_SOURCE=NEW_EXACT'
    Write-Host 'R0_PERSONAL_LOADED_RUNTIME=NOT_ATTESTED'
    exit 0
}
if ($installedHash -cne $oldSha) { Hold 'INSTALLED_SOURCE_NOT_ORIGINAL_R0' }
Write-Host 'R0_PERSONAL_INSTALLED_SOURCE=LEGACY_EXACT'
if (-not $ApplyOffline) {
    Write-Host 'R0_PERSONAL_UPGRADE=READY_FOR_OWNER_OFFLINE_PRECONDITIONS'
    exit 0
}
if ([string]$task.State -cne 'Disabled') { Hold 'TASK_MUST_BE_DISABLED' }

$workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('py.exe', 'python.exe', 'pythonw.exe') -and
    $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
Write-Host ('R0_PERSONAL_OWNER_WORKERS=' + $workers.Count)
if ($workers.Count -ne 0) { Hold 'OWNER_PROCESS_REMAINS' }

$inbox = Join-Path $owner 'inbox'
RegularDirectory $inbox
$pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
$state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$inflight = @()
if (Test-Path -LiteralPath $state) {
    RegularDirectory $state
    $inflight = @(Get-ChildItem -LiteralPath $state -File -Filter '*.inflight' -Recurse)
}
Write-Host ('R0_PERSONAL_PENDING_EVENTS=' + $pending.Count)
Write-Host ('R0_PERSONAL_PROVIDER_INFLIGHT=' + $inflight.Count)
if ($pending.Count -ne 0 -or $inflight.Count -ne 0) {
    Hold 'PENDING_OR_INFLIGHT_WORK'
}
if ((CanonicalHash $installed) -cne $oldSha) {
    Hold 'INSTALLED_SOURCE_CHANGED'
}

$recovery = Join-Path $owner 'recovery'
if (-not (Test-Path -LiteralPath $recovery)) {
    New-Item -ItemType Directory -Path $recovery -ErrorAction Stop | Out-Null
}
RegularDirectory $recovery
$backupDir = Join-Path $recovery ('r0-personal-policy-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backupDir -ErrorAction Stop | Out-Null
$saved = Join-Path $backupDir 'owner_p3_p4_private_policy.py'
[IO.File]::Copy($installed, $saved, $false)
if ((CanonicalHash $saved) -cne $oldSha) { Hold 'BACKUP_MISMATCH' }

$nonce = [Guid]::NewGuid().ToString('N')
$staged = Join-Path $installedDir ('.r0-personal-new-' + $nonce + '.tmp')
$displaced = Join-Path $installedDir ('.r0-personal-old-' + $nonce + '.tmp')
[IO.File]::Copy($source, $staged, $false)
if ((HashFile $staged) -cne $newSha) { Hold 'STAGING_MISMATCH' }
[IO.File]::Replace($staged, $installed, $displaced)
if ((HashFile $installed) -cne $newSha) { Hold 'INSTALL_HASH_MISMATCH' }
Write-Host 'R0_PERSONAL_UPGRADE=INSTALLED_HASH_VERIFIED'
Write-Host 'R0_PERSONAL_BACKUP=PRESERVED_IN_OWNER_RECOVERY'
Write-Host 'R0_PERSONAL_TASK_RESTART=NOT_PERFORMED'
Write-Host 'R0_PERSONAL_LOADED_RUNTIME=NOT_ATTESTED'
