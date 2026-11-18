# P2-F6: reconcile the *installed* Owner bootstrap with F4/F5 Antigravity CLI.
# Default: read-only. Install changes three pinned source files only after
# the interactive owner has disabled the task and there is no active work.
# No listener, provider, queue replay, secret export, or task start.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Install')][switch]$InstallOffline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Host 'P2_F6_VERSION=OWNER_BOOTSTRAP_COMPAT_V1_1_CRLF_PIN'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'P2_F6_WINDOWS_REQUIRED'
}
if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'P2_F6_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'P2_F6_SERVICE_OWNER_FORBIDDEN'
}

# Fixed CANONICAL (UTF-8 + LF) hashes derived from exact PR #173 head e186606
# and R0 integration base eb7695e. Git .gitattributes checks out PowerShell
# sources with CRLF; Canonical-Bytes normalizes those back to LF before SHA.
# Unknown installed source is never replaced.
$modules = [ordered]@{
    'automatic_vietsub_flow.py' = @{
        new = '57529953f6e0d5e13f7cc56165873e40818b801ac3e4144b94445a583076af04'
        old = '4a9c248c9099d410f3d1f986373e874818e17fc4eabe499aa9a20d7f73b16a5a'
    }
    'owner_vietsub_pipeline.py' = @{
        new = '08ddd41e0474c6e85b6916e632dca4e811d8901b8193e1124cbabdc5dd3194d3'
        old = '391b1c81c3071d68eedcacc34a6257cf7480a788facfd2cc72d2f05bc3b3a30b'
    }
    'start-owner-session-agent.ps1' = @{
        new = '29d66749f4c44dfb396f971ea09660dd50e958eb0c10cbb312f07fd19df5bf74'
        old = '74d3139a5bc255023058d6029eb28d09065fef92caa195fd4f894c4e2d64fd70'
    }
}
$dependencies = [ordered]@{
    'translator_profile.json' = '43a7e2234e1c0a407f4e821ac4ddfb342daa2eb3d9166a5f9d0aec706ac62394'
    'translator_gateway.py' = 'b06c151cc4275a7793fdb7891d7859715e602a676a553ea89e6e242578190183'
    'automatic_lean120_worker.py' = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
    'cached_en_direct_handoff.py' = 'a4fc357f427d4bda9b73dadf93dd5bfd3a2c644425f2ea8cb6f7d78fd85c90b1'
}

function Canonical-Bytes([string]$File) {
    $item = Get-Item -LiteralPath $File -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P2_F6_UNSAFE_FILE'
    }
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $value = $utf8.GetString([IO.File]::ReadAllBytes($File))
    if ($value.StartsWith([char]0xFEFF) -or
        $value.Replace("`r`n", "`n").Contains("`r")) {
        throw 'P2_F6_INVALID_TEXT_ENCODING'
    }
    return ,($utf8.GetBytes($value.Replace("`r`n", "`n")))
}
function Sha([byte[]]$Bytes) {
    return [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
function Put-New([string]$Path, [byte[]]$Bytes) {
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sourceRoot = Join-Path $repoRoot 'poc\p2-sub-discovery'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$installedRoot = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$installedP2 = Join-Path $ownerRoot 'app\poc\p2-aisub'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$configured = [string]$task.Principal.UserId
$sid = if ($configured -match '^S-1-') { $configured } else {
    ([Security.Principal.NTAccount]::new($configured)).Translate(
        [Security.Principal.SecurityIdentifier]).Value
}
if ($sid -cne $identity.User.Value -or
    [string]$task.Principal.LogonType -ne 'Interactive') {
    throw 'P2_F6_TASK_OWNER_MISMATCH'
}

$sources = [ordered]@{}
$priorHashes = [ordered]@{}
$changes = [System.Collections.Generic.List[string]]::new()
foreach ($name in $modules.Keys) {
    $src = Join-Path $sourceRoot $name
    if ($name -ceq 'start-owner-session-agent.ps1') {
        $dst = Join-Path $ownerRoot $name
    } else {
        $dst = Join-Path $installedRoot $name
    }
    $sourceBytes = Canonical-Bytes $src
    $oldBytes = Canonical-Bytes $dst
    $newSha = Sha $sourceBytes
    $oldSha = Sha $oldBytes
    if ($newSha -cne $modules[$name].new) { throw 'P2_F6_SOURCE_PIN_MISMATCH' }
    $status = if ($oldSha -ceq $newSha) { 'MATCH' }
        elseif ($oldSha -ceq $modules[$name].old) { 'BASE_COMPAT' }
        else { 'UNKNOWN_INSTALLED' }
    Write-Host ('P2_F6_MODULE=' + $name + ' STATUS=' + $status)
    if ($status -ceq 'UNKNOWN_INSTALLED') {
        throw 'P2_F6_INSTALLED_SOURCE_UNRECOGNIZED_HOLD'
    }
    if ($status -ceq 'BASE_COMPAT') { $changes.Add($name) }
    $sources[$name] = $sourceBytes
    $priorHashes[$name] = $oldSha
}

$depDrift = 0
foreach ($name in $dependencies.Keys) {
    $dep = Join-Path $installedP2 $name
    if (-not (Test-Path -LiteralPath $dep -PathType Leaf) -or
        (Sha (Canonical-Bytes $dep)) -cne $dependencies[$name]) {
        $depDrift++
    }
}
Write-Host ('P2_F6_DEPENDENCY_MISMATCH_COUNT=' + $depDrift)
Write-Host ('P2_F6_TASK_STATE=' + [string]$task.State)
Write-Host ('P2_F6_FILES_TO_UPDATE=' + $changes.Count)
if (-not $InstallOffline) {
    Write-Host 'P2_F6_RESULT=INSPECT_ONLY_NO_CHANGES'
    return
}
if ($depDrift -ne 0) { throw 'P2_F6_DEPENDENCY_DRIFT_HOLD' }
if ([string]$task.State -cne 'Disabled') {
    throw 'P2_F6_TASK_MUST_BE_DISABLED'
}
$processes = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
    $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
$pending = @()
$inbox = Join-Path $ownerRoot 'inbox'
if (Test-Path -LiteralPath $inbox -PathType Container) {
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
}
$locks = @()
$state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
if (Test-Path -LiteralPath $state -PathType Container) {
    $locks = @(Get-ChildItem -LiteralPath $state -File -Filter 'active.lock' -Recurse)
}
Write-Host ('P2_F6_RUNNING_OWNER_COUNT=' + $processes.Count)
Write-Host ('P2_F6_PENDING_EVENT_COUNT=' + $pending.Count)
Write-Host ('P2_F6_ACTIVE_LOCK_COUNT=' + $locks.Count)
if ($processes.Count -ne 0 -or $pending.Count -ne 0 -or $locks.Count -ne 0) {
    throw 'P2_F6_OWNER_NOT_QUIESCENT'
}
if ($changes.Count -eq 0) {
    Write-Host 'P2_F6_RESULT=ALREADY_COMPATIBLE_NO_CHANGES'
    return
}

$backups = Join-Path $ownerRoot 'backups\p2-f6-bootstrap'
[IO.Directory]::CreateDirectory($backups) | Out-Null
$folder = Join-Path $backups ('p2f6-' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ') +
    '-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($folder) | Out-Null

# Stage/backup EVERYTHING before the first replacement. Never delete original
# bytes or private state, even when a later module update fails.
$destinations = [ordered]@{}
foreach ($name in $changes) {
    $destination = if ($name -ceq 'start-owner-session-agent.ps1') {
        Join-Path $ownerRoot $name
    } else { Join-Path $installedRoot $name }
    $destinations[$name] = $destination
    $original = [IO.File]::ReadAllBytes($destination)
    if ((Sha (Canonical-Bytes $destination)) -cne $priorHashes[$name]) {
        throw 'P2_F6_TARGET_CHANGED_DURING_BACKUP'
    }
    Put-New (Join-Path $folder ('original-' + $name)) $original
    Put-New (Join-Path $folder ('stage-' + $name)) $sources[$name]
    if ((Sha (Canonical-Bytes (Join-Path $folder ('stage-' + $name)))) -cne
        $modules[$name].new) { throw 'P2_F6_STAGE_PIN_MISMATCH' }
}
if ([string](Get-ScheduledTask -TaskName $taskName).State -cne 'Disabled') {
    throw 'P2_F6_TASK_CHANGED_BEFORE_COMMIT'
}
Write-Host ('P2_F6_BACKUP_CREATED=YES')
$done = [System.Collections.Generic.List[string]]::new()
try {
    foreach ($name in $changes) {
        if ((Sha (Canonical-Bytes $destinations[$name])) -cne $priorHashes[$name]) {
            throw 'P2_F6_TARGET_CHANGED_BEFORE_REPLACE'
        }
        [IO.File]::Replace((Join-Path $folder ('stage-' + $name)),
            $destinations[$name], (Join-Path $folder ('displaced-' + $name)))
        $done.Add($name)
        if ((Sha (Canonical-Bytes $destinations[$name])) -cne $modules[$name].new) {
            throw 'P2_F6_REPLACEMENT_VERIFY_FAILED'
        }
    }
} catch {
    $rolledBack = $true
    foreach ($name in $done) {
        try {
            $restore = Join-Path $folder ('rollback-' + $name)
            [IO.File]::Copy((Join-Path $folder ('original-' + $name)), $restore, $false)
            [IO.File]::Replace($restore, $destinations[$name],
                (Join-Path $folder ('failed-' + $name)))
        } catch { $rolledBack = $false }
    }
    Write-Host ('P2_F6_ROLLBACK=' + $(if ($rolledBack) { 'RESTORED' } else { 'HOLD_MANUAL_REVIEW' }))
    throw 'P2_F6_INSTALL_FAILED_KEEP_TASK_DISABLED'
}

Write-Host 'P2_F6_RESULT=BOOTSTRAP_COMPAT_INSTALLED_VERIFIED_TASK_DISABLED'
Write-Host 'P2_F6_QUARANTINED_BATCH=UNTOUCHED_NO_RETRY'
