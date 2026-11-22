# One-shot recovery for an Owner task which is READY with no running Owner.
# Do not alter P2 work or replace files. Source pair must be entirely old
# PR179 or entirely fixed; mixed-version Owner is not safe to start.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceHashes = @{
    old = @{
        'owner_p3_p4_entrypoint.py' = '3febeac9f8ee5f3c0719894e1fb9ba67c91af4439970adbafdcbc8df28d9f953'
        'owner_p3_p4_policy_r0.py' = 'f52e5ce0fd41fd6bbd593d9dd11265aaf0f8334d85dd99f0ebb075238d918121'
    }
    fixed = @{
        'owner_p3_p4_entrypoint.py' = 'a2c7ff61d4e4c414bcb510fb573059a99f17cbcbb0e4cd2ee17b7cd98c01d666'
        'owner_p3_p4_policy_r0.py' = '8ab15096e0e1dbd2c28ee2b6d12620150b5d17966e27e89ec73b0a398f32fc46'
    }
}
function Hold([string]$reason) { throw ('OWNER_SAFE_RESUME_HOLD_' + $reason) }
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$interactive = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($interactive) -or
    -not ([Security.Principal.WindowsIdentity]::GetCurrent().Name).Equals(
        $interactive,[StringComparison]::OrdinalIgnoreCase)) { Hold 'INTERACTIVE_OWNER_REQUIRED' }
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$taskSid = [string]$task.Principal.UserId
if ($taskSid -notmatch '^S-\d+(?:-\d+){2,}$') {
    $taskSid = ([Security.Principal.NTAccount]::new($taskSid).Translate(
        [Security.Principal.SecurityIdentifier])).Value
}
if ($taskSid -cne $sid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
    @($task.Actions).Count -ne 1 -or
    [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    Hold 'OWNER_TASK_IDENTITY_DRIFT'
}
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app\poc\p2-sub-discovery'
$installed = @{}
foreach ($name in $sourceHashes.old.Keys) {
    $path = Join-Path $app $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Hold 'SOURCE_FILE_MISSING' }
    $installed[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$version = 'UNKNOWN'
foreach ($candidate in @('old','fixed')) {
    $allMatch = $true
    foreach ($name in $installed.Keys) {
        if ($installed[$name] -cne $sourceHashes[$candidate][$name]) { $allMatch = $false }
    }
    if ($allMatch) { $version = $candidate.ToUpperInvariant() }
}
if ($version -ceq 'UNKNOWN') { Hold 'SOURCE_PAIR_MIXED_OR_DRIFT' }
Write-Output ('OWNER_SAFE_RESUME_SOURCE_PAIR=' + $version)
$workers = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
    $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
    [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
})
if ($workers.Count -ne 0) { Hold 'OWNER_PROCESS_ALREADY_PRESENT' }
if ([string]$task.State -cne 'Ready') { Hold 'OWNER_TASK_NOT_READY' }
$health = Join-Path $root 'agent-health.json'
$previousPid = 0L
try {
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        $previousPid = [long]((Get-Content -LiteralPath $health -Raw | ConvertFrom-Json).pid)
    }
} catch { $previousPid = 0L }
$since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
Write-Output 'OWNER_SAFE_RESUME=TASK_STARTED'
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
    try {
        $state = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
        if ($state.state -cne 'READY' -or [long]$state.pid -eq $previousPid -or
            [long]$state.observed_utc_epoch -lt $since) { continue }
        $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$state.pid)
        if ($null -eq $proc -or [string]$proc.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
        $procOwner = Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid
        if ($procOwner.ReturnValue -eq 0 -and $procOwner.Sid -ceq $sid -and
            [string](Get-ScheduledTask -TaskName $taskName -TaskPath '\').State -ceq 'Running') {
            Write-Output 'OWNER_SAFE_RESUME=OWNER_READY_FRESH'
            Write-Output 'OWNER_SAFE_RESUME_P2_CHECKPOINTS=UNTOUCHED'
            return
        }
    } catch { continue }
}
Hold 'OWNER_FRESH_HEARTBEAT_NOT_VERIFIED'
