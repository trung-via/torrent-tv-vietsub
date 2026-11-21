# Torrent TV OwnerAgent task-only HostOps delegation (one-time, owner interactive).
# No elevation of the GitHub runner, no access to owner DPAPI secrets.
# Default is READ_ONLY. -Apply changes only the exact task DACL; -Rollback restores.
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Apply -and $Rollback) { throw 'TTV_TASK_ACL_MUTUALLY_EXCLUSIVE_MODES' }
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    throw 'TTV_TASK_ACL_INTERACTIVE_OWNER_ONLY'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
    throw 'TTV_TASK_ACL_SERVICE_IDENTITY_REFUSED'
}
$loggedOnUser = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($loggedOnUser) -or
    -not $identity.Name.Equals($loggedOnUser, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TTV_TASK_ACL_OWNER_LOGON_MISMATCH'
}

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
if (@($task).Count -ne 1 -or $task.TaskPath -cne '\') {
    throw 'TTV_TASK_ACL_TASK_PATH_NOT_EXACT'
}
$principalUser = [string]$task.Principal.UserId
$principalSid = if ($principalUser -match '^S-1-\d+(?:-\d+)+$') {
    $principalUser
} else {
    ([Security.Principal.NTAccount]::new($principalUser)).Translate(
        [Security.Principal.SecurityIdentifier]).Value
}
if ($principalSid -cne $identity.User.Value -or
    [string]$task.Principal.LogonType -cne 'Interactive' -or
    [string]$task.Principal.RunLevel -cne 'Limited') {
    throw 'TTV_TASK_ACL_TASK_PRINCIPAL_MISMATCH'
}
$launcher = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\start-owner-session-agent.ps1'
$actions = @($task.Actions)
if ($actions.Count -ne 1 -or
    [IO.Path]::GetFileName([string]$actions[0].Execute) -ine 'pwsh.exe' -or
    ([string]$actions[0].Arguments).IndexOf(
        $launcher, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    throw 'TTV_TASK_ACL_TASK_ACTION_MISMATCH'
}

$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$registered = $service.GetFolder('\').GetTask($taskName)
$originalSddl = [string]$registered.GetSecurityDescriptor(7)  # Owner + Group + DACL, not SACL
if ([string]::IsNullOrWhiteSpace($originalSddl)) {
    throw 'TTV_TASK_ACL_ORIGINAL_DESCRIPTOR_UNAVAILABLE'
}
$descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($originalSddl)
if ($null -eq $descriptor.DiscretionaryAcl) {
    throw 'TTV_TASK_ACL_NULL_DACL_REFUSED'
}

$networkServiceSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-20')
$requestedBits = [uint32]::Parse(
    'A0000000', [Globalization.NumberStyles]::HexNumber) # GENERIC_READ | GENERIC_EXECUTE
$mask = [BitConverter]::ToInt32([BitConverter]::GetBytes($requestedBits), 0)
$alreadyGranted = $false
foreach ($ace in $descriptor.DiscretionaryAcl) {
    if ($ace -isnot [Security.AccessControl.CommonAce] -or
        $ace.SecurityIdentifier.Value -cne $networkServiceSid.Value) {
        continue
    }
    if ($ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessDenied -and
        (($ace.AccessMask -band $mask) -ne 0)) {
        throw 'TTV_TASK_ACL_EXISTING_DENY_REQUIRES_REVIEW'
    }
    if ($ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed -and
        (($ace.AccessMask -band $mask) -eq $mask)) {
        $alreadyGranted = $true
    }
}
$backupPath = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\hostops-task-acl-receipt.json'

if ($Rollback) {
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        throw 'TTV_TASK_ACL_ROLLBACK_RECEIPT_MISSING'
    }
    $receipt = Get-Content -LiteralPath $backupPath -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
    if ($receipt.schema -cne 'TTV-HOSTOPS-TASK-ACL-V1' -or
        $receipt.task -cne $taskName -or
        $receipt.owner_sid -cne $identity.User.Value -or
        $receipt.after -cne $originalSddl) {
        throw 'TTV_TASK_ACL_ROLLBACK_STATE_DRIFT'
    }
    $registered.SetSecurityDescriptor([string]$receipt.before, 0)
    if ([string]$registered.GetSecurityDescriptor(7) -cne $receipt.before) {
        throw 'TTV_TASK_ACL_ROLLBACK_VERIFY_FAILED'
    }
    Write-Host 'TTV_TASK_ACL_ROLLBACK=PASS'
    Write-Host 'TTV_TASK_ACL_RUNNER_ADMIN_GRANTED=NO'
    return
}
if ($alreadyGranted) {
    Write-Host 'TTV_TASK_ACL_STATUS=NETWORK_SERVICE_READ_EXECUTE_ALREADY_PRESENT'
    return
}
Write-Host 'TTV_TASK_ACL_PREFLIGHT=PASS'
Write-Host 'TTV_TASK_ACL_SCOPE=EXACT_OWNERAGENT_READ_EXECUTE_ONLY'
if (-not $Apply) {
    Write-Host 'TTV_TASK_ACL_MODE=DRY_RUN_NO_CHANGE'
    return
}
if (Test-Path -LiteralPath $backupPath) {
    throw 'TTV_TASK_ACL_PREVIOUS_RECEIPT_REQUIRES_REVIEW'
}
$newAce = [Security.AccessControl.CommonAce]::new(
    [Security.AccessControl.AceFlags]::None,
    [Security.AccessControl.AceQualifier]::AccessAllowed,
    $mask, $networkServiceSid, $false, $null)
$descriptor.DiscretionaryAcl.InsertAce($descriptor.DiscretionaryAcl.Count, $newAce)
$sections = [Security.AccessControl.AccessControlSections]::Owner -bor
    [Security.AccessControl.AccessControlSections]::Group -bor
    [Security.AccessControl.AccessControlSections]::Access
$newSddl = $descriptor.GetSddlForm($sections)
# Original ACL is stored privately before the only task DACL change.
$receipt = [ordered]@{
    schema = 'TTV-HOSTOPS-TASK-ACL-V1'
    task = $taskName
    owner_sid = $identity.User.Value
    before = $originalSddl
    after = ''
}
[IO.File]::WriteAllText(
    $backupPath, ($receipt | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
try {
    $registered.SetSecurityDescriptor($newSddl, 0)
    $applied = [string]$registered.GetSecurityDescriptor(7)
    $verify = [Security.AccessControl.RawSecurityDescriptor]::new($applied)
    $found = @($verify.DiscretionaryAcl | Where-Object {
        $_ -is [Security.AccessControl.CommonAce] -and
        $_.SecurityIdentifier.Value -ceq $networkServiceSid.Value -and
        $_.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed -and
        (($_.AccessMask -band $mask) -eq $mask)
    }).Count -ge 1
    if (-not $found) { throw 'TTV_TASK_ACL_POST_VERIFY_MISSING_ACE' }
    $receipt.after = $applied
    [IO.File]::WriteAllText(
        $backupPath, ($receipt | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
} catch {
    Write-Host 'TTV_TASK_ACL_APPLY=HOLD_CHECK_PRIVATE_ROLLBACK_RECEIPT'
    throw
}
Write-Host 'TTV_TASK_ACL_APPLY=PASS'
Write-Host 'TTV_TASK_ACL_TASK_OWNER_CHANGED=NO'
Write-Host 'TTV_TASK_ACL_RUNNER_ADMIN_GRANTED=NO'
Write-Host 'TTV_TASK_ACL_OWNER_SECRETS_EXPOSED=NO'
Write-Host 'TTV_TASK_ACL_PROCESS_STOP_PRIVILEGE_GRANTED=NO'