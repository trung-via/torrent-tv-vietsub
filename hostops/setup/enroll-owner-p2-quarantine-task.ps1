# One-time, interactive Owner enrollment for a FIXED P2 preservation task.
# The NetworkService HostOps runner receives task READ+EXECUTE, never Owner
# profile access, arbitrary PowerShell or permission to mutate the task.
# No maintenance runs here. -Revoke unregisters ONLY this dedicated task.
[CmdletBinding()]
param([switch]$Revoke)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$taskName = 'TorrentTV-Vietsub-P2-Quarantine-Once'
$ownerTaskName = 'TorrentTV-Vietsub-OwnerAgent'
$taskDescription = 'TTV_OWNER_P2_BATCH_0001_QUARANTINE_ONCE_V1'
$approvedCommit = '50f282a484dd6ad6104587a914b753e1ed467972'
$approvedHelperHash = 'a21ff672e15db0b2efca20909ae88b35957193f99a52a83a3000dfa65f3d7cb3'

function AssertDedicatedTask {
    param($Task, $Identity, [string]$Pwsh, [string]$Helper, [string]$Description)
    $triggerCount = if ($null -eq $Task -or $null -eq $Task.Triggers) {
        0
    } else { @($Task.Triggers).Count }
    if ($null -eq $Task -or
        [string]$Task.Description -cne $Description -or
        -not (Test-TTVOwnerTaskPrincipal -Principal $Task.Principal -ExpectedSid $Identity.User.Value) -or
        $triggerCount -ne 0 -or
        [string]$Task.Settings.MultipleInstances -ine 'IgnoreNew' -or
        -not (Get-TTVOwnerTaskActionState -Task $Task -ExpectedExecutable $Pwsh `
            -ExpectedLauncher $Helper).Accepted) {
        throw 'OWNER_P2_ENROLL_DEDICATED_TASK_DRIFT'
    }
}

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'OWNER_P2_ENROLL_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_P2_ENROLL_WRONG_SIGNED_IN_OWNER'
}
$currentExecutable = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.Path]::GetFileName($currentExecutable).Equals(
        'pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -or
    -not [IO.File]::Exists($currentExecutable)) {
    throw 'OWNER_P2_ENROLL_PWSH7_REQUIRED'
}

# The existing Owner Task MUST retain its original action and principal.
# Fetch its two pure identity guards from immutable source; no repo checkout.
$sourceRoot = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' + $approvedCommit
$pinnedFiles = [ordered]@{
    'poc/p2-sub-discovery/owner-task-principal-identity.ps1' = '9fd3c43f10cf9694d6ecc396aae6a3e6fc724a51750c7d51a2d287d431f778d9'
    'poc/p2-sub-discovery/owner-task-action-identity.ps1' = 'f3c497123af4d38c806aa631684e0a77fa926285c4d31ccba8d88f802cb27caf'
    'hostops/setup/owner-p2-quarantine-once.ps1' = $approvedHelperHash
}
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$privateDir = Join-Path $ownerRoot 'Maintenance'
$helper = Join-Path $privateDir 'owner-p2-quarantine-once.ps1'
$launcher = Join-Path $ownerRoot 'start-owner-session-agent.ps1'
$args = '-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"'

if (-not (Test-Path -LiteralPath $ownerRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $launcher -PathType Leaf) -or
    ((Get-Item -LiteralPath $ownerRoot).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'OWNER_P2_ENROLL_INSTALLED_OWNER_ROOT_REQUIRED'
}

$originalTask = Get-ScheduledTask -TaskName $ownerTaskName -TaskPath '\' -ErrorAction Stop
if (-not $Revoke -and [string]$originalTask.State -cne 'Running') {
    throw 'OWNER_P2_ENROLL_ORIGINAL_TASK_NOT_RUNNING'
}

$stage = Join-Path $env:TEMP ('TorrentTV-P2-Task-Enroll-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stage -ErrorAction Stop)
try {
    foreach ($path in $pinnedFiles.Keys) {
        $file = Join-Path $stage $path
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force)
        Invoke-WebRequest -Uri ($sourceRoot + '/' + $path) -OutFile $file -ErrorAction Stop
        $actualHash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if (-not $actualHash.Equals($pinnedFiles[$path], [StringComparison]::OrdinalIgnoreCase)) {
            throw 'OWNER_P2_ENROLL_IMMUTABLE_SOURCE_HASH_MISMATCH'
        }
    }
    . (Join-Path $stage 'poc/p2-sub-discovery/owner-task-principal-identity.ps1')
    . (Join-Path $stage 'poc/p2-sub-discovery/owner-task-action-identity.ps1')
    if (-not (Test-TTVOwnerTaskPrincipal -Principal $originalTask.Principal -ExpectedSid $identity.User.Value) -or
        -not (Get-TTVOwnerTaskActionState -Task $originalTask `
            -ExpectedExecutable $currentExecutable -ExpectedLauncher $launcher).Accepted) {
        throw 'OWNER_P2_ENROLL_ORIGINAL_TASK_IDENTITY_MISMATCH'
    }

    # Exact original Owner-private script; no service token can edit it.
    if ($Revoke) {
        $existingForRevoke = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
        if ($null -eq $existingForRevoke) {
            Write-Output 'OWNER_P2_ENROLL_REVOKE=ALREADY_ABSENT'
            return
        }
        AssertDedicatedTask $existingForRevoke $identity $currentExecutable $helper $taskDescription
        if ([string]$existingForRevoke.State -ceq 'Running') {
            throw 'OWNER_P2_ENROLL_REVOKE_ACTIVE_ATTEMPT_HOLD'
        }
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false -ErrorAction Stop
        Write-Output 'OWNER_P2_ENROLL_REVOKE=DEDICATED_TASK_REMOVED'
        Write-Output 'OWNER_P2_ENROLL_ORIGINAL_TASK=UNTOUCHED'
        return
    }

    if (Test-Path -LiteralPath $privateDir) {
        if (-not (Test-Path -LiteralPath $privateDir -PathType Container) -or
            ((Get-Item -LiteralPath $privateDir).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'OWNER_P2_ENROLL_MAINTENANCE_DIR_UNTRUSTED'
        }
    } else {
        [void](New-Item -ItemType Directory -Path $privateDir -ErrorAction Stop)
    }
    & icacls.exe $privateDir /inheritance:r /grant:r `
        "*$($identity.User.Value):(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_P2_ENROLL_PRIVATE_ACL_FAILED' }

    if (Test-Path -LiteralPath $helper) {
        if (((Get-Item -LiteralPath $helper).Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash -ine $approvedHelperHash) {
            throw 'OWNER_P2_ENROLL_INSTALLED_HELPER_DRIFT'
        }
    } else {
        Copy-Item -LiteralPath (Join-Path $stage 'hostops/setup/owner-p2-quarantine-once.ps1') `
            -Destination $helper -ErrorAction Stop
    }
    & icacls.exe $helper /inheritance:r /grant:r `
        "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_P2_ENROLL_HELPER_ACL_FAILED' }

    $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        $action = New-ScheduledTaskAction -Execute $currentExecutable -Argument $args
        $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
            -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        $definition = New-ScheduledTask -Action $action -Principal $principal `
            -Settings $settings -Description $taskDescription
        Register-ScheduledTask -TaskName $taskName -TaskPath '\' -InputObject $definition -ErrorAction Stop | Out-Null
        $existing = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    }
    AssertDedicatedTask $existing $identity $currentExecutable $helper $taskDescription

    # Security descriptor for THIS registered task only. Preserve all existing
    # Owner/SYSTEM/Admin ACEs; only append NetworkService generic R+X.
    $service = New-Object -ComObject 'Schedule.Service'
    $service.Connect()
    $registered = $service.GetFolder('\').GetTask($taskName)
    $before = [string]$registered.GetSecurityDescriptor(4) # DACL_SECURITY_INFORMATION
    if (-not $before.StartsWith('D:', [StringComparison]::Ordinal) -or
        $before -match 'S:' -or $before -match 'O:' -or $before -match 'G:') {
        throw 'OWNER_P2_ENROLL_TASK_DACL_UNEXPECTED'
    }
    $parsed = [Security.AccessControl.RawSecurityDescriptor]::new($before)
    $nsSid = 'S-1-5-20'
    # Windows Task Scheduler maps GR|GX from generic 0xA0000000 to the
    # object-specific file READ|EXECUTE mask 0x001200A9 on roundtrip.
    # Both forms have been checked; NEVER accept write/full-control masks.
    $approvedMasks = @(-1610612736, 0x001200A9)
    $nsAceCount = 0
    foreach ($ace in $parsed.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.QualifiedAce]) {
            throw 'OWNER_P2_ENROLL_TASK_DACL_UNSUPPORTED_ACE'
        }
        if ($null -ne $ace.SecurityIdentifier -and $ace.SecurityIdentifier.Value -ceq $nsSid) {
            $nsAceCount += 1
            if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
                $ace.AccessMask -notin $approvedMasks) {
                throw 'OWNER_P2_ENROLL_UNEXPECTED_NETWORKSERVICE_GRANT'
            }
        }
    }
    if ($nsAceCount -gt 1) { throw 'OWNER_P2_ENROLL_DUPLICATE_NETWORKSERVICE_GRANT' }
    if ($nsAceCount -eq 0) {
        $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)', 0)
    }
    $after = [Security.AccessControl.RawSecurityDescriptor]::new(
        [string]$registered.GetSecurityDescriptor(4))
    $grantCount = 0
    foreach ($ace in $after.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.QualifiedAce]) {
            throw 'OWNER_P2_ENROLL_TASK_DACL_UNSUPPORTED_ACE'
        }
        if ($null -ne $ace.SecurityIdentifier -and $ace.SecurityIdentifier.Value -ceq $nsSid -and
            $ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed -and
            $ace.AccessMask -in $approvedMasks) {
            $grantCount += 1
        }
    }
    if ($grantCount -ne 1) { throw 'OWNER_P2_ENROLL_NETWORKSERVICE_RX_NOT_VERIFIED' }

    Write-Output 'OWNER_P2_ENROLL_STATUS=REGISTERED_NOT_RUN'
    Write-Output 'OWNER_P2_ENROLL_NETWORKSERVICE_RIGHTS=TASK_READ_EXECUTE_ONLY'
    Write-Output 'OWNER_P2_ENROLL_HELPER_SHA256=VERIFIED'
    Write-Output 'OWNER_P2_ENROLL_ORIGINAL_TASK=NOT_MUTATED'
    Write-Output 'OWNER_P2_ENROLL_PROVIDER_TV=NOT_RUN'
}
finally {
    # Only the unique, newly created temporary source stage is removed.
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
