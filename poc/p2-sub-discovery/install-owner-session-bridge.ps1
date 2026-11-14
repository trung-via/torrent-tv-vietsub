# One-time owner-only enrollment for Torrent TV automatic Vietsub.
# Run interactively under the SAME Windows user that owns the subtitle cache.
# Does not grant GitHub runner admin, change UAC, open ports or copy secrets.
# Run from a source-pinned Torrent TV checkout of the reviewed bridge PR.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    throw 'OWNER_BRIDGE_ENROLLMENT_REQUIRES_INTERACTIVE_USER'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.User.Value -in @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')) {
    throw 'OWNER_BRIDGE_BUILTIN_SERVICE_IDENTITY_REFUSED'
}

$loggedOnUser = (Get-CimInstance Win32_ComputerSystem).UserName
if ([string]::IsNullOrWhiteSpace($loggedOnUser) -or
    -not $identity.Name.Equals(
        $loggedOnUser, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_BRIDGE_ENROLLMENT_MUST_MATCH_LOGGED_ON_USER'
}

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$srcD2 = Join-Path $repo 'poc\p2-sub-discovery'
$srcP2 = Join-Path $repo 'poc\p2-aisub'
foreach ($needed in @(
    (Join-Path $srcD2 'owner_session_bridge.py'),
    (Join-Path $srcD2 'automatic_vietsub_flow.py'),
    (Join-Path $srcD2 'start-owner-session-agent.ps1'),
    (Join-Path $srcP2 'automatic_lean120_worker.py'),
    (Join-Path $srcP2 'translator_profile.json')
)) {
    if (-not (Test-Path -LiteralPath $needed -PathType Leaf)) {
        throw 'OWNER_BRIDGE_SOURCE_INCOMPLETE'
    }
}

$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$secretsDir = Join-Path $root 'secrets'
$installed = Join-Path $root 'app'
$d2Target = Join-Path $installed 'poc\p2-sub-discovery'
$p2Target = Join-Path $installed 'poc\p2-aisub'
foreach ($directory in @($root, $secretsDir, $d2Target, $p2Target)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# Protect owner-local app and encrypted secrets against the service runner.
$sid = $identity.User.Value
foreach ($dir in @($root, $secretsDir)) {
    & icacls.exe $dir /inheritance:r /grant:r "*$($sid):(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_BRIDGE_PRIVATE_ACL_SETUP_FAILED' }
}

Copy-Item -LiteralPath (Join-Path $srcD2 'start-owner-session-agent.ps1') -Destination $root -Force
Get-ChildItem -LiteralPath $srcD2 -Filter '*.py' -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $d2Target -Force }
Get-ChildItem -LiteralPath $srcP2 -Filter '*.py' -File |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $p2Target -Force }
Copy-Item -LiteralPath (Join-Path $srcP2 'translator_profile.json') -Destination $p2Target -Force

# Store each key only once. DPAPI binds ciphertext to this Windows account.
# A later login can start the agent with NO prompts or key sent to GitHub.
foreach ($item in @(
    @{ Label = 'OpenSubtitles API key'; Name = 'opensub.dpapi' },
    @{ Label = 'Gemini API key'; Name = 'gemini.dpapi' }
)) {
    $dest = Join-Path $secretsDir $item.Name
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        $entry = Read-Host $item.Label -AsSecureString
        if ($entry.Length -eq 0) { throw 'OWNER_BRIDGE_EMPTY_SECRET_REFUSED' }
        $cipher = ConvertFrom-SecureString -SecureString $entry
        Set-Content -LiteralPath $dest -Value $cipher -Encoding ASCII -NoNewline
        Write-Host 'OWNER_BRIDGE_OWNER_SECRET_ENROLLED=YES'
    }
}
# Harden newly created files; inherit owner-only + SYSTEM permissions.
foreach ($file in (Get-ChildItem -LiteralPath $secretsDir -File)) {
    & icacls.exe $file.FullName /inheritance:r /grant:r "*$($sid):F" "*S-1-5-18:F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_BRIDGE_SECRET_ACL_FAILED' }
}

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$argument = '-NoLogo -NoProfile -NonInteractive -File "' + $launcher + '"'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    if ($existing.Principal.UserId -ine $identity.Name -or
        $existing.Principal.LogonType -ne 'Interactive' -or
        $existing.Actions.Count -ne 1 -or
        $existing.Actions[0].Execute -ine $pwsh -or
        $existing.Actions[0].Arguments -cne $argument) {
        throw 'OWNER_BRIDGE_SCHEDULED_TASK_CONFLICT'
    }
}
else {
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $principal = New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -StartWhenAvailable
    try {
        $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
        Register-ScheduledTask -TaskName $taskName -InputObject $task -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host 'OWNER_BRIDGE_TASK_REGISTRATION=BLOCKED_WINDOWS_PERMISSION'
        throw
    }
}

Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
Write-Host 'OWNER_BRIDGE_ONE_TIME_ENROLLMENT=COMPLETED'
Write-Host 'OWNER_BRIDGE_TASK_SCOPE=INTERACTIVE_OWNER_ONLY'
Write-Host 'OWNER_BRIDGE_RUNNER_ADMIN_GRANTED=NO'
Write-Host 'OWNER_BRIDGE_SRT_OR_API_KEY_COPIED_TO_GITHUB=NO'
Write-Host 'OWNER_BRIDGE_OMP_SELECTED_MEDIA_HOOK=REQUIRES_INTEGRATION'
