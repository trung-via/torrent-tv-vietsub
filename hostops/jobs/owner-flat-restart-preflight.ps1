# Read-only exact Owner task/process and in-flight status before a supervised
# Windows interactive restart. No task or process mutation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub') {
    throw 'TTV_OWNER_RESTART_PREFLIGHT_BAD_RUNNER'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$current = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
$userMatch = (-not [string]::IsNullOrWhiteSpace($logged) -and
    $current.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase))
$sidMatch = $false
try {
    $principal = [Security.Principal.NTAccount]::new([string]$task.Principal.UserId)
    $taskSid = $principal.Translate([Security.Principal.SecurityIdentifier]).Value
    $sidMatch = $taskSid -ceq $current.User.Value
} catch {
    if ([string]$task.Principal.UserId -match '^S-1-5-') {
        $sidMatch = ([string]$task.Principal.UserId) -ceq $current.User.Value
    }
}
Write-Host ('TTV_OWNER_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_OWNER_TASK_LOGON_TYPE=' + [string]$task.Principal.LogonType)
Write-Host ('TTV_OWNER_RUNNER_ACCOUNT_MATCH=' + $sidMatch.ToString().ToUpperInvariant())
Write-Host ('TTV_OWNER_RUNNER_IS_INTERACTIVE_OWNER=' +
    ([bool]($userMatch -and [Environment]::UserInteractive -and
        [Diagnostics.Process]::GetCurrentProcess().SessionId -gt 0)).ToString().ToUpperInvariant())
$actions = @($task.Actions)
Write-Host ('TTV_OWNER_TASK_ACTION_COUNT=' + $actions.Count)
if ($actions.Count -ne 1 -or
    [string]$actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    throw 'TTV_OWNER_RESTART_PREFLIGHT_ACTION_UNKNOWN'
}
$processes = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
$ownerProcesses = @($processes | Where-Object {
    [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
$unknownProcesses = @($processes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.CommandLine) })
Write-Host ('TTV_OWNER_PYTHON_PROCESS_COUNT=' + $ownerProcesses.Count)
Write-Host ('TTV_OWNER_UNINSPECTABLE_PYTHON_COUNT=' + $unknownProcesses.Count)
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
if ($sidMatch -and (Test-Path -LiteralPath $root -PathType Container)) {
    $inbox = Join-Path $root 'inbox'
    $state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    $pending = if (Test-Path -LiteralPath $inbox -PathType Container) {
        @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json' -ErrorAction Stop).Count
    } else { -1 }
    $inflight = if (Test-Path -LiteralPath $state -PathType Container) {
        @(Get-ChildItem -LiteralPath $state -File -Filter '*.inflight' -Recurse -ErrorAction Stop).Count
    } else { 0 }
    Write-Host ('TTV_OWNER_PENDING_EVENTS=' + $pending)
    Write-Host ('TTV_OWNER_PROVIDER_INFLIGHT=' + $inflight)
} else {
    Write-Host 'TTV_OWNER_PENDING_EVENTS=UNVERIFIED_DIFFERENT_OWNER_CONTEXT'
    Write-Host 'TTV_OWNER_PROVIDER_INFLIGHT=UNVERIFIED_DIFFERENT_OWNER_CONTEXT'
}
Write-Host 'TTV_OWNER_RESTART_PREFLIGHT=READ_ONLY_COMPLETE'
Write-Host 'TTV_OWNER_STOP_START=NOT_RUN'
