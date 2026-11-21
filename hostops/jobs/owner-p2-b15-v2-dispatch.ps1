# Dedicated NETWORK_SERVICE runner triggers only the separately enrolled,
# fixed one-shot Owner V2 task. No Owner-private file/API access from runner.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Hold([string]$code) { throw ('HOSTOPS_P2_B15_V2_HOLD_' + $code) }
if ($PSVersionTable.PSVersion.Major -ne 7 -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne 'S-1-5-20') {
    Hold 'PWSH7_NETWORK_SERVICE_REQUIRED'
}
$name = 'TorrentTV-Vietsub-Owner-P2-B15-FreshStartV2'
$original = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
$task = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
$triggerCount = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
$receipt = Join-Path $env:ProgramData `
    'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\p2-batch15-fresh-start-v2.json'
function Sid($task) {
    $id = [string]$task.Principal.UserId
    if ($id -notmatch '^S-\d+(?:-\d+){2,}$') {
        $id = ([Security.Principal.NTAccount]::new($id).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    return $id
}
if ([string]$original.State -cne 'Running' -or
    (Sid $original) -cne (Sid $task) -or
    [string]$task.State -cne 'Ready' -or
    [string]$task.Description -cne 'TTV_OWNER_P2_B15_FRESH_START_V2_ONCE_20261121' -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    @($task.Actions).Count -ne 1 -or
    [IO.Path]::GetFileName([string]$task.Actions[0].Execute) -ine 'pwsh.exe' -or
    $triggerCount -ne 0 -or
    [string]$task.Actions[0].Arguments -cnotmatch
        '\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-p2-b15-fresh-start-v2-once\.ps1"\z') {
    Hold 'TASK_IDENTITY_DRIFT'
}
if (Test-Path -LiteralPath $receipt) { Hold 'PRIOR_ATTEMPT_NO_REPLAY' }
$info = Get-ScheduledTaskInfo -TaskName $name -TaskPath '\' -ErrorAction Stop
if ($info.LastRunTime -ge [datetime]'2000-01-01') { Hold 'PREVIOUS_RUN_NO_REPLAY' }
$epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction Stop
Write-Output 'HOSTOPS_P2_B15_V2=TRIGGERED_ONCE'
for ($i=0; $i -lt 125; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { continue }
    $item = Get-Item -LiteralPath $receipt -Force
    if ($item.Length -gt 1024 -or
        ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Hold 'RECEIPT_INVALID' }
    try { $r = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable }
    catch { continue }
    if ($r.schema -cne 'TTV-OWNER-P2-B15-FRESH-START-V2' -or
        $r.batch -cne 'batch-0015' -or
        $r.marker_sha256 -cne '4158f5ac6b0922e2eb58b5c1ecf5e5d40c85a6e69bb484e579c242c517478ab5' -or
        $r.observed_utc_epoch -isnot [ValueType] -or
        [long]$r.observed_utc_epoch -lt $epoch -or
        [long]$r.observed_utc_epoch -gt ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()+5)) {
        Hold 'RECEIPT_SCHEMA_DRIFT'
    }
    $result = [string]$r.result
    if ($result -in @('PREFLIGHT_STARTED','PREFLIGHT_PASS_NO_MUTATION',
        'ARCHIVED_OWNER_STOPPED')) { continue }
    if ($result -ceq 'ARCHIVED_OWNER_RUNNING_WAIT_NEW_TV_REQUEST') {
        Write-Output 'HOSTOPS_P2_B15_V2=ARCHIVED_OWNER_RUNNING_WAIT_NEW_TV_REQUEST'
        Write-Output 'HOSTOPS_P2_B15_V2_OLD_JOB=PRIVATE_RECOVERABLE_ARCHIVE'
        Write-Output 'HOSTOPS_P2_B15_V2_PROVIDER_TV=NOT_RUN'
        return
    }
    if ($result -cmatch '^(PREFLIGHT_HOLD|HOLD_OWNER_DISABLED)_[A-Z0-9_]{1,100}$') {
        Write-Output ('HOSTOPS_P2_B15_V2_OWNER_RESULT=' + $result)
        Hold 'OWNER_REPORTED_HOLD_NO_REPLAY'
    }
    Hold 'UNEXPECTED_RECEIPT_RESULT'
}
Hold 'RECEIPT_TIMEOUT_DO_NOT_RETRY'
