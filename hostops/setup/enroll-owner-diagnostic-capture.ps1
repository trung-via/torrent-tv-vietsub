# One-time Owner-interactive enrollment of a repeatable, READ-ONLY snapshot.
# No OwnerAgent restart, queue mutation, provider call or TV interaction.
# HostOps gets execute access to this exact Task, NOT to Owner-private files.
[CmdletBinding(DefaultParameterSetName = 'Inspect')]
param(
    [Parameter(ParameterSetName = 'Enroll')][switch]$Enroll,
    [Parameter(ParameterSetName = 'Revoke')][switch]$Revoke
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'TorrentTV-Vietsub-Owner-Diagnostic-Capture'
$ownerTaskName = 'TorrentTV-Vietsub-OwnerAgent'
$taskDescription = 'TTV_OWNER_HOSTOPS_P3_P2_CAPTURE_READONLY_V1'
$sourceCommit = '02a8dc3a6a53c6386fe84c22fb7a44348fe37289'
$sourceRoot = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' + $sourceCommit
$pinnedFiles = [ordered]@{
    'poc/p2-sub-discovery/owner-task-principal-identity.ps1' = '9fd3c43f10cf9694d6ecc396aae6a3e6fc724a51750c7d51a2d287d431f778d9'
    'poc/p2-sub-discovery/owner-task-action-identity.ps1' = 'f3c497123af4d38c806aa631684e0a77fa926285c4d31ccba8d88f802cb27caf'
    'hostops/setup/owner-p2-snapshot-once.ps1' = '5ea41dfbcddd4b447dc1bf839a3048654e89f1a2c31a6e50fe3945ae70a753f4'
}
$expectedHelperHash = $pinnedFiles['hostops/setup/owner-p2-snapshot-once.ps1']
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true' -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_DIAG_ENROLL_INTERACTIVE_OWNER_REQUIRED'
}
$pwsh = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.File]::Exists($pwsh) -or
    -not [IO.Path]::GetFileName($pwsh).Equals('pwsh.exe', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_DIAG_ENROLL_PWSH7_REQUIRED'
}

$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$maintenance = Join-Path $ownerRoot 'Maintenance'
$helper = Join-Path $maintenance 'owner-p2-snapshot-once.ps1'
$launcher = Join-Path $ownerRoot 'start-owner-session-agent.ps1'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics'
foreach ($path in @($ownerRoot, $launcher, $spool)) {
    if (-not (Test-Path -LiteralPath $path) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_DIAG_ENROLL_REQUIRED_PATH_MISSING_OR_REPARSE'
    }
}
if (-not (Test-Path -LiteralPath $ownerRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $launcher -PathType Leaf) -or
    -not (Test-Path -LiteralPath $spool -PathType Container)) {
    throw 'OWNER_DIAG_ENROLL_REQUIRED_PATH_TYPE'
}

$stage = Join-Path $env:TEMP ('TorrentTV-Owner-Diag-Enroll-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stage -ErrorAction Stop)
try {
    foreach ($path in $pinnedFiles.Keys) {
        $destination = Join-Path $stage $path
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force)
        Invoke-WebRequest -Uri ($sourceRoot + '/' + $path) -OutFile $destination -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine
            $pinnedFiles[$path]) {
            throw 'OWNER_DIAG_ENROLL_SOURCE_HASH_MISMATCH'
        }
    }
    . (Join-Path $stage 'poc/p2-sub-discovery/owner-task-principal-identity.ps1')
    . (Join-Path $stage 'poc/p2-sub-discovery/owner-task-action-identity.ps1')

    $original = Get-ScheduledTask -TaskName $ownerTaskName -TaskPath '\' -ErrorAction Stop
    if (-not (Test-TTVOwnerTaskPrincipal -Principal $original.Principal `
            -ExpectedSid $identity.User.Value) -or
        -not (Get-TTVOwnerTaskActionState -Task $original `
            -ExpectedExecutable $pwsh -ExpectedLauncher $launcher).Accepted) {
        throw 'OWNER_DIAG_ENROLL_OWNER_TASK_IDENTITY_DRIFT'
    }

    function AssertCaptureTask($Task) {
        $triggerCount = if ($null -eq $Task.Triggers) { 0 } else { @($Task.Triggers).Count }
        if ([string]$Task.Description -cne $taskDescription -or
            -not (Test-TTVOwnerTaskPrincipal -Principal $Task.Principal `
                -ExpectedSid $identity.User.Value) -or
            [string]$Task.Principal.LogonType -ine 'Interactive' -or
            [string]$Task.Principal.RunLevel -ine 'Limited' -or
            $triggerCount -ne 0 -or
            [string]$Task.Settings.MultipleInstances -ine 'IgnoreNew' -or
            -not (Get-TTVOwnerTaskActionState -Task $Task `
                -ExpectedExecutable $pwsh -ExpectedLauncher $helper).Accepted) {
            throw 'OWNER_DIAG_ENROLL_CAPTURE_TASK_DRIFT'
        }
    }

    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($null -ne $existing) { AssertCaptureTask $existing }
    if ($Revoke) {
        if ($null -eq $existing) {
            Write-Output 'OWNER_DIAG_ENROLL_REVOKE=ALREADY_ABSENT'
            return
        }
        if ([string]$existing.State -ceq 'Running') {
            throw 'OWNER_DIAG_ENROLL_REVOKE_RUNNING_HOLD'
        }
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' `
            -Confirm:$false -ErrorAction Stop
        Write-Output 'OWNER_DIAG_ENROLL_REVOKE=TASK_REMOVED_HELPER_PRESERVED'
        Write-Output 'OWNER_DIAG_ENROLL_OWNER_TASK=UNCHANGED'
        return
    }
    if (-not $Enroll) {
        Write-Output ('OWNER_DIAG_ENROLL_STATUS=' + $(if ($null -eq $existing) {
            'HOSTOPS_SETUP_REQUIRED'
        } else { 'TASK_REGISTERED' }))
        Write-Output 'OWNER_DIAG_ENROLL_PROVIDER_TV=NOT_RUN'
        return
    }
    if ([string]$original.State -cne 'Running') {
        throw 'OWNER_DIAG_ENROLL_ORIGINAL_OWNER_NOT_RUNNING'
    }

    if (Test-Path -LiteralPath $maintenance) {
        if (-not (Test-Path -LiteralPath $maintenance -PathType Container) -or
            ((Get-Item -LiteralPath $maintenance -Force).Attributes -band
                [IO.FileAttributes]::ReparsePoint)) {
            throw 'OWNER_DIAG_ENROLL_MAINTENANCE_UNTRUSTED'
        }
    } else {
        [void](New-Item -ItemType Directory -Path $maintenance -ErrorAction Stop)
        & icacls.exe $maintenance /inheritance:r /grant:r `
            "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_DIAG_ENROLL_PRIVATE_DIR_ACL_FAILED' }
    }
    if (Test-Path -LiteralPath $helper) {
        if (-not (Test-Path -LiteralPath $helper -PathType Leaf) -or
            ((Get-Item -LiteralPath $helper -Force).Attributes -band
                [IO.FileAttributes]::ReparsePoint) -or
            (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -ine $expectedHelperHash) {
            throw 'OWNER_DIAG_ENROLL_HELPER_DRIFT'
        }
    } else {
        Copy-Item -LiteralPath (Join-Path $stage 'hostops/setup/owner-p2-snapshot-once.ps1') `
            -Destination $helper -ErrorAction Stop
        & icacls.exe $helper /inheritance:r /grant:r `
            "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_DIAG_ENROLL_HELPER_ACL_FAILED' }
    }

    if ($null -eq $existing) {
        $args = '-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"'
        $action = New-ScheduledTaskAction -Execute $pwsh -Argument $args
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name `
            -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 3) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $definition = New-ScheduledTask -Action $action -Principal $principal `
            -Settings $settings -Description $taskDescription
        Register-ScheduledTask -TaskName $taskName -TaskPath '\' `
            -InputObject $definition -ErrorAction Stop | Out-Null
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    }
    AssertCaptureTask $existing

    # Only task-specific read+execute. Never expose private OwnerBridge ACLs.
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($taskName)
    $before = [string]$registered.GetSecurityDescriptor(4)
    if (-not $before.StartsWith('D:', [StringComparison]::Ordinal) -or
        $before -match 'S:' -or $before -match 'O:' -or $before -match 'G:') {
        throw 'OWNER_DIAG_ENROLL_TASK_DACL_INVALID'
    }
    $nsSid = 'S-1-5-20'
    $masks = @(-1610612736, 0x001200A9) # GRGX or Windows-mapped read+execute
    function CountExpectedAce([string]$Sddl) {
        $count = 0
        $parsed = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
        foreach ($ace in $parsed.DiscretionaryAcl) {
            if ($ace -isnot [Security.AccessControl.QualifiedAce]) {
                throw 'OWNER_DIAG_ENROLL_UNSUPPORTED_ACE'
            }
            if ($ace.SecurityIdentifier.Value -ceq $nsSid) {
                if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
                    $ace.AccessMask -notin $masks) {
                    throw 'OWNER_DIAG_ENROLL_UNEXPECTED_NETWORKSERVICE_GRANT'
                }
                $count++
            }
        }
        return $count
    }
    $count = CountExpectedAce $before
    if ($count -gt 1) { throw 'OWNER_DIAG_ENROLL_DUPLICATE_NETWORKSERVICE_GRANT' }
    if ($count -eq 0) { $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)', 0) }
    $after = [string]$registered.GetSecurityDescriptor(4)
    if ((CountExpectedAce $after) -ne 1) {
        throw 'OWNER_DIAG_ENROLL_NETWORKSERVICE_RX_NOT_VERIFIED'
    }

    Write-Output 'OWNER_DIAG_ENROLL_STATUS=REGISTERED_NOT_RUN'
    Write-Output 'OWNER_DIAG_ENROLL_NETWORKSERVICE=TASK_READ_EXECUTE_ONLY'
    Write-Output 'OWNER_DIAG_ENROLL_HELPER_SHA256=VERIFIED'
    Write-Output 'OWNER_DIAG_ENROLL_OWNER_TASK=RUNNING_UNCHANGED'
    Write-Output 'OWNER_DIAG_ENROLL_PROVIDER_TV=NOT_RUN'
} finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
