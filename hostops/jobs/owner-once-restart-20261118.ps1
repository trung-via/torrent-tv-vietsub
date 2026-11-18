# One-shot, owner-requested restart via the existing registered Windows task.
# Runs under the dedicated Torrent TV HostOps runner. Never changes task
# registration, permissions, owner files, credentials, queues or provider state.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_OWNER_ONCE_INVALID_HOSTOPS_CONTEXT'
}
$name = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
$actions = @($task.Actions)
$info = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
Write-Host 'TTV_OWNER_ONCE=REQUESTED_ONE_ATTEMPT'
Write-Host ('TTV_OWNER_BEFORE_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_OWNER_BEFORE_LAST_RESULT=' + [string]$info.LastTaskResult)
if ($task.State -ne 'Ready' -or
    [string]$task.Principal.LogonType -ne 'Interactive' -or
    $actions.Count -ne 1 -or
    [string]$actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    Write-Host 'TTV_OWNER_START_RESULT=HOLD_TASK_CONTRACT'
    throw 'TTV_OWNER_ONCE_TASK_CONTRACT_HOLD'
}
# Do not use the service runner identity to access owner-only resources.
# The task must already be registered for the currently signed-in owner.
$console = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($console)) {
    Write-Host 'TTV_OWNER_START_RESULT=HOLD_NO_SIGNED_IN_OWNER'
    throw 'TTV_OWNER_ONCE_NO_SIGNED_IN_OWNER'
}
try {
    $configured = [string]$task.Principal.UserId
    $principalSid = if ($configured -match '^S-1-') {
        $configured
    } else {
        ([Security.Principal.NTAccount]::new($configured)).Translate(
            [Security.Principal.SecurityIdentifier]).Value
    }
    $consoleSid = ([Security.Principal.NTAccount]::new($console)).Translate(
        [Security.Principal.SecurityIdentifier]).Value
    if ($principalSid -cne $consoleSid) {
        Write-Host 'TTV_OWNER_START_RESULT=HOLD_LOGGED_ON_USER_MISMATCH'
        throw 'TTV_OWNER_ONCE_LOGGED_ON_USER_MISMATCH'
    }
} catch {
    if ($_.Exception.Message -eq 'TTV_OWNER_ONCE_LOGGED_ON_USER_MISMATCH') { throw }
    Write-Host 'TTV_OWNER_START_RESULT=HOLD_OWNER_IDENTITY_UNVERIFIED'
    throw 'TTV_OWNER_ONCE_OWNER_IDENTITY_UNVERIFIED'
}
function Get-OwnerPyProcesses {
    $all = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
    $unknown = @($all | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.CommandLine)
    })
    if ($unknown.Count -gt 0) {
        Write-Host 'TTV_OWNER_START_RESULT=HOLD_PROCESS_IDENTITY_UNVERIFIED'
        throw 'TTV_OWNER_ONCE_PYTHON_IDENTITY_UNVERIFIED'
    }
    return @($all | Where-Object {
        [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
$before = @(Get-OwnerPyProcesses)
Write-Host ('TTV_OWNER_BEFORE_PROCESS_COUNT=' + $before.Count)
if ($before.Count -gt 0) {
    Write-Host 'TTV_OWNER_START_RESULT=ALREADY_RUNNING_NO_DUPLICATE'
    exit 0
}
try {
    Start-ScheduledTask -TaskName $name -ErrorAction Stop
} catch {
    Write-Host ('TTV_OWNER_START_ERROR_TYPE=' + $_.Exception.GetType().Name)
    Write-Host 'TTV_OWNER_START_RESULT=DENIED_OR_FAILED_BY_TASK_SCHEDULER'
    throw 'TTV_OWNER_ONCE_SCHEDULER_START_FAILED'
}
Write-Host 'TTV_OWNER_START_REQUEST=ACCEPTED'
$found = $false
for ($n = 0; $n -lt 6; $n++) {
    Start-Sleep -Seconds 4
    $active = @(Get-OwnerPyProcesses)
    if ($active.Count -gt 0) {
        $found = $true
        break
    }
}
$finalTask = Get-ScheduledTask -TaskName $name -ErrorAction Stop
$finalInfo = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
Write-Host ('TTV_OWNER_AFTER_TASK_STATE=' + [string]$finalTask.State)
Write-Host ('TTV_OWNER_AFTER_LAST_RESULT=' + [string]$finalInfo.LastTaskResult)
Write-Host ('TTV_OWNER_AFTER_PROCESS_COUNT=' + $active.Count)
if ($found) {
    Write-Host 'TTV_OWNER_START_RESULT=PYTHON_PROCESS_OBSERVED_HEARTBEAT_NOT_VERIFIED'
    exit 0
}
Write-Host 'TTV_OWNER_START_RESULT=FAILED_NO_OWNER_PROCESS_AFTER_ONE_ATTEMPT'
throw 'TTV_OWNER_ONCE_NO_LIVE_PROCESS'
