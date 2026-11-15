# Owner-interactive, source-pinned, INERT staging of P3/P4 diagnostic V2.
# No active OwnerBridge application file, Scheduled Task, process, TV, LAN,
# Windows ACL, provider, pairing key or private media is changed.
# Default is read-only. -Stage only prepares an immutable candidate for a
# separately reviewed, idle-proven offline activation.
[CmdletBinding()]
param([switch]$Stage)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-TTVStage([string]$Reason) {
    Write-Host ('TTV_OWNER_V2_STAGE=HOLD_' + $Reason)
    throw 'TTV_OWNER_V2_STAGE_PRECONDITION_FAILED'
}

function Get-TTVCanonicalSourceBytes([string]$Path) {
    # Windows Git checkouts can turn a Git LF blob into CRLF without changing
    # its logical source. Verify and stage the exact Git LF bytes, never a
    # checkout-dependent encoding/newline variant of the reviewed candidate.
    $raw = [IO.File]::ReadAllBytes($Path)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    try { $source = $utf8.GetString($raw) }
    catch { Stop-TTVStage 'SOURCE_ENCODING_INVALID' }
    if ($source.StartsWith([char]0xFEFF) -or
        $source.Replace("`r`n", "`n").Contains("`r")) {
        Stop-TTVStage 'SOURCE_LINE_ENDINGS_INVALID'
    }
    $normal = $source.Replace("`r`n", "`n")
    return ,($utf8.GetBytes($normal))
}

function Get-TTVSHA256([byte[]]$Bytes) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hasher.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant()
    } finally { $hasher.Dispose() }
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    Stop-TTVStage 'INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
    Stop-TTVStage 'SERVICE_IDENTITY'
}
$loggedOn = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($loggedOn) -or
    -not $identity.Name.Equals($loggedOn, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-TTVStage 'WRONG_WINDOWS_OWNER'
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$src = Join-Path $repo 'poc\p2-sub-discovery'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
$installed = Join-Path $root 'app\poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'
foreach ($path in @($root, $launcher, $installed)) {
    if (-not (Test-Path -LiteralPath $path)) {
        Stop-TTVStage 'OWNER_INSTALL_NOT_VERIFIED'
    }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint) {
        Stop-TTVStage 'OWNER_PATH_REPARSE_POINT'
    }
}

$principalGuard = Join-Path $src 'owner-task-principal-identity.ps1'
$actionGuard = Join-Path $src 'owner-task-action-identity.ps1'
if (-not (Test-Path -LiteralPath $principalGuard -PathType Leaf) -or
    -not (Test-Path -LiteralPath $actionGuard -PathType Leaf)) {
    Stop-TTVStage 'TASK_GUARDS_MISSING'
}
. $principalGuard
. $actionGuard
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
$matchSid = Test-TTVOwnerTaskPrincipal -Principal $task.Principal -ExpectedSid $identity.User.Value
$pwsh = Get-TTVOwnerCurrentPwshExecutable
$action = Get-TTVOwnerTaskActionState -Task $task -ExpectedExecutable $pwsh -ExpectedLauncher $launcher
if (-not $matchSid -or -not $action.Accepted) {
    Stop-TTVStage 'TASK_IDENTITY_MISMATCH'
}
Write-Host 'TTV_OWNER_V2_OWNER_SID_MATCH=TRUE'
Write-Host 'TTV_OWNER_V2_TASK_IDENTITY=VERIFIED'
Write-Host ('TTV_OWNER_V2_TASK_STATE=' + [string]$task.State)

# Known exact SHA-256 bytes from Draft #165 head f7fdb02404660ced8e3834a6a621ccdfb8de63cd.
# Pin the four production modules, rather than trusting a movable branch or
# a ZIP label. This staging script itself may live in a follow-up Draft PR.
$files = [ordered]@{
    'owner_p3_p4_diagnostics.py' = 'a30bc451c4d8d0c38d9899773c9c33a9c0e0ba7e0bf98cd0f351c2f873877886'
    'p3_owner_state_wiring.py' = '4bbafda8444413a2d7e907f10aa2cce904be03e8bcb1075f39e01fa4bd60e73a'
    'p3_p4_shared_https_route.py' = 'ab9deb57a7d568c1a5141a50a18afe5831577242d0e8e7723f569dec4ef27d2e'
    'p3_ingress_telemetry.py' = '69f6711496575dd61ba82d3260d39726232b761bc395e22c10435d917c405b69'
}
foreach ($name in $files.Keys) {
    $path = Join-Path $src $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint) {
        Stop-TTVStage 'SOURCE_HASH_MISMATCH'
    }
    $bytes = Get-TTVCanonicalSourceBytes $path
    if ((Get-TTVSHA256 $bytes) -cne $files[$name]) {
        Stop-TTVStage 'SOURCE_HASH_MISMATCH'
    }
}
Write-Host 'TTV_OWNER_V2_SOURCE_PIN=F7FDB024_VERIFIED'

# V1 READY is emitted before private inbox processing; it is not an IDLE
# proof. A read-only observer cannot atomically prevent a new P3 request or
# prove no in-flight quota call. Never automatically restart from this script.
Write-Host 'TTV_OWNER_V2_ACTIVE_PROVIDER_JOB=UNPROVEN_V1'
Write-Host 'TTV_OWNER_V2_RESTART=NOT_AUTHORIZED_BY_THIS_SCRIPT'
if (-not $Stage) {
    Write-Host 'TTV_OWNER_V2_STAGE=READ_ONLY_PREFLIGHT_PASS'
    exit 0
}

# Inert owner-only staging: no file is copied into the installed app tree.
# The existing OwnerBridge root is already owner/SYSTEM ACL protected.
$stages = Join-Path $root 'staged-releases'
$target = Join-Path $stages 'p3p4-ingress-v2-f7fdb024'
foreach ($folder in @($stages, $target)) {
    if (Test-Path -LiteralPath $folder) {
        $item = Get-Item -LiteralPath $folder -Force
        if (-not $item.PSIsContainer -or
            $item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Stop-TTVStage 'STAGE_DIRECTORY_CONFLICT'
        }
    } else {
        New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
    }
}
foreach ($name in $files.Keys) {
    $dest = Join-Path $target $name
    if (Test-Path -LiteralPath $dest) {
        $item = Get-Item -LiteralPath $dest -Force
        if ($item.PSIsContainer -or
            $item.Attributes -band [IO.FileAttributes]::ReparsePoint -or
            (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $files[$name]) {
            Stop-TTVStage 'STAGED_FILE_CONFLICT'
        }
    } else {
        # CreateNew ensures a concurrent owner process cannot be overwritten.
        $bytes = Get-TTVCanonicalSourceBytes (Join-Path $src $name)
        $stream = [IO.File]::Open($dest, [IO.FileMode]::CreateNew,
                                  [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
    }
    if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -cne $files[$name]) {
        Stop-TTVStage 'POSTCOPY_HASH_MISMATCH'
    }
}
Write-Host 'TTV_OWNER_V2_STAGE=INERT_FILES_VERIFIED'
Write-Host 'TTV_OWNER_V2_INSTALLED_RUNTIME=UNCHANGED'
Write-Host 'TTV_OWNER_V2_ACTIVATION=HOLD_UNTIL_SAFE_IDLE_OWNER_STOP_AND_REVIEW'
