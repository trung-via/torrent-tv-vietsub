# Owner-authorized, one-time HostOps trigger only. The NETWORK_SERVICE runner
# never opens Owner-private P2/queue data or passes any movie/provider input.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Hold([string]$code) { throw ('HOSTOPS_OWNER_P2_FRESH_START_HOLD_' + $code) }
if ($PSVersionTable.PSVersion.Major -ne 7) { Hold 'POWERSHELL7_REQUIRED' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -cne 'S-1-5-20') { Hold 'EXPECTED_NETWORK_SERVICE_ONLY' }
$taskName = 'TorrentTV-Vietsub-Owner-P2-Batch15-FreshStart'
$originalName = 'TorrentTV-Vietsub-OwnerAgent'
$description = 'TTV_OWNER_P2_BATCH15_FRESH_START_ONCE_20261121'
$receiptPath = Join-Path $env:ProgramData `
    'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\p2-batch15-fresh-start.json'
$original = Get-ScheduledTask -TaskName $originalName -TaskPath '\' -ErrorAction Stop
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
function TaskSid($task) {
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    return $sid
}
$actions = @($task.Actions)
$triggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
if ([string]$original.State -cne 'Running' -or
    (TaskSid $original) -cne (TaskSid $task) -or
    [string]$original.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Description -cne $description -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    [string]$task.State -cne 'Ready' -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    $actions.Count -ne 1 -or $triggers -ne 0 -or
    -not [IO.Path]::GetFileName([string]$actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace([string]$actions[0].WorkingDirectory) -or
    [string]$actions[0].Arguments -cnotmatch
        '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-p2-batch15-fresh-start-once\.ps1"\z') {
    Hold 'OWNER_TASK_IDENTITY_DRIFT_OR_NOT_READY'
}
if (Test-Path -LiteralPath $receiptPath) { Hold 'PRIOR_ATTEMPT_NO_REPLAY' }
$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
if ($info.LastRunTime -ge [datetime]'2000-01-01') { Hold 'TASK_PREVIOUSLY_RAN_NO_RETRY' }
$startEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
Write-Output 'HOSTOPS_OWNER_P2_FRESH_START=TRIGGERED_OWNER_SESSION'
for ($i=0;$i -lt 130;$i++) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf)) { continue }
    if (((Get-Item -LiteralPath $receiptPath -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint) -or
        (Get-Item -LiteralPath $receiptPath).Length -gt 1024) { Hold 'RECEIPT_INVALID' }
    try { $r = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable }
    catch { continue }
    if ($r.schema -cne 'TTV-OWNER-P2-BATCH15-FRESH-START-V1' -or
        $r.batch -cne 'batch-0015' -or
        $r.marker_sha256 -cne '4158f5ac6b0922e2eb58b5c1ecf5e5d40c85a6e69bb484e579c242c517478ab5' -or
        $r.observed_utc_epoch -isnot [ValueType] -or
        [long]$r.observed_utc_epoch -lt $startEpoch -or
        [long]$r.observed_utc_epoch -gt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+5)) {
        Hold 'RECEIPT_SCHEMA_OR_TIME_DRIFT'
    }
    if ($r.result -in @('STARTED_NO_PROVIDER_REPLAY',
            'PRIVATE_ARCHIVE_COMPLETE_OWNER_STOPPED')) { continue }
    if ($r.result -ceq 'ARCHIVED_OWNER_RESTARTED_WAIT_NEW_VIEWER_REQUEST') {
        Write-Output 'HOSTOPS_OWNER_P2_FRESH_START=ARCHIVED_OWNER_RESTARTED_WAIT_NEW_VIEWER_REQUEST'
        Write-Output 'HOSTOPS_OWNER_P2_FRESH_START_OLD_JOB=PRIVATE_RECOVERABLE_ARCHIVE'
        Write-Output 'HOSTOPS_OWNER_P2_FRESH_START_PROVIDER=NOT_CALLED'
        Write-Output 'HOSTOPS_OWNER_P2_FRESH_START_TV=NOT_TESTED'
        return
    }
    if ($r.result -ceq 'HOLD_OWNER_DISABLED_RECOVERY_PRESERVED') {
        Hold 'OWNER_REPORTED_DISABLED_RECOVERY_PRESERVED'
    }
    Hold 'OWNER_RECEIPT_UNKNOWN_RESULT'
}
Hold 'TIMEOUT_DO_NOT_RETRY_OR_RESTART'
