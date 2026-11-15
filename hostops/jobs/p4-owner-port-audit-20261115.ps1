# Torrent TV HostOps diagnostic: process ownership only.
# PUBLIC-safe output. No credentials, local paths, command lines, IPs, ports, media or user data.
# No process stop, task start, network request, or owner-profile access.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_HOSTOPS_AUDIT_UNTRUSTED_RUNNER'
}

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$targetProcessId = 2500
$reportedParentId = 9724
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
Write-Host "TTV_HO_TASK_STATE=$($task.State)"

function Test-CommandMarker([string]$command, [string]$marker) {
    return $command.IndexOf(
        $marker, [StringComparison]::OrdinalIgnoreCase
    ) -ge 0
}

foreach ($target in @($targetProcessId, $reportedParentId)) {
    $label = if ($target -eq $targetProcessId) { 'OWNER' } else { 'PARENT' }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$target" -ErrorAction Stop
    if ($null -eq $proc) {
        Write-Host "TTV_HO_$($label)_EXISTS=FALSE"
        continue
    }
    $command = [string]$proc.CommandLine
    $commandReadable = -not [string]::IsNullOrWhiteSpace($command)
    Write-Host "TTV_HO_$($label)_EXISTS=TRUE"
    Write-Host "TTV_HO_$($label)_NAME=$($proc.Name)"
    Write-Host "TTV_HO_$($label)_SESSION_ID=$($proc.SessionId)"
    Write-Host "TTV_HO_$($label)_PARENT_ID=$($proc.ParentProcessId)"
    Write-Host "TTV_HO_$($label)_COMMAND_READABLE=$commandReadable"
    if ($commandReadable) {
        Write-Host "TTV_HO_$($label)_LEGACY_P4=$(Test-CommandMarker $command 'run_assumed_source_gateway.py')"
        Write-Host "TTV_HO_$($label)_INTEGRATED_P3P4=$(Test-CommandMarker $command 'owner_p3_p4_entrypoint.py')"
        Write-Host "TTV_HO_$($label)_OWNER_BRIDGE=$(Test-CommandMarker $command 'owner_session_bridge.py')"
        Write-Host "TTV_HO_$($label)_P4_MOCK_MODE=$(Test-CommandMarker $command '--mock-revisions')"
        Write-Host "TTV_HO_$($label)_P4_API_MODE=$(Test-CommandMarker $command '--execute-api')"
        Write-Host "TTV_HO_$($label)_P4_START_LAN=$(Test-CommandMarker $command '--start-lan')"
    } else {
        Write-Host "TTV_HO_$($label)_COMMAND_CLASS=UNKNOWN_CROSS_SESSION"
    }
}

function Measure-Listener {
    $tcp = @(Get-NetTCPConnection -OwningProcess $targetProcessId -State Listen -ErrorAction SilentlyContinue)
    return $tcp.Count
}

$first = Measure-Listener
Start-Sleep -Seconds 3
$second = Measure-Listener
Write-Host "TTV_HO_TARGET_LISTENERS_FIRST=$first"
Write-Host "TTV_HO_TARGET_LISTENERS_SECOND=$second"

$py = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction Stop)
$integrated = @($py | Where-Object {
    Test-CommandMarker ([string]$_.CommandLine) 'owner_p3_p4_entrypoint.py'
})
Write-Host "TTV_HO_VISIBLE_INTEGRATED_PROCESS_COUNT=$($integrated.Count)"
Write-Host 'TTV_HO_RESULT=READ_ONLY_OBSERVATION_COMPLETE'
Write-Host 'TTV_HO_OWNER_PROFILE_ACCESSED=NO'
Write-Host 'TTV_HO_PROCESS_OR_TASK_CHANGED=NO'
Write-Host 'TTV_HO_REAL_TV_ACCEPTANCE=NOT_RUN'
