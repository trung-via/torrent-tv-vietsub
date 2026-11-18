# Owner-only, offline and read-only diagnostic for a ScheduledTask exiting 1.
# Run in the signed-in Windows owner's PowerShell, NOT the GitHub runner.
# Prints only fixed vocabulary. Never prints paths, IPs, tokens or exceptions.
# No task mutations, HTTPS binds, network calls, provider calls or DPAPI export.
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Write-Host 'TTV_STARTUP_PROBE_VERSION=V1_READ_ONLY_OWNER'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_WINDOWS_REQUIRED'
    exit 2
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
if (-not [Environment]::UserInteractive -or $session -le 0 -or
    $identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20') -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_INTERACTIVE_OWNER_REQUIRED'
    exit 2
}
Write-Host 'TTV_STARTUP_OWNER_CONTEXT=INTERACTIVE'

$name = 'TorrentTV-Vietsub-OwnerAgent'
try {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction Stop
    $taskInfo = Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
} catch {
    Write-Host 'TTV_STARTUP_TASK=NOT_FOUND_OR_UNREADABLE'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_TASK'
    exit 2
}
Write-Host ('TTV_STARTUP_TASK_STATE=' + [string]$task.State)
Write-Host ('TTV_STARTUP_TASK_LAST_RESULT=' + [string]$taskInfo.LastTaskResult)

$ownerMatch = $false
try {
    $configured = [string]$task.Principal.UserId
    $ownerSid = if ($configured -match '^S-1-') {
        $configured
    } else {
        ([Security.Principal.NTAccount]::new($configured)).Translate(
            [Security.Principal.SecurityIdentifier]).Value
    }
    $ownerMatch = $ownerSid -ceq $identity.User.Value
} catch {
    $ownerMatch = $false
}
if (-not $ownerMatch -or [string]$task.Principal.LogonType -ne 'Interactive') {
    Write-Host 'TTV_STARTUP_TASK_OWNER=UNVERIFIED_OR_MISMATCH'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_TASK_OWNER'
    exit 2
}
Write-Host 'TTV_STARTUP_TASK_OWNER=MATCH'

$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$subdir = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$launcher = Join-Path $subdir 'start-owner-session-agent.ps1'
$entrypoint = Join-Path $subdir 'owner_p3_p4_entrypoint.py'
$actions = @($task.Actions)
if ($actions.Count -ne 1 -or
    [string]$actions[0].Arguments -notmatch '(?i)-File\s+' -or
    -not ([string]$actions[0].Arguments).Contains($launcher)) {
    Write-Host 'TTV_STARTUP_TASK_ACTION=MISMATCH'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_TASK_ACTION'
    exit 2
}
Write-Host 'TTV_STARTUP_TASK_ACTION=MATCH'

$filesReady = (Test-Path -LiteralPath $launcher -PathType Leaf) -and
    (Test-Path -LiteralPath $entrypoint -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $subdir 'owner_session_bridge.py') -PathType Leaf)
if (-not $filesReady) {
    Write-Host 'TTV_STARTUP_INSTALL=INCOMPLETE'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_INSTALL'
    exit 2
}
Write-Host 'TTV_STARTUP_INSTALL=PRESENT'

try {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $launcher, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -gt 0) { throw 'SCRIPT_PARSE_FAILED' }
    Write-Host 'TTV_STARTUP_LAUNCHER_PARSE=PASS'
} catch {
    Write-Host 'TTV_STARTUP_LAUNCHER_PARSE=FAIL'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_LAUNCHER_SYNTAX'
    exit 2
}

$secret = Join-Path $ownerRoot 'secrets\opensub.dpapi'
if (-not (Test-Path -LiteralPath $secret -PathType Leaf)) {
    Write-Host 'TTV_STARTUP_DPAPI=MISSING'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_SECRET_FILE'
    exit 2
}
try {
    # Validate the same current-user unseal operation as the launcher.
    # Do not unwrap the secure string or log the encrypted file contents.
    $encrypted = Get-Content -LiteralPath $secret -Raw -ErrorAction Stop
    $sealed = ConvertTo-SecureString -String $encrypted -ErrorAction Stop
    if ($null -eq $sealed) { throw 'DPAPI_INVALID' }
    Write-Host 'TTV_STARTUP_DPAPI=UNSEAL_PASS'
} catch {
    Write-Host 'TTV_STARTUP_DPAPI=UNSEAL_FAIL'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_DPAPI'
    exit 2
} finally {
    Remove-Variable encrypted, sealed -ErrorAction SilentlyContinue
}

$policy = Join-Path $ownerRoot 'p3-p4-policy.json'
$bindFile = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P4\gateway-bind.txt'
if (-not (Test-Path -LiteralPath $policy -PathType Leaf) -or
    -not (Test-Path -LiteralPath $bindFile -PathType Leaf)) {
    Write-Host 'TTV_STARTUP_P3P4_CONFIG=INCOMPLETE'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_P3P4_CONFIG'
    exit 2
}
Write-Host 'TTV_STARTUP_P3P4_CONFIG=PRESENT'

try {
    $bind = (Get-Content -LiteralPath $bindFile -Raw -ErrorAction Stop).Trim()
    if ($bind -notmatch '^(?<ip>(?:\d{1,3}\.){3}\d{1,3}):(?<port>\d{4,5})$') {
        throw 'BIND_FORMAT'
    }
    $bindIp = [string]$Matches['ip']
    $bindPort = [int]$Matches['port']
    if ($bindPort -lt 1024 -or $bindPort -gt 65535) { throw 'BIND_PORT' }
    $localIps = @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        ForEach-Object { $_.GetIPProperties().UnicastAddresses } |
        ForEach-Object { $_.Address.ToString() })
    $ipAssigned = $localIps -contains $bindIp
    Write-Host ('TTV_STARTUP_BIND_IP=' + $(if ($ipAssigned) { 'ASSIGNED' } else { 'NOT_ASSIGNED' }))
    if (-not $ipAssigned) {
        Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_STALE_LAN_BIND'
        exit 2
    }
    if ($null -eq (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        throw 'PORT_CHECK_UNAVAILABLE'
    }
    $portListeners = @(Get-NetTCPConnection -LocalPort $bindPort -State Listen -ErrorAction SilentlyContinue)
    $portBusy = $portListeners.Count -gt 0
    Write-Host ('TTV_STARTUP_BIND_PORT=' + $(if ($portBusy) { 'OCCUPIED' } else { 'AVAILABLE' }))
    if ($portBusy) {
        Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_PORT_CONFLICT'
        exit 2
    }
} catch {
    Write-Host 'TTV_STARTUP_BIND_CHECK=UNAVAILABLE_OR_INVALID'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_BIND_CHECK'
    exit 2
} finally {
    Remove-Variable bind, bindIp, bindPort, localIps -ErrorAction SilentlyContinue
}

try {
    & py -3 -c 'import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'PYTHON_UNAVAILABLE' }
    Write-Host 'TTV_STARTUP_PYTHON=PASS'
} catch {
    Write-Host 'TTV_STARTUP_PYTHON=FAIL'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_PYTHON'
    exit 2
}

$tlsCert = Join-Path $ownerRoot 'p4-identity\pc-cert.pem'
$tlsKey = Join-Path $ownerRoot 'p4-identity\pc-key.pem'
if (-not (Test-Path -LiteralPath $tlsCert -PathType Leaf) -or
    -not (Test-Path -LiteralPath $tlsKey -PathType Leaf)) {
    Write-Host 'TTV_STARTUP_TLS=FILES_MISSING'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_TLS_FILES'
    exit 2
}
try {
    # Construct the server TLS context only; do not bind a listening socket.
    $pythonTls = 'import ssl,sys; ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain(sys.argv[1],sys.argv[2])'
    & py -3 -c $pythonTls $tlsCert $tlsKey 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'TLS_LOAD_FAILED' }
    Write-Host 'TTV_STARTUP_TLS=LOAD_PASS'
} catch {
    Write-Host 'TTV_STARTUP_TLS=LOAD_FAIL'
    Write-Host 'TTV_STARTUP_PROBE_RESULT=HOLD_TLS_CONTEXT'
    exit 2
}

# Never claim a healthy Owner from these checks. A real startup still has
# HTTP bind and the foreground agent loop to pass.
Write-Host 'TTV_STARTUP_PROBE_RESULT=READ_ONLY_PASS_RUNTIME_UNVERIFIED'
