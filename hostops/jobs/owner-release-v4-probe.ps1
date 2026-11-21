# Read-only, sanitized discovery of the pre-enrolled interactive Owner release
# staging task. No file content, subtitles, secrets, task trigger or TV action.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_RELEASE_V4_PROBE_TRUSTED_RUNNER_REQUIRED'
}
function SidOf([string]$id) {
    if ($id -match '^S-\d+(?:-\d+){2,}$') { return $id }
    return ([Security.Principal.NTAccount]::new($id).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$stage = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Owner-Release-Stage' -TaskPath '\' -ErrorAction SilentlyContinue
Write-Output ('OWNER_RELEASE_V4_OWNER_TASK=' + [string]$owner.State)
if ($null -eq $stage) {
    Write-Output 'OWNER_RELEASE_V4_STAGE_TASK=HOSTOPS_SETUP_REQUIRED'
    Write-Output 'OWNER_RELEASE_V4_STAGE=NOT_RUN'
    return
}
$count = if ($null -eq $stage.Triggers) { 0 } else { @($stage.Triggers).Count }
$action = if (@($stage.Actions).Count -eq 1) { @($stage.Actions)[0] } else { $null }
$matches = (
    [string]$stage.State -ceq 'Ready' -and
    [string]$stage.Description -ceq 'TTV_OWNER_HOSTOPS_RELEASE_STAGE_ONLY_V1' -and
    [string]$stage.Principal.LogonType -ieq 'Interactive' -and
    [string]$stage.Principal.RunLevel -ieq 'Limited' -and
    [string]$stage.Settings.MultipleInstances -ieq 'IgnoreNew' -and
    $count -eq 0 -and $null -ne $action -and
    (SidOf ([string]$stage.Principal.UserId)) -ceq (SidOf ([string]$owner.Principal.UserId)) -and
    [IO.Path]::GetFileName([string]$action.Execute).Equals('pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -and
    [string]::IsNullOrWhiteSpace([string]$action.WorkingDirectory) -and
    [string]$action.Arguments -cmatch '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-release-stage-helper\.ps1"\z'
)
Write-Output ('OWNER_RELEASE_V4_STAGE_TASK=' + $(if ($matches) { 'ENROLLED_READY' } else { 'DRIFT_HOLD' }))
Write-Output 'OWNER_RELEASE_V4_STAGE=NOT_RUN'
Write-Output 'OWNER_RELEASE_V4_PROVIDER_TV=NOT_TOUCHED'
