# Read-only, no account IDs, usernames, secrets, paths or media names printed
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
  throw 'RUNNER_IDENTITY_PROBE_UNTRUSTED'
}
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $id.User.Value
$who = $id.Name
$admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$kind = 'STANDARD_ACCOUNT'
if ($sid -ceq 'S-1-5-18') { $kind = 'LOCAL_SYSTEM' }
elseif ($sid -ceq 'S-1-5-19') { $kind = 'LOCAL_SERVICE' }
elseif ($sid -ceq 'S-1-5-20') { $kind = 'NETWORK_SERVICE' }
elseif ($sid -match '^S-1-5-80-') { $kind = 'SERVICE_VIRTUAL_ACCOUNT' }
$interactiveName = (Get-CimInstance Win32_ComputerSystem).UserName
$sameAsInteractive = (-not [string]::IsNullOrWhiteSpace($interactiveName)) -and
                     $who.Equals($interactiveName,[StringComparison]::OrdinalIgnoreCase)
$noninteractive = -not [Environment]::UserInteractive
$sessionZero = [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0
Write-Host 'RUNNER_ACCOUNT_CLASSIFICATION_V1'
Write-Host ('RUNNER_ACCOUNT_KIND=' + $kind)
Write-Host ('RUNNER_IS_ADMIN=' + $admin.ToString().ToUpperInvariant())
Write-Host ('RUNNER_IS_INTERACTIVE_OWNER=' + $sameAsInteractive.ToString().ToUpperInvariant())
Write-Host ('RUNNER_IS_NONINTERACTIVE=' + $noninteractive.ToString().ToUpperInvariant())
Write-Host ('RUNNER_SESSION_ZERO=' + $sessionZero.ToString().ToUpperInvariant())
Write-Host 'NO_PERMISSIONS_CHANGED=YES'
Write-Host 'NO_ACCOUNT_NAMES_SECRETS_OR_PATHS_PRINTED=YES'
