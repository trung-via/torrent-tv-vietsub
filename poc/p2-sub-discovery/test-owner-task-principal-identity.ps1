# Pure Windows TaskScheduler principal ID regression: NO task changes.
# The current runner Windows identity is used only in memory to check both
# TaskScheduler's SID and DOMAIN\User representations; never emit either.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'owner-task-principal-identity.ps1')

function Require-Same([string]$name, [object]$principal,
                       [string]$sid, [bool]$expected) {
    $result = [bool](Test-TTVOwnerTaskPrincipal -Principal $principal -ExpectedSid $sid)
    if ($result -ne $expected) { throw ('OWNER_TASK_SID_REGRESSION_' + $name) }
}
$current = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($null -eq $current.User) { throw 'OWNER_TASK_SID_TEST_IDENTITY_UNAVAILABLE' }
$sid = [string]$current.User.Value
$displayName = [string]$current.Name
$principal = [pscustomobject]@{
    UserId = $sid
    LogonType = 'Interactive'
    RunLevel = 'Limited'
}
Require-Same 'IDENTICAL_SID' $principal $sid $true
$principal.UserId = $displayName
Require-Same 'NTACCOUNT_TRANSLATES_TO_SAME_SID' $principal $sid $true
$principal.UserId = $displayName.ToUpperInvariant()
Require-Same 'CASE_VARIANT_SAME_SID' $principal $sid $true
$principal.UserId = 'S-1-5-18'
if ($sid -ceq 'S-1-5-18') { $principal.UserId = 'S-1-5-20' }
Require-Same 'FOREIGN_SID_DENIED' $principal $sid $false
$principal.UserId = $sid
$principal.LogonType = 'ServiceAccount'
Require-Same 'SERVICE_LOGON_DENIED' $principal $sid $false
$principal.LogonType = 'Password'
Require-Same 'PASSWORD_LOGON_DENIED' $principal $sid $false
$principal.LogonType = 'Interactive'
$principal.RunLevel = 'Highest'
Require-Same 'ELEVATED_RUNLEVEL_DENIED' $principal $sid $false
$principal.RunLevel = 'Limited'
$principal.UserId = 'this-user-does-not-exist---123456789'
Require-Same 'UNKNOWN_PRINCIPAL_DENIED' $principal $sid $false
Write-Host 'P3_P4_OWNER_TASK_SID_NAMES_AND_SAFETY_REGRESSION=PASS'
Write-Host 'P3_P4_OWNER_TASK_USER_SID_OR_NAME_LOGGED=NO'
Write-Host 'P3_P4_REAL_OWNER_TASK_MUTATION=NO'
