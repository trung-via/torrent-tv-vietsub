# Exact OwnerAgent TaskScheduler start request; no PID kill or service restart.
# On source-pinned dedicated NETWORK_SERVICE HostOps runner only.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    throw 'TTV_OWNER_START_UNTRUSTED_RUNNER'
}
$name = 'TorrentTV-Vietsub-OwnerAgent'
$task = @(Get-ScheduledTask -TaskName $name -ErrorAction Stop)
if ($task.Count -ne 1 -or $task[0].TaskPath -cne '\\') {
    throw 'TTV_OWNER_START_TASK_NOT_EXACT'
}
$task = $task[0]
$action = @($task.Actions)
if ($action.Count -ne 1 -or
    [IO.Path]::GetFileName([string]$action[0].Execute) -ine 'pwsh.exe' -or
    ([string]$action[0].Arguments) -notmatch 'start-owner-session-agent\.ps1' -or
    [string]$task.Principal.LogonType -cne 'Interactive') {
    throw 'TTV_OWNER_START_TASK_ACTION_MISMATCH'
}
Write-Host 'TTV_OWNER_START_TARGET=EXACT_OWNERAGENT'
Write-Host ('TTV_OWNER_START_TASK_STATE_BEFORE=' + [string]$task.State)
$before = @(Get-NetTCPConnection -OwningProcess 2500 -State Listen -ErrorAction SilentlyContinue)
Write-Host ('TTV_OWNER_START_OLD_PID_LISTENER_COUNT=' + $before.Count)
if ([string]$task.State -cne 'Ready') {
    Write-Host 'TTV_OWNER_START=HOLD_TASK_NOT_READY'
    Write-Host 'TTV_OWNER_START_TASK_DISPATCHED=NO'
    return
}
$null = & schtasks.exe /Run /TN ('\\' + $name) 2>&1
$exitCode = $LASTEXITCODE
Write-Host ('TTV_OWNER_START_SCHTASKS_EXIT=' + $exitCode)
if ($exitCode -ne 0) {
    Write-Host 'TTV_OWNER_START=HOLD_TASK_EXECUTE_DENIED'
    throw 'TTV_OWNER_START_ACCESS_BOUNDARY'
}
Write-Host 'TTV_OWNER_START_DISPATCH=ACCEPTED'
Start-Sleep -Seconds 8
$after = Get-ScheduledTask -TaskName $name -ErrorAction Stop
Write-Host ('TTV_OWNER_START_TASK_STATE_AFTER=' + [string]$after.State)
$old = @(Get-NetTCPConnection -OwningProcess 2500 -State Listen -ErrorAction SilentlyContinue)
Write-Host ('TTV_OWNER_START_OLD_PID_LISTENER_COUNT_AFTER=' + $old.Count)
Write-Host 'TTV_OWNER_START_PROCESS_KILLED=NO'
Write-Host 'TTV_OWNER_START_PROVIDER_OR_TV=NOT_VERIFIED'