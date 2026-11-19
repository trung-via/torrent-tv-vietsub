# One-time Owner-interactive registration of the reusable HostOps STAGE-ONLY
# task. It does NOT replace/restart Owner or run Gemini/OpenSubtitles/TV.
# Run -Enroll once with the reviewed exact repository commit containing the
# pinned helper; future HostOps requests use this same immutable task action.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Enroll')][switch]$Enroll,
    [Parameter(ParameterSetName = 'Enroll', Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')][string]$SourceCommit,
    [Parameter(ParameterSetName = 'Revoke')][switch]$Revoke
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskName = 'TorrentTV-Vietsub-Owner-Release-Stage'
$description = 'TTV_OWNER_HOSTOPS_RELEASE_STAGE_ONLY_V1'
$helperSHA = 'f606ec73370faf3cf108ae9a9765c362de7ccbfef506a65eb76be257f7b195b1'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true' -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_RELEASE_ENROLL_INTERACTIVE_OWNER_REQUIRED'
}
$pwsh = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.Path]::GetFileName($pwsh).Equals('pwsh.exe',
    [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_RELEASE_ENROLL_PWSH7_REQUIRED'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$maintenance = Join-Path $root 'Maintenance'
$helper = Join-Path $maintenance 'owner-release-stage-helper.ps1'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge'
$requestDir = Join-Path $spool 'ReleaseRequests'
$receiptDir = Join-Path $spool 'ReleaseReceipts'
foreach ($path in @($root, $launcher, $spool)) {
    if (-not (Test-Path -LiteralPath $path) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_RELEASE_ENROLL_REQUIRED_PATH_MISSING_OR_REPARSE'
    }
}

$original = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$ownerSid = [string]$original.Principal.UserId
if ($ownerSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $ownerSid = ([Security.Principal.NTAccount]::new($ownerSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($ownerSid -cne $identity.User.Value -or
    [string]$original.Principal.LogonType -ine 'Interactive' -or
    @($original.Actions).Count -ne 1 -or
    -not [string]::IsNullOrWhiteSpace([string]$original.Actions[0].WorkingDirectory) -or
    -not [IO.Path]::GetFileName([string]$original.Actions[0].Execute).Equals('pwsh.exe',
        [StringComparison]::OrdinalIgnoreCase) -or
    [string]$original.Actions[0].Arguments -notmatch
        '(?i)start-owner-session-agent\.ps1') {
    throw 'OWNER_RELEASE_ENROLL_ORIGINAL_TASK_IDENTITY_DRIFT'
}

function AssertReleaseTask($task) {
    if ($null -eq $task) { throw 'OWNER_RELEASE_ENROLL_TASK_MISSING' }
    $triggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
    $principalSid = [string]$task.Principal.UserId
    if ($principalSid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $principalSid = ([Security.Principal.NTAccount]::new($principalSid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    $actions = @($task.Actions)
    if ([string]$task.Description -cne $description -or
        $principalSid -cne $identity.User.Value -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        [string]$task.Principal.RunLevel -ine 'Limited' -or
        $triggers -ne 0 -or $actions.Count -ne 1 -or
        [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
        -not [IO.Path]::GetFullPath([string]$actions[0].Execute).Equals(
            [IO.Path]::GetFullPath($pwsh), [StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::IsNullOrWhiteSpace([string]$actions[0].WorkingDirectory) -or
        [string]$actions[0].Arguments -cne ('-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"')) {
        throw 'OWNER_RELEASE_ENROLL_TASK_DRIFT'
    }
}

$existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
if ($null -ne $existing) { AssertReleaseTask $existing }
if ($Revoke) {
    if ($null -eq $existing) {
        Write-Output 'OWNER_RELEASE_ENROLL_REVOKE=ALREADY_ABSENT'
        return
    }
    if ([string]$existing.State -ceq 'Running') {
        throw 'OWNER_RELEASE_ENROLL_REVOKE_RUNNING_HOLD'
    }
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' `
        -Confirm:$false -ErrorAction Stop
    Write-Output 'OWNER_RELEASE_ENROLL_REVOKE=TASK_ONLY_HELPER_AND_STAGES_PRESERVED'
    return
}
if (-not $Enroll) {
    Write-Output ('OWNER_RELEASE_ENROLL_STATUS=' + $(if ($null -eq $existing) {
        'HOSTOPS_SETUP_REQUIRED'
    } else { 'TASK_REGISTERED' }))
    Write-Output 'OWNER_RELEASE_ENROLL_ORIGINAL_TASK=UNCHANGED'
    return
}
if ([string]$original.State -cne 'Running') {
    throw 'OWNER_RELEASE_ENROLL_ORIGINAL_OWNER_NOT_RUNNING'
}
if (-not (Test-Path -LiteralPath $maintenance -PathType Container) -or
    ((Get-Item -LiteralPath $maintenance -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint)) {
    throw 'OWNER_RELEASE_ENROLL_PRIVATE_MAINTENANCE_REQUIRED'
}

$download = Join-Path $env:TEMP ('ttv-release-helper-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $url = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $SourceCommit + '/hostops/setup/owner-release-stage-helper.ps1'
    Invoke-WebRequest -Uri $url -OutFile $download -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $helperSHA) {
        throw 'OWNER_RELEASE_ENROLL_PINNED_HELPER_MISMATCH'
    }
    if (Test-Path -LiteralPath $helper) {
        if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $helperSHA) {
            throw 'OWNER_RELEASE_ENROLL_EXISTING_HELPER_DRIFT'
        }
    } else {
        [IO.File]::Copy($download,$helper,$false)
        & icacls.exe $helper /inheritance:r /grant:r `
            "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_RELEASE_ENROLL_HELPER_ACL_FAILED' }
    }

    foreach ($folder in @($requestDir,$receiptDir)) {
        if (-not (Test-Path -LiteralPath $folder)) {
            New-Item -ItemType Directory -Path $folder -ErrorAction Stop | Out-Null
        }
        if (-not (Test-Path -LiteralPath $folder -PathType Container) -or
            ((Get-Item -LiteralPath $folder -Force).Attributes -band
                [IO.FileAttributes]::ReparsePoint)) {
            throw 'OWNER_RELEASE_ENROLL_SPOOL_DIRECTORY_DRIFT'
        }
    }
    & icacls.exe $requestDir /inheritance:r /grant:r `
        "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-20:(OI)(CI)M' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_RELEASE_ENROLL_INBOX_ACL_FAILED' }
    & icacls.exe $receiptDir /inheritance:r /grant:r `
        "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' `
        '*S-1-5-20:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_RELEASE_ENROLL_RECEIPT_ACL_FAILED' }

    if ($null -eq $existing) {
        $action = New-ScheduledTaskAction -Execute $pwsh `
            -Argument ('-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"')
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name `
            -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $definition = New-ScheduledTask -Action $action -Principal $principal `
            -Settings $settings -Description $description
        Register-ScheduledTask -TaskName $taskName -TaskPath '\' `
            -InputObject $definition -ErrorAction Stop | Out-Null
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    }
    AssertReleaseTask $existing
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($taskName)
    $before = [string]$registered.GetSecurityDescriptor(4)
    if (-not $before.StartsWith('D:',[StringComparison]::Ordinal) -or
        $before -match 'S:' -or $before -match 'O:' -or $before -match 'G:') {
        throw 'OWNER_RELEASE_ENROLL_TASK_DACL_INVALID'
    }
    $masks = @(-1610612736,0x001200A9)
    function CountServiceAce([string]$sddl) {
        $count = 0
        $acl = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
        foreach ($ace in $acl.DiscretionaryAcl) {
            if ($ace.SecurityIdentifier.Value -ceq 'S-1-5-20') {
                if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
                    $ace.AccessMask -notin $masks) {
                    throw 'OWNER_RELEASE_ENROLL_UNEXPECTED_SERVICE_GRANT'
                }
                $count++
            }
        }
        return $count
    }
    $count = CountServiceAce $before
    if ($count -gt 1) { throw 'OWNER_RELEASE_ENROLL_DUPLICATE_SERVICE_ACE' }
    if ($count -eq 0) { $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)',0) }
    if ((CountServiceAce ([string]$registered.GetSecurityDescriptor(4))) -ne 1) {
        throw 'OWNER_RELEASE_ENROLL_SERVICE_TASK_RX_NOT_VERIFIED'
    }
    Write-Output 'OWNER_RELEASE_ENROLL_STATUS=REGISTERED_NOT_RUN'
    Write-Output 'OWNER_RELEASE_ENROLL_HELPER_SHA256=VERIFIED'
    Write-Output 'OWNER_RELEASE_ENROLL_SERVICE=TASK_RX_INBOX_WRITE_RECEIPT_READ'
    Write-Output 'OWNER_RELEASE_ENROLL_OWNER_AGENT=RUNNING_UNCHANGED'
    Write-Output 'OWNER_RELEASE_ENROLL_PROVIDER_TV=NOT_RUN'
} finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
}
