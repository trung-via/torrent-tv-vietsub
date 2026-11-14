# Scopingly authorized owner-session Task Scheduler bridge smoke.
# NOT generic runner impersonation. NO keys, subtitle bytes, or names printed.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'OWNER_BRIDGE_UNTRUSTED_HOSTOPS'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'OWNER_BRIDGE_REGISTRATION=BLOCKED_RUNNER_NOT_ADMIN'
    Write-Host 'NO_WINDOWS_CHANGES=YES'
    exit 0
}

$owner = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
$sessions = @(Get-Process explorer -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -gt 0 } |
    Select-Object -ExpandProperty SessionId -Unique)
if ([string]::IsNullOrWhiteSpace($owner) -or $sessions.Count -ne 1) {
    Write-Host 'OWNER_BRIDGE_REGISTRATION=BLOCKED_NO_UNIQUE_INTERACTIVE_SESSION'
    Write-Host 'NO_WINDOWS_CHANGES=YES'
    exit 0
}

$taskName = 'TorrentTV-OwnerSessionProbe'
if ($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) {
    Write-Host 'OWNER_BRIDGE_REGISTRATION=BLOCKED_TASK_ALREADY_EXISTS'
    Write-Host 'NO_WINDOWS_CHANGES=YES'
    exit 0
}

# Fixed immutable task action, not arbitrary GitHub comment execution.
$dir = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$pwsh = Get-Command pwsh.exe -ErrorAction Stop
$ownerScript = Join-Path $dir 'owner-session-probe.ps1'

@'
$ErrorActionPreference = 'Stop'
try {
    $session = (Get-Process -Id $PID).SessionId
    if ($session -le 0) { exit 41 }
    $local = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($local)) { exit 42 }
    $cache = Join-Path $local 'TorrentTVVietsub\subtitle-trials'
    if (-not (Test-Path -LiteralPath $cache -PathType Container)) { exit 43 }
    $hasSrt = @(Get-ChildItem -LiteralPath $cache -Filter '*.srt' -File -ErrorAction Stop |
        Select-Object -First 1).Count -gt 0
    if (-not $hasSrt) { exit 44 }
    exit 0
} catch { exit 45 }
'@ | Set-Content -LiteralPath $ownerScript -Encoding UTF8 -NoNewline

# SYSTEM & local administrators have write access; Users read/execute only.
# Protect the fixed task script from ordinary user modification.
$acl = Get-Acl -LiteralPath $dir
$acl.SetAccessRuleProtection($true, $false)
foreach ($entry in @(
    @{ sid='S-1-5-18'; right='FullControl' },
    @{ sid='S-1-5-32-544'; right='FullControl' },
    @{ sid='S-1-5-32-545'; right='ReadAndExecute' }
)) {
    $sid = New-Object Security.Principal.SecurityIdentifier($entry.sid)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $sid, $entry.right, 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $dir -AclObject $acl -ErrorAction Stop
$fileAcl = Get-Acl -LiteralPath $ownerScript
$fileAcl.SetAccessRuleProtection($true,$false)
foreach ($entry in @(
    @{ sid='S-1-5-18'; right='FullControl' },
    @{ sid='S-1-5-32-544'; right='FullControl' },
    @{ sid='S-1-5-32-545'; right='ReadAndExecute' }
)) {
    $sid = New-Object Security.Principal.SecurityIdentifier($entry.sid)
    $rule = New-Object Security.AccessControl.FileSystemAccessRule(
        $sid, $entry.right, 'None', 'None', 'Allow')
    $fileAcl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $ownerScript -AclObject $fileAcl -ErrorAction Stop

$act = New-ScheduledTaskAction -Execute $pwsh.Source -Argument (
    '-NoLogo -NoProfile -NonInteractive -File "' + $ownerScript + '"')
$userPrincipal = New-ScheduledTaskPrincipal -UserId $owner -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
$task = New-ScheduledTask -Action $act -Principal $userPrincipal -Settings $settings
Register-ScheduledTask -TaskName $taskName -InputObject $task -ErrorAction Stop | Out-Null

Write-Host 'OWNER_BRIDGE_REGISTRATION=INTERACTIVE_TOKEN_TASK_CREATED'
Write-Host 'OWNER_BRIDGE_GENERAL_IMPERSONATION=NO'
Write-Host 'OWNER_BRIDGE_NETWORK_ACCESS=NONE'
Write-Host 'OWNER_BRIDGE_SECRETS_READ=NO'
Write-Host 'OWNER_BRIDGE_RUN=TRIGGER_REQUESTED'

$before = (Get-ScheduledTaskInfo -TaskName $taskName).LastRunTime
Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
$state = 'TIMEOUT'
for ($i=0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    $taskNow = Get-ScheduledTask -TaskName $taskName
    if ($info.LastRunTime -gt $before -and $taskNow.State -ne 'Running') {
        $state = [string]$info.LastTaskResult
        break
    }
}
switch ($state) {
    '0' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=PASS' }
    '41' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=BLOCKED_SESSION0' }
    '42' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=BLOCKED_LOCALAPPDATA' }
    '43' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=BLOCKED_CACHE_MISSING' }
    '44' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=BLOCKED_SRT_MISSING' }
    '45' { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=BLOCKED_OWNER_ERROR' }
    default { Write-Host 'OWNER_BRIDGE_SESSION_CACHE_ACCESS=UNVERIFIED'; Write-Host 'OWNER_BRIDGE_TASK_RESULT_UNCLASSIFIED=YES' }
}
Write-Host 'OWNER_BRIDGE_ACTUAL_TRANSLATION=NOT_RUN'
Write-Host 'OWNER_BRIDGE_ACTUAL_MODEL_KEY_ACCESS=NOT_TESTED'
Write-Host 'OWNER_BRIDGE_GENERIC_REMOTE_EXECUTION=DISABLED'
