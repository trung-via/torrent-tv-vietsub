# R0 #174 — one-time interactive Owner enrollment for sanitized receipts ONLY.
# Default mode inspects; -Enroll creates/configures a dedicated ProgramData
# directory, -Disable revokes NETWORK_SERVICE read. Neither touches OwnerBridge
# private files, scheduled tasks, models, queue, firewall or TV.
[CmdletBinding()]
param([switch] $Enroll, [switch] $Disable)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Enroll -and $Disable) { throw 'TTV_HOSTOPS_DIAG_CONFLICTING_ACTIONS' }

$who = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($who)
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
$loggedOn = (Get-CimInstance Win32_ComputerSystem).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or $session -le 0 -or
    -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    [string]::IsNullOrWhiteSpace($loggedOn) -or
    -not $who.Name.Equals($loggedOn, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TTV_HOSTOPS_DIAG_INTERACTIVE_OWNER_ADMIN_REQUIRED'
}

$parent = Join-Path $env:ProgramData 'TorrentTVVietsub'
$bridge = Join-Path $parent 'OwnerBridge'
$folder = Join-Path $bridge 'Diagnostics'
foreach ($path in @($env:ProgramData, $parent, $bridge, $folder)) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'TTV_HOSTOPS_DIAG_UNTRUSTED_PATH'
        }
    }
}

if (-not $Enroll -and -not $Disable) {
    Write-Output 'HOSTOPS_DIAG_ENROLL_MODE=READ_ONLY_INSPECT'
    Write-Output ('HOSTOPS_DIAG_ENROLLED_FOLDER=' + $(if (Test-Path -LiteralPath $folder -PathType Container) { 'PRESENT' } else { 'MISSING' }))
    Write-Output 'HOSTOPS_DIAG_PRIVATE_OWNER_DATA=NOT_READ'
    return
}
if ($Disable -and -not (Test-Path -LiteralPath $folder -PathType Container)) {
    Write-Output 'HOSTOPS_DIAG_READ_ACCESS=ALREADY_DISABLED'
    return
}
if ($Enroll) {
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
}

$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($who.User)
$acl.SetAccessRuleProtection($true, $false)
foreach ($entry in @(
    @{ Sid = $who.User.Value; Rights = 'FullControl' },
    @{ Sid = 'S-1-5-18'; Rights = 'FullControl' },
    @{ Sid = 'S-1-5-32-544'; Rights = 'FullControl' }
)) {
    $sid = [Security.Principal.SecurityIdentifier]::new($entry.Sid)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $sid, $entry.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
if ($Enroll) {
    $runnerSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-20')
    $readOnly = [Security.AccessControl.FileSystemAccessRule]::new(
        $runnerSid, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($readOnly)
}
Set-Acl -LiteralPath $folder -AclObject $acl
Write-Output ('HOSTOPS_DIAG_READ_ACCESS=' + $(if ($Enroll) { 'ENROLLED_READ_ONLY' } else { 'DISABLED' }))
Write-Output 'HOSTOPS_DIAG_PRIVATE_OWNER_DATA=NOT_ACCESSED'
Write-Output 'HOSTOPS_DIAG_TASK_OR_PROVIDER_MUTATION=NONE'
Write-Output 'HOSTOPS_DIAG_ROLLBACK=RUN_SCRIPT_WITH_DISABLE'
