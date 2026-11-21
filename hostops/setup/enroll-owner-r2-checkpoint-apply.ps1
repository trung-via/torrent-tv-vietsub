# One-time signed-in Owner enrollment. The separate no-trigger task installs
# exactly five fixed R2/P4 files only after a fresh owner-authorized HostOps
# dispatch. No service token ever gains access to Owner-private files.
[CmdletBinding(DefaultParameterSetName='Inspect')]
param(
    [Parameter(ParameterSetName='Enroll')][switch]$Enroll,
    [Parameter(ParameterSetName='Enroll',Mandatory=$true)]
    [ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [Parameter(ParameterSetName='Revoke')][switch]$Revoke
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-Owner-R2-Checkpoint-Apply'
$description = 'TTV_OWNER_CHECKPOINT_APPLY_ONCE_20261121'
$helperSHA = '5effe01d34d3a8d25c5df569bf6279c787aaab2c52cf153cf19c33ea1e987814'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$maintenance = Join-Path $root 'Maintenance'
$helper = Join-Path $maintenance 'owner-r2-checkpoint-apply-once.ps1'
$originalLauncher = Join-Path $root 'start-owner-session-agent.ps1'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_CHECKPOINT_ENROLL_INTERACTIVE_OWNER_REQUIRED'
}
$pwsh = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.Path]::GetFileName($pwsh).Equals('pwsh.exe',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_CHECKPOINT_ENROLL_PWSH7_REQUIRED'
}
foreach ($path in @($root,$maintenance)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_CHECKPOINT_ENROLL_DIRECTORY_MISSING_OR_REPARSE'
    }
}
if (-not (Test-Path -LiteralPath $originalLauncher -PathType Leaf)) {
    throw 'OWNER_CHECKPOINT_ENROLL_ORIGINAL_LAUNCHER_MISSING'
}
$original = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
function TaskSid($task) {
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    return $sid
}
if ((TaskSid $original) -cne $identity.User.Value -or
    [string]$original.Principal.LogonType -ine 'Interactive' -or
    @($original.Actions).Count -ne 1 -or
    -not [IO.Path]::GetFileName([string]$original.Actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    [string]$original.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    throw 'OWNER_CHECKPOINT_ENROLL_ORIGINAL_TASK_DRIFT'
}
function AssertTask($task) {
    if ($null -eq $task) { throw 'OWNER_CHECKPOINT_ENROLL_TASK_MISSING' }
    $triggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
    if ([string]$task.Description -cne $description -or
        (TaskSid $task) -cne $identity.User.Value -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        [string]$task.Principal.RunLevel -ine 'Limited' -or
        $triggers -ne 0 -or @($task.Actions).Count -ne 1 -or
        [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
        -not [IO.Path]::GetFullPath([string]$task.Actions[0].Execute).Equals(
            [IO.Path]::GetFullPath($pwsh),[StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::IsNullOrWhiteSpace([string]$task.Actions[0].WorkingDirectory) -or
        [string]$task.Actions[0].Arguments -cne
            ('-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"')) {
        throw 'OWNER_CHECKPOINT_ENROLL_TASK_DRIFT'
    }
}
$existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
if ($null -ne $existing) { AssertTask $existing }
if ($Revoke) {
    if ($null -eq $existing) { Write-Output 'OWNER_CHECKPOINT_ENROLL=ALREADY_REVOKED'; return }
    if ([string]$existing.State -ceq 'Running') { throw 'OWNER_CHECKPOINT_ENROLL_TASK_RUNNING' }
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
    Write-Output 'OWNER_CHECKPOINT_ENROLL=TASK_REVOKED_PRIVATE_RECOVERY_PRESERVED'
    return
}
if (-not $Enroll) {
    Write-Output ('OWNER_CHECKPOINT_ENROLL=' + $(if ($null -eq $existing) {
        'HOSTOPS_SETUP_REQUIRED' } else { 'TASK_REGISTERED' }))
    return
}
if ([string]$original.State -cne 'Running') {
    throw 'OWNER_CHECKPOINT_ENROLL_ORIGINAL_OWNER_NOT_RUNNING'
}
$download = Join-Path $env:TEMP ('ttv-checkpoint-helper-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $url = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $SourceCommit + '/hostops/setup/owner-r2-checkpoint-apply-once.ps1'
    Invoke-WebRequest -Uri $url -OutFile $download -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $helperSHA) { throw 'OWNER_CHECKPOINT_ENROLL_HELPER_HASH_MISMATCH' }
    if (Test-Path -LiteralPath $helper) {
        if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $helperSHA) { throw 'OWNER_CHECKPOINT_ENROLL_EXISTING_HELPER_DRIFT' }
    } else {
        [IO.File]::Copy($download,$helper,$false)
        & icacls.exe $helper /inheritance:r /grant:r `
            "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_CHECKPOINT_ENROLL_HELPER_ACL_FAILED' }
    }
    if ($null -eq $existing) {
        $action = New-ScheduledTaskAction -Execute $pwsh `
            -Argument ('-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"')
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name `
            -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 4) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $definition = New-ScheduledTask -Action $action -Principal $principal `
            -Settings $settings -Description $description
        Register-ScheduledTask -TaskName $taskName -TaskPath '\' `
            -InputObject $definition -ErrorAction Stop | Out-Null
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    }
    AssertTask $existing
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($taskName)
    $before = [string]$registered.GetSecurityDescriptor(4)
    if (-not $before.StartsWith('D:',[StringComparison]::Ordinal) -or
        $before -match 'S:' -or $before -match 'O:' -or $before -match 'G:') {
        throw 'OWNER_CHECKPOINT_ENROLL_TASK_DACL_INVALID'
    }
    function CountServiceAce([string]$sddl) {
        $acl = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
        $found = 0
        foreach ($ace in $acl.DiscretionaryAcl) {
            if ($ace.SecurityIdentifier.Value -ceq 'S-1-5-20') {
                if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
                    $ace.AccessMask -notin @(-1610612736,0x001200A9)) {
                    throw 'OWNER_CHECKPOINT_ENROLL_UNEXPECTED_SERVICE_GRANT'
                }
                $found++
            }
        }
        return $found
    }
    $count = CountServiceAce $before
    if ($count -gt 1) { throw 'OWNER_CHECKPOINT_ENROLL_DUPLICATE_SERVICE_ACE' }
    if ($count -eq 0) { $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)',0) }
    if ((CountServiceAce ([string]$registered.GetSecurityDescriptor(4))) -ne 1) {
        throw 'OWNER_CHECKPOINT_ENROLL_SERVICE_TASK_RX_NOT_VERIFIED'
    }
    Write-Output 'OWNER_CHECKPOINT_ENROLL=REGISTERED_NO_TRIGGER_NOT_RUN'
    Write-Output 'OWNER_CHECKPOINT_ENROLL_HELPER=SHA256_VERIFIED'
    Write-Output 'OWNER_CHECKPOINT_ENROLL_OWNER_AGENT=UNCHANGED'
} finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
}
