# Fixed, read-only Task Scheduler identity probe after an Owner-side V2
# enrollment HOLD. Runs only under the dedicated Torrent TV HostOps runner.
# No Owner profile, task mutation, P2 queue, API provider or TV interaction.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$who = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($PSVersionTable.PSVersion.Major -ne 7 -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $who.User.Value -cne 'S-1-5-20') {
    throw 'HOSTOPS_P2_B15_V2_DRIFT_PROBE_TRUSTED_RUNNER_REQUIRED'
}

function SidOf($principal) {
    try {
        $id = [string]$principal.UserId
        if ($id -match '^S-\d+(?:-\d+){2,}$') {
            return ([Security.Principal.SecurityIdentifier]::new($id)).Value
        }
        return ([Security.Principal.NTAccount]::new($id).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    } catch { return '' }
}
function Flag([string]$key,[bool]$value) {
    Write-Output ('HOSTOPS_P2_B15_V2_DRIFT_' + $key + '=' + $(
        if ($value) { 'YES' } else { 'NO' }))
}

$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' `
    -TaskPath '\' -ErrorAction Stop
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
$loggedSid = if ([string]::IsNullOrWhiteSpace($logged)) { '' } else {
    SidOf ([pscustomobject]@{ UserId = $logged })
}
$ownerSid = SidOf $owner.Principal
$actions = @($owner.Actions)
$oneAction = $null -ne $owner.Actions -and $actions.Count -eq 1
$act = if ($oneAction) { $actions[0] } else { $null }
$exeName = if ($null -ne $act) {
    [IO.Path]::GetFileName([string]$act.Execute).Trim('"')
} else { '' }
$args = if ($null -ne $act) { [string]$act.Arguments } else { '' }
$launcherMatch = $args -match '(?i)start-owner-session-agent\.ps1'
$strictArgs = $args -match '(?i)\A\s*-NoLogo\s+-NoProfile\s+-NonInteractive\s+-File\s+"[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\start-owner-session-agent\.ps1"\s*\z'

Write-Output 'HOSTOPS_P2_B15_V2_DRIFT_PROBE=READ_ONLY'
Flag 'OWNER_RUNNING' ([string]$owner.State -ceq 'Running')
Flag 'OWNER_LOGON_INTERACTIVE' ([string]$owner.Principal.LogonType -ieq 'Interactive')
Flag 'OWNER_RUNLEVEL_LIMITED' ([string]$owner.Principal.RunLevel -ieq 'Limited')
Flag 'OWNER_PRINCIPAL_RESOLVED' (-not [string]::IsNullOrWhiteSpace($ownerSid))
Flag 'LOGGED_IN_PRINCIPAL_RESOLVED' (-not [string]::IsNullOrWhiteSpace($loggedSid))
Flag 'OWNER_MATCHES_LOGGED_IN' ($ownerSid -cne '' -and $ownerSid -ceq $loggedSid)
Flag 'OWNER_EXACTLY_ONE_ACTION' $oneAction
Flag 'OWNER_EXE_PWSH7_NAME' ($exeName -ieq 'pwsh.exe')
Flag 'OWNER_LAUNCHER_NAME_MATCH' $launcherMatch
Flag 'OWNER_LAUNCHER_STRICT_ARGS_MATCH' $strictArgs
Flag 'OWNER_WORKDIR_EMPTY' ($null -ne $act -and
    [string]::IsNullOrWhiteSpace([string]$act.WorkingDirectory))
$v2 = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Owner-P2-B15-FreshStartV2' `
    -TaskPath '\' -ErrorAction SilentlyContinue
Flag 'V2_TASK_ABSENT' ($null -eq $v2)
Write-Output 'HOSTOPS_P2_B15_V2_DRIFT_OWNER_ID_PATH=NOT_PRINTED'
Write-Output 'HOSTOPS_P2_B15_V2_DRIFT_PRIVATE_PROVIDER_TV=NOT_ACCESSED'
