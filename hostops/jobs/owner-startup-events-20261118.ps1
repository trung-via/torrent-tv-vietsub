# Owner startup failure: machine-visible, READ-ONLY Windows event evidence.
# No owner-profile reads, credentials, local paths, raw event messages, task/process changes, LAN calls or provider calls.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_STARTUP_EVENTS_RUNNER_MISMATCH'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$ownerMatch = $false
try {
    $raw = [string]$task.Principal.UserId
    $taskSid = if ($raw -match '^S-1-') { $raw } else {
        ([Security.Principal.NTAccount]::new($raw)).Translate(
            [Security.Principal.SecurityIdentifier]).Value
    }
    $ownerMatch = $taskSid -ceq $identity.User.Value
} catch { $ownerMatch = $false }
Write-Host 'TTV_STARTUP_DIAG=READ_ONLY'
Write-Host ('TTV_STARTUP_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_STARTUP_TASK_LAST_RESULT=' + [string]$info.LastTaskResult)
Write-Host ('TTV_STARTUP_LAST_RUN_UTC=' + ([datetime]$info.LastRunTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
Write-Host ('TTV_STARTUP_RUNNER_SAME_OWNER=' + $ownerMatch.ToString().ToUpperInvariant())
Write-Host ('TTV_STARTUP_TASK_ACTION_COUNT=' + @($task.Actions).Count)
$start = ([datetime]$info.LastRunTime).AddMinutes(-3)
$end = ([datetime]$info.LastRunTime).AddMinutes(3)
if ($start.Year -lt 2020 -or $end -gt (Get-Date).AddMinutes(3)) {
    Write-Host 'TTV_STARTUP_EVENT_WINDOW=INVALID_LAST_RUN_TIME'
    exit 0
}
function Probe-EventLog([string]$name, [string]$label, [bool]$onlyTask, [bool]$crashOnly) {
    $meta = $null
    try { $meta = Get-WinEvent -ListLog $name -ErrorAction Stop }
    catch {
        Write-Host ('TTV_STARTUP_' + $label + '_STATUS=UNAVAILABLE')
        return
    }
    if (-not $meta.IsEnabled) {
        Write-Host ('TTV_STARTUP_' + $label + '_STATUS=DISABLED')
        return
    }
    $events = @(Get-WinEvent -FilterHashtable @{
        LogName = $name
        StartTime = $start
        EndTime = $end
    } -ErrorAction SilentlyContinue)
    if ($onlyTask) {
        $events = @($events | Where-Object {
            [string]$_.Message -like ('*' + $taskName + '*')
        })
    }
    if ($crashOnly) {
        $events = @($events | Where-Object {
            $_.Level -le 2 -and
            $_.ProviderName -in @('Application Error','Windows Error Reporting','.NET Runtime','PowerShell')
        })
    }
    if (-not $onlyTask -and -not $crashOnly) {
        $events = @($events | Where-Object { $_.Level -le 2 })
    }
    Write-Host ('TTV_STARTUP_' + $label + '_STATUS=ENABLED')
    Write-Host ('TTV_STARTUP_' + $label + '_EVENT_COUNT=' + $events.Count)
    $ids = @($events | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
    Write-Host ('TTV_STARTUP_' + $label + '_EVENT_IDS=' + $(if ($ids.Count -gt 0) { $ids -join ',' } else { 'NONE' }))
}
Probe-EventLog 'Microsoft-Windows-TaskScheduler/Operational' 'TASK_LOG' $true $false
Probe-EventLog 'PowerShellCore/Operational' 'PWSH_CORE' $false $false
Probe-EventLog 'Microsoft-Windows-PowerShell/Operational' 'PWSH_WIN' $false $false
Probe-EventLog 'Application' 'APPLICATION_CRASH' $false $true
$python = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
Write-Host ('TTV_STARTUP_PYTHON_TOTAL=' + $python.Count)
Write-Host 'TTV_STARTUP_PRIVATE_OWNER_DPAPI=NOT_READ_DIFFERENT_CONTEXT'
Write-Host 'TTV_STARTUP_OWNER_TASK_MUTATION=NONE'
Write-Host 'TTV_STARTUP_PROVIDER_OR_LAN_CALL=NONE'
Write-Host 'TTV_STARTUP_DIAG_RESULT=COMPLETE'
