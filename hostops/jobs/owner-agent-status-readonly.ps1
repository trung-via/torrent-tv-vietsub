# Read-only scheduled task and identity status. Do not inspect owner files/keys.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') { throw 'OWNER_TASK_STATUS_UNTRUSTED_RUNNER' }

Write-Host 'OWNER_BRIDGE_TASK_STATUS_PROBE_V1'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
}
catch {
    Write-Host 'OWNER_BRIDGE_TASK_QUERY=UNAVAILABLE_OR_NOT_VISIBLE'
    Write-Host 'OWNER_BRIDGE_NO_PROFILE_OR_SECRET_READ=YES'
    Write-Host 'OWNER_BRIDGE_WINDOWS_CHANGES=NO'
    exit 0
}
Write-Host 'OWNER_BRIDGE_TASK_QUERY=VISIBLE'
Write-Host ('OWNER_BRIDGE_TASK_RUNNING=' + ($task.State -eq 'Running').ToString().ToUpperInvariant())
Write-Host ('OWNER_BRIDGE_TASK_PRINCIPAL_INTERACTIVE=' + ($task.Principal.LogonType -eq 'Interactive').ToString().ToUpperInvariant())
Write-Host ('OWNER_BRIDGE_TASK_LIMITED=' + ($task.Principal.RunLevel -eq 'Limited').ToString().ToUpperInvariant())
# Only compare launcher's basename; never print owner profile paths.
$actionSafe = ($task.Actions.Count -eq 1 -and
               [IO.Path]::GetFileName($task.Actions[0].Execute) -ieq 'pwsh.exe' -and
               $task.Actions[0].Arguments -match 'start-owner-session-agent[.]ps1')
Write-Host ('OWNER_BRIDGE_TASK_ACTION_MATCH=' + $actionSafe.ToString().ToUpperInvariant())
try {
    $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
    $result = [int64]$info.LastTaskResult
    Write-Host ('OWNER_BRIDGE_TASK_LAST_RESULT_ZERO=' + ($result -eq 0).ToString().ToUpperInvariant())
    Write-Host ('OWNER_BRIDGE_TASK_HAS_RUN=' + ($info.LastRunTime.Year -gt 2000).ToString().ToUpperInvariant())
}
catch {
    Write-Host 'OWNER_BRIDGE_TASK_LAST_RESULT=UNAVAILABLE'
}
Write-Host 'OWNER_BRIDGE_NO_PROFILE_OR_SECRET_READ=YES'
Write-Host 'OWNER_BRIDGE_WINDOWS_CHANGES=NO'
