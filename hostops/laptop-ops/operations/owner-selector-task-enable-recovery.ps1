# Recover only the Owner scheduled-task enable flag after a failed source
# rollout. The existing verified Python Owner process is deliberately left
# running: no Start/Stop/kill, no event replay, no provider, no file swap.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'SELECTOR_RECOVERY_REQUEST_INVALID'
}
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$owner = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$taskSid = [string]$task.Principal.UserId
if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $taskSid -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    throw 'SELECTOR_RECOVERY_OWNER_TASK_IDENTITY_DRIFT'
}
$installed = Join-Path $owner 'app\poc\p2-sub-discovery'
$expected = @{
    'automatic_vietsub_flow.py' = '0156951817811a3c72a183e23df73611119386716f8f0572e7d6203e533911c5'
    'matcher.py' = 'f56ca2dfe004dfe0c127b19307720661e19920a44c507bceab88986c0997af3b'
}
foreach ($name in $expected.Keys) {
    if ((Get-FileHash -LiteralPath (Join-Path $installed $name) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected[$name]) {
        throw 'SELECTOR_RECOVERY_INSTALLED_DRIFT'
    }
}
$healthPath = Join-Path $owner 'agent-health.json'
$health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($health.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
    $health.state -cne 'READY' -or [long]$health.pid -le 0 -or
    $now - [long]$health.observed_utc_epoch -gt 30 -or
    [long]$health.observed_utc_epoch -gt $now) {
    throw 'SELECTOR_RECOVERY_OWNER_NOT_FRESH'
}
$proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$health.pid)
if ($null -eq $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') {
    throw 'SELECTOR_RECOVERY_OWNER_PROCESS_UNKNOWN'
}
$identity = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
if ($identity.ReturnValue -ne 0 -or $identity.Sid -cne $sid) {
    throw 'SELECTOR_RECOVERY_OWNER_PROCESS_IDENTITY_DRIFT'
}
if ([string]$task.State -eq 'Disabled') {
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
} elseif ([string]$task.State -notin @('Ready','Running')) {
    throw 'SELECTOR_RECOVERY_TASK_STATE_UNEXPECTED'
}
$after = Get-ScheduledTask -TaskName $taskName -TaskPath '\'
if ([string]$after.State -notin @('Ready','Running')) {
    throw 'SELECTOR_RECOVERY_TASK_ENABLE_FAILED'
}
$current = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'SELECTOR_RECOVERY_REQUEST_CHANGED' }
$data = [ordered]@{
    schema='TTV-OWNER-SELECTOR-RECOVERY-V1'; nonce=$request.nonce
    task='ENABLED'; owner='PRESERVED_RUNNING_VERIFIED'; version='OLD_TWO'
} | ConvertTo-Json -Compress
$target = Join-Path $spool 'Receipts\selector-recovery.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp,$data,[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp,$target,$true)
Write-Output 'OWNER_SELECTOR_RECOVERY=TASK_ENABLED_NO_RESTART'
