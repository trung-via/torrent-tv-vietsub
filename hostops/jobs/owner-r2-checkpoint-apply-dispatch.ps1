# Owner-approved 2026-11-21 HostOps dispatch of an independently enrolled
# one-shot Owner-context task. Service only reads task metadata, starts that
# exact task and reads a sanitized ProgramData receipt. No private path access.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Hold([string]$code) { throw ('HOSTOPS_CHECKPOINT_APPLY_HOLD_' + $code) }
$taskName = 'TorrentTV-Vietsub-Owner-R2-Checkpoint-Apply'
$originalName = 'TorrentTV-Vietsub-OwnerAgent'
$expectedDescription = 'TTV_OWNER_CHECKPOINT_APPLY_ONCE_20261121'
$receiptFile = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\checkpoint-apply.json'
$original = Get-ScheduledTask -TaskName $originalName -TaskPath '\' -ErrorAction Stop
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$sid = [string]$original.Principal.UserId
$taskSid = [string]$task.Principal.UserId
if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
$actions = @($task.Actions)
$triggers = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
if ([string]$original.State -cne 'Running' -or
    $sid -cne $taskSid -or
    [string]$original.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Description -cne $expectedDescription -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    [string]$task.State -cne 'Ready' -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    $actions.Count -ne 1 -or $triggers -ne 0 -or
    -not [IO.Path]::GetFileName([string]$actions[0].Execute).Equals(
        'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace([string]$actions[0].WorkingDirectory) -or
    [string]$actions[0].Arguments -cnotmatch
        '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-r2-checkpoint-apply-once\.ps1"\z') {
    Hold 'ENROLLED_TASK_IDENTITY_DRIFT_OR_NOT_READY'
}
if (Test-Path -LiteralPath $receiptFile) { Hold 'PRIOR_ATTEMPT_RECEIPT_PRESENT' }
$info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
if ($info.LastRunTime -ge [datetime]'2000-01-01') { Hold 'ALREADY_RAN_NO_RETRY' }
$dispatchEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
Write-Output 'HOSTOPS_OWNER_CHECKPOINT_APPLY=TRIGGERED_OWNER_SESSION'

# The task may take up to ~100s for stop/install/restart and rollback.
for ($n=0;$n -lt 120;$n++) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $receiptFile -PathType Leaf)) { continue }
    if ((Get-Item -LiteralPath $receiptFile -Force).Attributes -band
        [IO.FileAttributes]::ReparsePoint) { Hold 'RECEIPT_REPARSE' }
    if ((Get-Item -LiteralPath $receiptFile).Length -gt 1024) { Hold 'RECEIPT_TOO_LARGE' }
    try { $r = Get-Content -LiteralPath $receiptFile -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable }
    catch { continue }
    if ($r.schema -cne 'TTV-OWNER-CHECKPOINT-APPLY-V1' -or
        $r.release_id -cne 'r2-checkpoint-175' -or
        $r.stage_commit -cne '5ab8a2dd6e09c2eeef83b473e82b2ff4c758e961' -or
        $r.observed_utc_epoch -isnot [ValueType] -or
        [long]$r.observed_utc_epoch -lt $dispatchEpoch -or
        [long]$r.observed_utc_epoch -gt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+5)) {
        Hold 'RECEIPT_SCHEMA_OR_TIME_DRIFT'
    }
    if ($r.result -ceq 'STARTED_OWNER_STOP_P2_STATE_PRESERVED') { continue }
    if ($r.result -ceq 'INSTALLED_OWNER_FRESH_P2_STATE_PRESERVED') {
        Write-Output 'HOSTOPS_OWNER_CHECKPOINT_APPLY=INSTALLED_OWNER_FRESH_P2_STATE_PRESERVED'
        Write-Output 'HOSTOPS_OWNER_CHECKPOINT_APPLY_TV=NOT_VERIFIED'
        Write-Output 'HOSTOPS_OWNER_CHECKPOINT_APPLY_PROVIDER=NOT_RUN_BY_INSTALLER'
        return
    }
    if ($r.result -ceq 'ROLLED_BACK_OLD_OWNER_FRESH' -or
        $r.result -ceq 'HOLD_OWNER_DISABLED_OR_RECOVERY_UNVERIFIED') {
        Hold ('OWNER_REPORT_' + [string]$r.result)
    }
    Hold 'OWNER_RECEIPT_RESULT_UNKNOWN'
}
Hold 'OWNER_RECEIPT_TIMEOUT_DO_NOT_RETRY'
