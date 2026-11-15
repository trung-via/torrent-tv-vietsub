# Owner-requested cold restart of the one known Torrent TV P4 listener and OwnerAgent task.
# This job is SHA-pinned, exact-PID/parent/socket guarded; it never touches unrelated Python.
# Public logs contain only status codes. No secrets, media, command lines, IP or port values.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_RESTART_UNTRUSTED_RUNNER'
}

$taskName = '\TorrentTV-Vietsub-OwnerAgent'
$oldPid = 2500
$parentPid = 9724
Write-Host 'TTV_RESTART_SCOPE=TTV_OWNER_P3_P4_ONLY'
Write-Host 'TTV_RESTART_PHASE=CONTROL_PREFLIGHT'

# Confirm that the existing task is runnable from the GitHub runner's
# unprivileged service token BEFORE touching the existing P4 process.
# Some Task Scheduler task ACLs deliberately hide it from NETWORK_SERVICE.
$null = & schtasks.exe /Query /TN $taskName /FO LIST 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'TTV_RESTART=HOLD_TASK_NOT_QUERYABLE_BY_HOSTOPS'
    Write-Host 'TTV_RESTART_PROCESS_STOPPED=NO'
    throw 'TTV_RESTART_CONTROL_BOUNDARY'
}
Write-Host 'TTV_RESTART_TASK_QUERY=PASS'

$old = Get-CimInstance Win32_Process -Filter "ProcessId=$oldPid" -ErrorAction Stop
$parent = Get-CimInstance Win32_Process -Filter "ProcessId=$parentPid" -ErrorAction Stop
if ($null -eq $old -or $null -eq $parent -or
    $old.Name -cne 'python.exe' -or $parent.Name -cne 'pwsh.exe' -or
    [int]$old.ParentProcessId -ne $parentPid -or
    [int]$old.SessionId -ne 1 -or [int]$parent.SessionId -ne 1) {
    Write-Host 'TTV_RESTART=HOLD_PROCESS_IDENTITY_DRIFT'
    throw 'TTV_RESTART_PROCESS_IDENTITY_GUARD'
}
$listeners = @(Get-NetTCPConnection -OwningProcess $oldPid -State Listen -ErrorAction Stop)
if ($listeners.Count -ne 1) {
    Write-Host 'TTV_RESTART=HOLD_OLD_LISTENER_NOT_UNIQUE'
    throw 'TTV_RESTART_SOCKET_GUARD'
}
$bindPort = [int]$listeners[0].LocalPort
$bindAddress = [string]$listeners[0].LocalAddress
$portPeers = @(Get-NetTCPConnection -LocalPort $bindPort -State Listen -ErrorAction Stop |
    Where-Object { $_.LocalAddress -eq $bindAddress })
if ($portPeers.Count -ne 1 -or [int]$portPeers[0].OwningProcess -ne $oldPid) {
    Write-Host 'TTV_RESTART=HOLD_BOUND_SOCKET_OWNERSHIP_DRIFT'
    throw 'TTV_RESTART_BOUND_GUARD'
}
Write-Host 'TTV_RESTART_PREFLIGHT=PASS'

# One exact PID from the user's prior P4 bind audit, never generic python.exe.
Write-Host 'TTV_RESTART_PHASE=STOP_EXACT_P4'
try {
    Stop-Process -Id $oldPid -Force -ErrorAction Stop
} catch {
    Write-Host 'TTV_RESTART=HOLD_CROSS_SESSION_STOP_DENIED'
    throw 'TTV_RESTART_STOP_ACCESS_BOUNDARY'
}
Start-Sleep -Seconds 3
if ($null -ne (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
    Write-Host 'TTV_RESTART=HOLD_OLD_P4_STILL_ALIVE'
    throw 'TTV_RESTART_STOP_INCOMPLETE'
}
$occupied = @(Get-NetTCPConnection -LocalPort $bindPort -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -eq $bindAddress })
if ($occupied.Count -ne 0) {
    Write-Host 'TTV_RESTART=HOLD_BIND_NOT_FREE_AFTER_STOP'
    throw 'TTV_RESTART_BIND_NOT_FREE'
}
Write-Host 'TTV_RESTART_OLD_P4_STOPPED=PASS'

Write-Host 'TTV_RESTART_PHASE=START_ORIGINAL_OWNER_TASK'
$null = & schtasks.exe /Run /TN $taskName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host 'TTV_RESTART=HOLD_TASK_START_DENIED_AFTER_STOP'
    throw 'TTV_RESTART_TASK_START_ACCESS_BOUNDARY'
}
Write-Host 'TTV_RESTART_TASK_START_REQUEST=ACCEPTED'

# A new exact bind owner is a socket-level result, not owner health or TV proof.
$replacement = $null
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    Start-Sleep -Seconds 2
    $current = @(Get-NetTCPConnection -LocalPort $bindPort -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -eq $bindAddress })
    if ($current.Count -eq 1 -and [int]$current[0].OwningProcess -ne $oldPid) {
        $replacement = $current[0]
        break
    }
    if ($current.Count -gt 1) {
        Write-Host 'TTV_RESTART=HOLD_DUPLICATE_LISTENERS'
        throw 'TTV_RESTART_DUPLICATE_BIND'
    }
}
if ($null -eq $replacement) {
    Write-Host 'TTV_RESTART=HOLD_NO_REPLACEMENT_P4_LISTENER'
    throw 'TTV_RESTART_NO_NEW_LISTENER'
}
$new = Get-CimInstance Win32_Process -Filter "ProcessId=$($replacement.OwningProcess)" -ErrorAction Stop
if ($null -eq $new -or $new.Name -cne 'python.exe') {
    Write-Host 'TTV_RESTART=HOLD_REPLACEMENT_IDENTITY_UNKNOWN'
    throw 'TTV_RESTART_NEW_IDENTITY'
}
Write-Host 'TTV_RESTART_SOCKET_OWNER_REPLACED=PASS'
Write-Host 'TTV_RESTART=SOCKET_ONLY_SUCCESS_OWNER_HEALTH_UNVERIFIED'
Write-Host 'TTV_RESTART_REAL_TV_PROOF=NOT_RUN'