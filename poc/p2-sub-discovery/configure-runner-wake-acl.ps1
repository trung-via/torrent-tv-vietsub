# OPTIONAL one-time owner-admin enrollment of an inert WAKE drop folder.
# Does NOT grant GitHub runner Administrator/owner-profile/DPAPI access.
# Never run this with NETWORK_SERVICE; requires interactive owner + UAC.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($id)
$loggedOn = (Get-CimInstance Win32_ComputerSystem).UserName

if ($env:GITHUB_ACTIONS -ceq 'true' -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    -not [Environment]::UserInteractive -or
    -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or
    [string]::IsNullOrWhiteSpace($loggedOn) -or
    -not $id.Name.Equals($loggedOn, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_BRIDGE_WAKE_ACL_NEEDS_INTERACTIVE_OWNER_ADMIN'
}

$root = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge'
$wake = Join-Path $root 'Wake'
if (Test-Path -LiteralPath $wake) {
    $existing = Get-Item -LiteralPath $wake -Force -ErrorAction Stop
    if (-not $existing.PSIsContainer -or
        $existing.Attributes.HasFlag([IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_BRIDGE_WAKE_UNTRUSTED_EXISTING_PATH'
    }
}
New-Item -ItemType Directory -Path $wake -Force | Out-Null

# Owner/System/Admins can read and remove markers. NETWORK_SERVICE may
# create a new marker ONLY; it cannot read the owner's private cache or
# edit owner scripts. Do not grant broad Modify/FullControl here.
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($id.User)
$acl.SetAccessRuleProtection($true, $false)
foreach ($entry in @(
    @{ Sid = $id.User.Value; Rights = 'FullControl'; Inherit = 'ContainerInherit,ObjectInherit' },
    @{ Sid = 'S-1-5-18'; Rights = 'FullControl'; Inherit = 'ContainerInherit,ObjectInherit' },
    @{ Sid = 'S-1-5-32-544'; Rights = 'FullControl'; Inherit = 'ContainerInherit,ObjectInherit' }
)) {
    $sid = [Security.Principal.SecurityIdentifier]::new($entry.Sid)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $sid, $entry.Rights, $entry.Inherit, 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
$netService = [Security.Principal.SecurityIdentifier]::new('S-1-5-20')
$createOnly = [Security.AccessControl.FileSystemAccessRule]::new(
    $netService, 'CreateFiles', 'None', 'None', 'Allow')
$acl.AddAccessRule($createOnly)
Set-Acl -LiteralPath $wake -AclObject $acl -ErrorAction Stop

Write-Host 'OWNER_BRIDGE_RUNNER_WAKE_ACL=ONE_TIME_PROVISIONED'
Write-Host 'OWNER_BRIDGE_RUNNER_PRIVILEGE=CREATE_INERT_MARKER_ONLY'
Write-Host 'OWNER_BRIDGE_RUNNER_PROFILE_ACCESS=DENIED'
Write-Host 'OWNER_BRIDGE_RUNNER_ADMIN_GRANTED=NO'
Write-Host 'OWNER_BRIDGE_FIREWALL_OR_UAC_CHANGED=NO'
