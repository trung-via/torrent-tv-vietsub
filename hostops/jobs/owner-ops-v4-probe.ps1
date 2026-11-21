# Read-only readiness probe for the already enrolled Owner-interactive
# LaptopHostOps task and its one-at-a-time request/receipt spool.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_OPS_V4_PROBE_TRUSTED_RUNNER_REQUIRED'
}
function SidOf([string]$id) {
    if ($id -match '^S-\d+(?:-\d+){2,}$') { return $id }
    return ([Security.Principal.NTAccount]::new($id).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
$owner = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-Laptop-HostOps' -TaskPath '\' -ErrorAction SilentlyContinue
Write-Output ('OWNER_OPS_V4_OWNER=' + [string]$owner.State)
if ($null -eq $task) {
    Write-Output 'OWNER_OPS_V4_TASK=HOSTOPS_SETUP_REQUIRED'
    return
}
$action = if (@($task.Actions).Count -eq 1) { @($task.Actions)[0] } else { $null }
$nTriggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
$valid = (
    [string]$task.State -ceq 'Ready' -and
    [string]$task.Description -ceq 'TTV_LAPTOP_HOSTOPS_OWNER_INTERACTIVE_ROUTINE_V1' -and
    [string]$task.Principal.LogonType -ieq 'Interactive' -and
    [string]$task.Principal.RunLevel -ieq 'Limited' -and
    [string]$task.Settings.MultipleInstances -ieq 'IgnoreNew' -and
    $nTriggers -eq 0 -and $null -ne $action -and
    (SidOf ([string]$task.Principal.UserId)) -ceq (SidOf ([string]$owner.Principal.UserId)) -and
    [IO.Path]::GetFileName([string]$action.Execute).Equals('pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -and
    [string]$action.Arguments -cmatch '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-laptop-ops-helper\.ps1"\z'
)
Write-Output ('OWNER_OPS_V4_TASK=' + $(if ($valid) { 'ENROLLED_READY' } else { 'DRIFT_HOLD' }))
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Join-Path $spool 'Requests\request.json'
$receipt = Join-Path $spool 'Receipts\receipt.json'
if (-not (Test-Path -LiteralPath $request)) {
    Write-Output 'OWNER_OPS_V4_SPOOL=EMPTY_READY'
} elseif (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    Write-Output 'OWNER_OPS_V4_SPOOL=UNRESOLVED_HOLD'
} else {
    $a = Get-Content -LiteralPath $request -Raw | ConvertFrom-Json
    $b = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    $safe = ($a.nonce -ceq $b.nonce -and $a.source_commit -ceq $b.source_commit -and
             $b.result -cin @('SUCCESS','FAILED_NO_RETRY'))
    Write-Output ('OWNER_OPS_V4_SPOOL=' + $(if ($safe) { 'TERMINAL_READY' } else { 'UNRESOLVED_HOLD' }))
}
Write-Output 'OWNER_OPS_V4_OPERATION=NOT_TRIGGERED'
