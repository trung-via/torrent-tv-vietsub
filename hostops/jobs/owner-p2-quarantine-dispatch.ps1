# Fixed HostOps capability: trigger ONE already-enrolled interactive Owner
# preservation task. No service access to Owner profile, P2 marker or DPAPI.
# The Owner Task itself performs exact live no-retry/marker preflight and leaves
# TorrentTV-Vietsub-OwnerAgent disabled for separately reviewed restart.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'HOSTOPS_P2_QUARANTINE_TRUSTED_NETWORKSERVICE_REQUIRED'
}

$taskName = 'TorrentTV-Vietsub-P2-Quarantine-Once'
$description = 'TTV_OWNER_P2_BATCH_0001_QUARANTINE_ONCE_V1'
function Get-TaskPrincipalSid {
    param([object]$Principal)
    if ([string]::IsNullOrWhiteSpace([string]$Principal.UserId)) {
        throw 'HOSTOPS_P2_QUARANTINE_PRINCIPAL_MISSING'
    }
    $id = ([string]$Principal.UserId).Trim()
    try {
        if ($id -match '^S-\d+(?:-\d+){2,}$') {
            return ([Security.Principal.SecurityIdentifier]::new($id)).Value
        }
        return ([Security.Principal.NTAccount]::new($id).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    } catch {
        throw 'HOSTOPS_P2_QUARANTINE_PRINCIPAL_UNRESOLVABLE'
    }
}
$ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' `
    -TaskPath '\' -ErrorAction Stop
if ([string]$ownerTask.State -cne 'Running') {
    throw 'HOSTOPS_P2_QUARANTINE_ORIGINAL_OWNER_TASK_NOT_RUNNING'
}

try {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
} catch {
    Write-Output 'HOSTOPS_P2_QUARANTINE_ENROLLMENT=HOSTOPS_SETUP_REQUIRED'
    throw 'HOSTOPS_P2_QUARANTINE_DEDICATED_TASK_NOT_ACCESSIBLE'
}
$triggerCount = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
if ([string]$task.State -cne 'Ready' -or
    [string]$task.Description -cne $description -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    $triggerCount -ne 0 -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    @($task.Actions).Count -ne 1) {
    throw 'HOSTOPS_P2_QUARANTINE_TASK_IDENTITY_DRIFT'
}
if ((Get-TaskPrincipalSid $task.Principal) -cne
    (Get-TaskPrincipalSid $ownerTask.Principal)) {
    throw 'HOSTOPS_P2_QUARANTINE_OWNER_PRINCIPAL_MISMATCH'
}
$action = @($task.Actions)[0]
$actualExecutable = [string]$action.Execute
if (-not [IO.Path]::IsPathRooted($actualExecutable) -or
    -not [IO.Path]::GetFileName($actualExecutable).Equals('pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace([string]$action.WorkingDirectory)) {
    throw 'HOSTOPS_P2_QUARANTINE_EXECUTABLE_DRIFT'
}
$args = [string]$action.Arguments
$pattern = '(?i)\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-p2-quarantine-once\.ps1"\z'
if (-not [regex]::IsMatch($args, $pattern)) {
    throw 'HOSTOPS_P2_QUARANTINE_FIXED_ACTION_DRIFT'
}

# LastRunTime is the durable Task Scheduler one-shot gate. A failed earlier
# attempt is STILL an attempt; never retry a possibly committed quarantine.
$history = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
if ($history.LastRunTime -gt [datetime]'2001-01-01') {
    Write-Output 'HOSTOPS_P2_QUARANTINE_DISPATCH=PRIOR_ATTEMPT_HOLD'
    throw 'HOSTOPS_P2_QUARANTINE_ONE_SHOT_ALREADY_ATTEMPTED'
}

Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
Write-Output 'HOSTOPS_P2_QUARANTINE_DISPATCH=OWNER_TASK_TRIGGERED_NOT_VERIFIED'
Write-Output 'HOSTOPS_P2_QUARANTINE_SERVICE_OWNER_PROFILE=NOT_ACCESSED'
Write-Output 'HOSTOPS_P2_QUARANTINE_SERVICE_PROVIDER_TV=NOT_RUN'
Write-Output 'HOSTOPS_P2_QUARANTINE_NEXT=OWNER_RECEIPT_AND_TASK_RESULT_REQUIRED'
