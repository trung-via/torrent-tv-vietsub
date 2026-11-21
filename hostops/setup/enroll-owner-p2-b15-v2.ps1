# One Owner-interactive PowerShell 7 enrollment for the fixed batch15 V2
# operation. Does not start the task, stop Owner or touch private P2 state.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{40}$')]
    [string]$SourceCommit
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$taskName = 'TorrentTV-Vietsub-Owner-P2-B15-FreshStartV2'
$description = 'TTV_OWNER_P2_B15_FRESH_START_V2_ONCE_20261121'
$helperSHA = 'b888a6de741e7e80c3f3e73d25c8aefd96859de7b714e093540f11025d726b93'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$maintenance = Join-Path $root 'Maintenance'
$helper = Join-Path $maintenance 'owner-p2-b15-fresh-start-v2-once.ps1'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($PSVersionTable.PSVersion.Major -ne 7 -or $env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_P2_B15_V2_ENROLL_INTERACTIVE_PWSH7_REQUIRED'
}
$pwsh = [string][Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if (-not [IO.Path]::GetFileName($pwsh).Equals('pwsh.exe',[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_P2_B15_V2_ENROLL_PWSH7_EXE_REQUIRED'
}
foreach ($dir in @($root,$maintenance)) {
    if (-not (Test-Path -LiteralPath $dir -PathType Container) -or
        ((Get-Item -LiteralPath $dir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'OWNER_P2_B15_V2_ENROLL_DIR_INVALID'
    }
}
$original = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$sid = [string]$original.Principal.UserId
if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($sid -cne $identity.User.Value -or
    [string]$original.Principal.LogonType -ine 'Interactive' -or
    [string]$original.State -cne 'Running' -or
    @($original.Actions).Count -ne 1 -or
    [IO.Path]::GetFileName([string]$original.Actions[0].Execute) -ine 'pwsh.exe' -or
    [string]$original.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    throw 'OWNER_P2_B15_V2_ENROLL_OWNER_TASK_DRIFT'
}
if (Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue) {
    throw 'OWNER_P2_B15_V2_ENROLL_ALREADY_REGISTERED_NO_REPLACEMENT'
}
$newReceipt = Join-Path $env:ProgramData `
    'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\p2-batch15-fresh-start-v2.json'
if (Test-Path -LiteralPath $newReceipt) {
    throw 'OWNER_P2_B15_V2_ENROLL_PRIOR_ATTEMPT_NO_REPLAY'
}
$download = Join-Path $env:TEMP ('ttv-b15-v2-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $url = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $SourceCommit + '/hostops/setup/owner-p2-b15-fresh-start-v2-once.ps1'
    Invoke-WebRequest -Uri $url -OutFile $download -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        $helperSHA) { throw 'OWNER_P2_B15_V2_ENROLL_HELPER_HASH_MISMATCH' }
    if (Test-Path -LiteralPath $helper) {
        if ((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne
            $helperSHA) { throw 'OWNER_P2_B15_V2_ENROLL_EXISTING_HELPER_DRIFT' }
    } else {
        [IO.File]::Copy($download,$helper,$false)
        & icacls.exe $helper /inheritance:r /grant:r `
            "*$($identity.User.Value):F" '*S-1-5-18:F' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'OWNER_P2_B15_V2_ENROLL_HELPER_ACL_FAILED' }
    }
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
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
    $triggerCount = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
    if ([string]$task.State -cne 'Ready' -or
        [string]$task.Description -cne $description -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Principal.LogonType -ine 'Interactive' -or
        $triggerCount -ne 0 -or
        [string]$task.Actions[0].Arguments -cne
            ('-NoLogo -NoProfile -NonInteractive -File "' + $helper + '"')) {
        throw 'OWNER_P2_B15_V2_ENROLL_TASK_DRIFT'
    }
    $scheduler = New-Object -ComObject 'Schedule.Service'
    $scheduler.Connect()
    $registered = $scheduler.GetFolder('\').GetTask($taskName)
    $before = [string]$registered.GetSecurityDescriptor(4)
    if (-not $before.StartsWith('D:',[StringComparison]::Ordinal) -or
        $before -match 'S:' -or $before -match 'O:' -or $before -match 'G:') {
        throw 'OWNER_P2_B15_V2_ENROLL_DACL_INVALID'
    }
    $rawAcl = [Security.AccessControl.RawSecurityDescriptor]::new($before)
    $serviceAces = @($rawAcl.DiscretionaryAcl | Where-Object {
        $_.SecurityIdentifier.Value -ceq 'S-1-5-20' })
    if ($serviceAces.Count -gt 1) { throw 'OWNER_P2_B15_V2_ENROLL_SERVICE_ACL_DRIFT' }
    if ($serviceAces.Count -eq 0) {
        $registered.SetSecurityDescriptor($before + '(A;;GRGX;;;NS)',0)
    } else {
        if ($serviceAces[0].AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
            $serviceAces[0].AccessMask -notin @(-1610612736,0x001200A9)) {
            throw 'OWNER_P2_B15_V2_ENROLL_SERVICE_PERMISSION_DRIFT'
        }
    }
    Write-Output 'OWNER_P2_B15_V2_ENROLL=REGISTERED_NO_TRIGGER_NOT_RUN'
    Write-Output 'OWNER_P2_B15_V2_ENROLL_HELPER=SHA256_VERIFIED'
    Write-Output 'OWNER_P2_B15_V2_ENROLL_OWNER_AGENT=UNCHANGED'
} finally {
    if (Test-Path -LiteralPath $download) {
        Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue
    }
}
