# Exact owner-local legacy model credential retirement.
# Read-only by default. This script never starts/stops Owner or invokes a model.
[CmdletBinding()]
param([switch]$RetireLegacyGeminiKey)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'P2_PROVIDER_SWITCH_INTERACTIVE_WINDOWS_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_PROVIDER_SWITCH_WRONG_WINDOWS_OWNER'
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$profile = Join-Path $repo 'poc\p2-aisub\translator_profile.json'
if (-not (Test-Path -LiteralPath $profile -PathType Leaf)) {
    throw 'P2_PROVIDER_SWITCH_PROFILE_MISSING'
}
$config = Get-Content -LiteralPath $profile -Raw -ErrorAction Stop |
    ConvertFrom-Json -ErrorAction Stop
if ($config.provider -cne 'antigravity') {
    throw 'P2_PROVIDER_SWITCH_ANTIGRAVITY_SOURCE_REQUIRED'
}

$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$inbox = Join-Path $owner 'inbox'
$inflightRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$legacy = Join-Path $owner 'secrets\gemini.dpapi'
$opensub = Join-Path $owner 'secrets\opensub.dpapi'
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
$workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('py.exe', 'python.exe', 'pythonw.exe') -and
    $_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
$pending = @()
if (Test-Path -LiteralPath $inbox -PathType Container) {
    $pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json')
}
$inflight = @()
if (Test-Path -LiteralPath $inflightRoot -PathType Container) {
    $inflight = @(Get-ChildItem -LiteralPath $inflightRoot -File -Filter '*.inflight' -Recurse)
}
$legacyExists = Test-Path -LiteralPath $legacy -PathType Leaf
$openExists = Test-Path -LiteralPath $opensub -PathType Leaf

Write-Host ('P2_SWITCH_TASK_STATE=' + [string]$task.State)
Write-Host ('P2_SWITCH_OWNER_PROCESS_COUNT=' + $workers.Count)
Write-Host ('P2_SWITCH_PENDING_EVENT_COUNT=' + $pending.Count)
Write-Host ('P2_SWITCH_PROVIDER_INFLIGHT_COUNT=' + $inflight.Count)
Write-Host ('P2_SWITCH_LEGACY_GEMINI_SECRET_PRESENT=' + $legacyExists)
Write-Host ('P2_SWITCH_OPENSUBTITLES_SECRET_PRESENT=' + $openExists)

if (-not $RetireLegacyGeminiKey) {
    Write-Host 'P2_SWITCH_LEGACY_KEY_REMOVAL=NOT_REQUESTED_READ_ONLY'
    return
}
if ([string]$task.State -cne 'Disabled' -or
    $workers.Count -ne 0 -or $pending.Count -ne 0 -or
    $inflight.Count -ne 0) {
    throw 'P2_SWITCH_HOLD_ACTIVE_PENDING_OR_INFLIGHT_WORK'
}
if (-not $legacyExists) {
    Write-Host 'P2_SWITCH_LEGACY_KEY_REMOVAL=ALREADY_ABSENT'
    return
}
$entry = Get-Item -LiteralPath $legacy -Force -ErrorAction Stop
if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'P2_SWITCH_LEGACY_SECRET_REPARSE_POINT'
}
# Exactly one obsolete DPAPI ciphertext; no wildcard or recursive delete.
Remove-Item -LiteralPath $legacy -Force -ErrorAction Stop
if (Test-Path -LiteralPath $legacy) {
    throw 'P2_SWITCH_LEGACY_SECRET_REMOVAL_UNVERIFIED'
}
Write-Host 'P2_SWITCH_LEGACY_GEMINI_SECRET=REMOVED_EXACT_FILE'
Write-Host 'P2_SWITCH_OPENSUBTITLES_SECRET=UNCHANGED'
