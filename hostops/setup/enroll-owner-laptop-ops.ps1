# One-time Owner-interactive enrollment of reusable routine laptop operations.
# Does not stop the existing Owner Agent, run an operation or install on TV.
[CmdletBinding(DefaultParameterSetName='Inspect')]
param(
    [Parameter(ParameterSetName='Enroll')][switch]$Enroll,
    [Parameter(ParameterSetName='Enroll', Mandatory=$true)]
    [ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [Parameter(ParameterSetName='Enroll', Mandatory=$true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedHelperSha256,
    [Parameter(ParameterSetName='Revoke')][switch]$Revoke
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$name = 'TorrentTV-Vietsub-Laptop-HostOps'
$description = 'TTV_LAPTOP_HOSTOPS_OWNER_INTERACTIVE_ROUTINE_V1'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_OPS_ENROLL_INTERACTIVE_LOGGED_IN_OWNER_REQUIRED'
}
$pwsh = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.Path]::GetFileName($pwsh).Equals('pwsh.exe',
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_OPS_ENROLL_POWERSHELL_7_REQUIRED'
}
$oldTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' `
    -ErrorAction Stop
function SidOf([string]$id) {
    if ($id -match '^S-\d+(?:-\d+){2,}$') { return $id }
    return ([Security.Principal.NTAccount]::new($id).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ((SidOf ([string]$oldTask.Principal.UserId)) -cne $identity.User.Value -or
    [string]$oldTask.Principal.LogonType -ine 'Interactive') {
    throw 'OWNER_OPS_ENROLL_OWNER_AGENT_IDENTITY_DRIFT'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$maintenance = Join-Path $root 'Maintenance'
$helper = Join-Path $maintenance 'owner-laptop-ops-helper.ps1'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestDir = Join-Path $spool 'Requests'
$receiptDir = Join-Path $spool 'Receipts'
$historyDir = Join-Path $spool 'History'
$arguments = '-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"'

function AssertTask($task) {
    if ($null -eq $task) { throw 'OWNER_OPS_ENROLL_TASK_MISSING' }
    $triggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
    if ([string]$task.Description -cne $description -or
        (SidOf ([string]$task.Principal.UserId)) -cne $identity.User.Value -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        [string]$task.Principal.RunLevel -ine 'Limited' -or
        $triggers -ne 0 -or @($task.Actions).Count -ne 1 -or
        [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
        -not [IO.Path]::GetFullPath([string]$task.Actions[0].Execute).Equals(
            [IO.Path]::GetFullPath($pwsh), [StringComparison]::OrdinalIgnoreCase) -or
        [string]$task.Actions[0].Arguments -cne $arguments -or
        -not [string]::IsNullOrWhiteSpace([string]$task.Actions[0].WorkingDirectory)) {
        throw 'OWNER_OPS_ENROLL_TASK_ACTION_OR_OWNER_DRIFT'
    }
}
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
if ($null -ne $task) { AssertTask $task }
if ($Revoke) {
    if ($null -eq $task) { Write-Output 'OWNER_OPS_ENROLL=ALREADY_REVOKED'; return }
    if ([string]$task.State -ceq 'Running') { throw 'OWNER_OPS_ENROLL_REVOKE_RUNNING_HOLD' }
    Disable-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop | Out-Null
    Unregister-ScheduledTask -TaskName $name -TaskPath '\' -Confirm:$false -ErrorAction Stop
    Write-Output 'OWNER_OPS_ENROLL=TASK_REVOKED_PRIVATE_LOGS_PRESERVED'
    return
}
if (-not $Enroll) {
    Write-Output ('OWNER_OPS_ENROLL=' + $(if ($null -eq $task) {
        'HOSTOPS_SETUP_REQUIRED'
    } else { 'REGISTERED_NOT_RUN' }))
    Write-Output ('OWNER_OPS_OWNER_AGENT=' + [string]$oldTask.State + '_UNCHANGED')
    return
}
if (-not (Test-Path -LiteralPath $root -PathType Container) -or
    ((Get-Item -LiteralPath $root -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint)) {
    throw 'OWNER_OPS_ENROLL_OWNER_ROOT_INVALID'
}
[IO.Directory]::CreateDirectory($maintenance) | Out-Null
$download = Join-Path $env:TEMP ('ttv-owner-laptop-ops-helper-' +
    [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $SourceCommit + '/hostops/setup/owner-laptop-ops-helper.ps1'
    Invoke-WebRequest -Uri $uri -OutFile $download -ErrorAction Stop
    $expected = $ExpectedHelperSha256.ToLowerInvariant()
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
        throw 'OWNER_OPS_ENROLL_HELPER_SOURCE_HASH_MISMATCH'
    }
    if (Test-Path -LiteralPath $helper) {
        if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
            throw 'OWNER_OPS_ENROLL_EXISTING_HELPER_DIFFERENT_REVIEW_UPGRADE'
        }
    } else {
        [IO.File]::Copy($download,$helper,$false)
        & icacls.exe $helper /inheritance:r /grant:r `
            "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_OPS_ENROLL_HELPER_ACL_FAILED' }
    }

    foreach ($folder in @($requestDir,$receiptDir,$historyDir)) {
        [IO.Directory]::CreateDirectory($folder) | Out-Null
        if (((Get-Item -LiteralPath $folder -Force).Attributes -band
                [IO.FileAttributes]::ReparsePoint)) {
            throw 'OWNER_OPS_ENROLL_SPOOL_REPARSE_FORBIDDEN'
        }
    }
    foreach ($folder in @($requestDir,$historyDir)) {
        & icacls.exe $folder /inheritance:r /grant:r `
            "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' `
            '*S-1-5-20:(OI)(CI)M' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_OPS_ENROLL_REQUEST_ACL_FAILED' }
    }
    & icacls.exe $receiptDir /inheritance:r /grant:r `
        "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-20:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_OPS_ENROLL_RECEIPT_ACL_FAILED' }

    if ($null -eq $task) {
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $arguments
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name `
            -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $definition = New-ScheduledTask -Action $action -Principal $principal `
            -Settings $settings -Description $description
        Register-ScheduledTask -TaskName $name -TaskPath '\' `
            -InputObject $definition -ErrorAction Stop | Out-Null
        $task = Get-ScheduledTask -TaskName $name -TaskPath '\'
    }
    AssertTask $task
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($name)
    $before = [string]$registered.GetSecurityDescriptor(4)
    $acl = [Security.AccessControl.RawSecurityDescriptor]::new($before)
    $count = 0
    foreach ($ace in $acl.DiscretionaryAcl) {
        if ($ace.SecurityIdentifier.Value -ceq 'S-1-5-20') {
            if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
                $ace.AccessMask -notin @(-1610612736,0x001200a9)) {
                throw 'OWNER_OPS_ENROLL_UNEXPECTED_SERVICE_TASK_RIGHT'
            }
            $count++
        }
    }
    if ($count -gt 1) { throw 'OWNER_OPS_ENROLL_DUPLICATE_SERVICE_ACE' }
    if ($count -eq 0) { $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)',0) }
    Write-Output 'OWNER_OPS_ENROLL=REGISTERED_NOT_RUN'
    Write-Output 'OWNER_OPS_HELPER_SHA256=VERIFIED'
    Write-Output 'OWNER_OPS_SERVICE=TASK_RX_REQUEST_WRITE_RECEIPT_READ'
    Write-Output ('OWNER_OPS_OWNER_AGENT=' + [string]$oldTask.State + '_UNCHANGED')
    Write-Output 'OWNER_OPS_PROVIDER_TV=NOT_RUN_BY_ENROLLMENT'
} finally {
    if (Test-Path -LiteralPath $download -PathType Leaf) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
}
