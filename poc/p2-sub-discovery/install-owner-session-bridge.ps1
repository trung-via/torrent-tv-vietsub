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
$srcTrigger = Join-Path $repo 'poc\p3-vietsub-trigger'
foreach ($needed in @(
    (Join-Path $srcD2 'owner_session_bridge.py'),
    (Join-Path $srcD2 'automatic_vietsub_flow.py'),
    (Join-Path $srcD2 'trusted_playback_to_owner.py'),
    (Join-Path $srcD2 'start-owner-session-agent.ps1'),
    (Join-Path $srcTrigger 'activation_gate.py'),
    (Join-Path $srcP2 'automatic_lean120_worker.py'),
    (Join-Path $srcP2 'translator_profile.json')
)) {
    if (-not (Test-Path -LiteralPath $needed -PathType Leaf)) {
        throw 'OWNER_BRIDGE_SOURCE_INCOMPLETE'
    }
}

# Fail closed on accidental stale P2 model config from another Draft.
$translatorProfileConfig = Get-Content -LiteralPath (Join-Path $srcP2 'translator_profile.json') -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if ($translatorProfileConfig.provider -cne 'gemini' -or $translatorProfileConfig.model -cne 'gemini-4-hydrogen' -or
    $translatorProfileConfig.thinking_level -cne 'high') {
    throw 'OWNER_BRIDGE_GEMINI_HYDROGEN_HIGH_PROFILE_REQUIRED'
}

# Inspect existing task BEFORE changing ACLs, copying code or enrolling keys.
# Previously task conflict was detected only after files had been changed.
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$launcher = Join-Path $root 'start-owner-session-agent.ps1'
$pwsh = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop).Source
$argument = '-NoLogo -NoProfile -NonInteractive -File "' + $launcher + '"'
$principalGuard = Join-Path $PSScriptRoot 'owner-task-principal-identity.ps1'
$actionGuard = Join-Path $PSScriptRoot 'owner-task-action-identity.ps1'
if (-not (Test-Path -LiteralPath $principalGuard -PathType Leaf) -or
    -not (Test-Path -LiteralPath $actionGuard -PathType Leaf)) {
    throw 'OWNER_BRIDGE_TASK_VALIDATION_GUARD_MISSING'
}
. $principalGuard
. $actionGuard
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $existing) {
    $sameOwner = [bool](Test-TTVOwnerTaskPrincipal -Principal $existing.Principal -ExpectedSid $identity.User.Value)
    $actionCheck = Get-TTVOwnerTaskActionState -Task $existing -ExpectedExecutable $pwsh -ExpectedLauncher $launcher
    Write-Host ('OWNER_BRIDGE_TASK_SID_MATCH=' + $sameOwner.ToString().ToUpperInvariant())
    Write-Host ('OWNER_BRIDGE_TASK_EXECUTABLE_MATCH=' + $actionCheck.ExecutableMatch.ToString().ToUpperInvariant())
    Write-Host ('OWNER_BRIDGE_TASK_LAUNCHER_MATCH=' + $actionCheck.LauncherMatch.ToString().ToUpperInvariant())
    Write-Host ('OWNER_BRIDGE_TASK_SWITCHES_MATCH=' + $actionCheck.SwitchesMatch.ToString().ToUpperInvariant())
    Write-Host ('OWNER_BRIDGE_TASK_WORKDIR_EMPTY=' + $actionCheck.WorkingDirectoryEmpty.ToString().ToUpperInvariant())
    if (-not $sameOwner -or -not $actionCheck.Accepted) {
        throw 'OWNER_BRIDGE_SCHEDULED_TASK_CONFLICT'
    }
}
Write-Host 'OWNER_BRIDGE_TASK_PREFLIGHT_BEFORE_OWNER_FILE_COPY=PASS'


$secretsDir = Join-Path $root 'secrets'
$installed = Join-Path $root 'app'
$d2Target = Join-Path $installed 'poc\p2-sub-discovery'
$p2Target = Join-Path $installed 'poc\p2-aisub'
$triggerTarget = Join-Path $installed 'poc\p3-vietsub-trigger'
foreach ($directory in @($root, $secretsDir, $d2Target, $p2Target, $triggerTarget)) {
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
Copy-Item -LiteralPath (Join-Path $srcTrigger 'activation_gate.py') -Destination $triggerTarget -Force

# Store each key only once. DPAPI binds ciphertext to this Windows account.
# A later login can start the agent with NO prompts or key sent to GitHub.
foreach ($item in @(
    @{ Label = 'OpenSubtitles API key'; Name = 'opensub.dpapi'; EnvName = 'OPENSUBTITLES_API_KEY' },
    @{ Label = 'Gemini API key'; Name = 'gemini.dpapi'; EnvName = 'GEMINI_API_KEY' }
)) {
    $dest = Join-Path $secretsDir $item.Name
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        # If the owner already configured the key for this PowerShell
        # process, reuse it once without a needless repeat prompt. Do not
        # persist plaintext environment variables or echo their contents.
        $existingKey = [Environment]::GetEnvironmentVariable($item.EnvName, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($existingKey) -and
            $existingKey -notmatch '[\r\n]') {
            $entry = ConvertTo-SecureString -String $existingKey -AsPlainText -Force
            Write-Host 'OWNER_BRIDGE_EXISTING_OWNER_KEY_REUSED=YES'
        }
        else {
            $entry = Read-Host $item.Label -AsSecureString
        }
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

if ($null -eq $existing) {
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

# Copying updated sources while a scheduled task is Running does NOT
# replace the Python modules already loaded inside its process. Do not claim
# P3/P4 is activated or interrupt a possibly quota-bearing translation.
# Its normal owner task start at the next user logon will load staged source.
$state = (Get-ScheduledTask -TaskName $taskName -ErrorAction Stop).State
if ([string]$state -ceq 'Running') {
    Write-Host 'OWNER_BRIDGE_SOURCE_UPDATE=STAGED_NEXT_INTERACTIVE_TASK_START'
    Write-Host 'OWNER_BRIDGE_NEW_P3_P4_RUNTIME_ACTIVE=NOT_VERIFIED'
} else {
    Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
    Write-Host 'OWNER_BRIDGE_SOURCE_UPDATE=OWNER_TASK_START_REQUESTED'
    Write-Host 'OWNER_BRIDGE_NEW_P3_P4_RUNTIME_ACTIVE=NOT_VERIFIED'
}
Write-Host 'OWNER_BRIDGE_ONE_TIME_ENROLLMENT=COMPLETED'
Write-Host 'OWNER_BRIDGE_TASK_SCOPE=INTERACTIVE_OWNER_ONLY'
Write-Host 'OWNER_BRIDGE_RUNNER_ADMIN_GRANTED=NO'
Write-Host 'OWNER_BRIDGE_SRT_OR_API_KEY_COPIED_TO_GITHUB=NO'
Write-Host 'OWNER_BRIDGE_OMP_SELECTED_MEDIA_HOOK=REQUIRES_INTEGRATION'
