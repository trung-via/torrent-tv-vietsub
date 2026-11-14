# Read-only identity and Task Scheduler capability inventory. NEVER read keys.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'AUTO_BRIDGE_UNTRUSTED_HOSTOPS'
}
$who = [Security.Principal.WindowsIdentity]::GetCurrent()
$sys = $who.User.Value -ceq 'S-1-5-18'
$principal = New-Object Security.Principal.WindowsPrincipal($who)
$admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$interactiveName = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
$interactiveExists = -not [string]::IsNullOrWhiteSpace($interactiveName)
$sessions = @(
    Get-Process -Name explorer -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -gt 0 } |
    Select-Object -ExpandProperty SessionId -Unique
)
$tasks = @(Get-ScheduledTask -ErrorAction Stop | Where-Object {
    $_.TaskName -like '*TorrentTV*' -or $_.TaskPath -like '\\TorrentTV*'
})
Write-Host 'AUTO_TTV_ACCESS_PROBE_V1'
Write-Host ('HOSTOPS_IS_LOCAL_SYSTEM=' + $sys.ToString().ToUpperInvariant())
Write-Host ('HOSTOPS_IS_ADMIN=' + $admin.ToString().ToUpperInvariant())
Write-Host ('INTERACTIVE_USER_LOGGED_ON=' + $interactiveExists.ToString().ToUpperInvariant())
Write-Host ('INTERACTIVE_EXPLORER_SESSIONS=' + $sessions.Count)
Write-Host ('EXISTING_TTV_TASK_COUNT=' + $tasks.Count)
Write-Host ('TASK_SCHEDULER_AVAILABLE=' + $true.ToString().ToUpperInvariant())
Write-Host 'NO_USER_NAME_OR_SECRET_PRINTED=YES'
Write-Host 'NO_WINDOWS_CONFIGURATION_CHANGED=YES'
