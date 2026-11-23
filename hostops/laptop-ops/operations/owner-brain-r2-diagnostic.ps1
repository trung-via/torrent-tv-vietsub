# Owner-interactive read-only diagnosis of the LAST Brain R2 install attempt.
# Only fixed status fields and counters are reported to HostOps. No file changes to Owner app.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_BRAIN_DIAG_OWNER_SESSION_REQUIRED'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$request = Get-Content -LiteralPath (Join-Path $spool 'Requests\request.json') -Raw |
    ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    $request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_BRAIN_DIAG_REQUEST_INVALID'
}
$private = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\LaptopHostOps'
$reason = 'NO_PRIOR_BRAIN_INSTALL_LOG'
$priorLog = $false
if (Test-Path -LiteralPath $private -PathType Container) {
    $folders = @(Get-ChildItem -LiteralPath $private -Directory -Filter 'run-*' |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 12)
    foreach ($folder in $folders) {
        if ($folder.Name -ceq ('run-' + $request.nonce)) { continue }
        $log = Join-Path $folder.FullName 'full-owner-output.log'
        if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $log).Length -gt 4194304) { continue }
        $tail = @(Get-Content -LiteralPath $log -Tail 300 -ErrorAction SilentlyContinue)
        if (-not (@($tail | Where-Object {
            [string]$_ -match 'OWNER_BRAIN_R2(?:_|=)'
        }).Count -gt 0)) { continue }
        $priorLog = $true
        $hold = @($tail | ForEach-Object {
            if ([string]$_ -match 'OWNER_BRAIN_R2=HOLD_([A-Z0-9_]{3,75})') {
                $Matches[1]
            }
        } | Select-Object -Last 1)
        if ($hold.Count -eq 1) {
            $reason = 'HOLD_' + $hold[0]
        } elseif (@($tail | Where-Object {
            [string]$_ -match 'OWNER_BRAIN_R2_INSTALL_FAILED_ROLLED_BACK'
        }).Count -gt 0) {
            $reason = 'FAILED_ROLLED_BACK'
        } elseif (@($tail | Where-Object {
            [string]$_ -match 'OWNER_BRAIN_R2_INSTALL=14_FILES_HASH_VERIFIED_FRESH_OWNER_RUNNING'
        }).Count -gt 0) {
            $reason = 'INSTALL_SUCCEEDED_IN_LOG'
        } else {
            $reason = 'UNCLASSIFIED_PRIVATE_FAILURE'
        }
        break
    }
}
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$stage = Join-Path $ownerRoot 'staged-releases\owner-brain-en-182-r2-20261123-09c16d388ae3\poc\p2-sub-discovery'
$names = @(
    'automatic_vietsub_flow.py',
    'brain_english_inbox.py',
    'owner_p3_p4_runtime.py',
    'owner_r2_progressive_registry.py',
    'owner_session_bridge.py',
    'p3_p4_shared_https_route_r0.py',
    'p3_signed_signal_to_owner.py',
    'agy_opensubtitles_acquisition.py',
    'matcher.py',
    'opensubtitles.py',
    'owner_selected_file_resolver.py',
    'trusted_playback_to_owner.py',
    'p3_owner_current_redmi.py',
    'owner_r2_verified_processor.py'
)
$matched = 0
$missing = 0
$invalid = 0
foreach ($name in $names) {
    $src = Join-Path $stage $name
    $dest = Join-Path $app $name
    if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) {
        $missing++
        continue
    }
    try {
        $file = Get-Item -LiteralPath $dest -Force
        $release = Get-Item -LiteralPath $src -Force
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint -or
            $release.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $invalid++
            continue
        }
        $installedHash = (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash
        $stageHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        if ($installedHash -ceq $stageHash) { $matched++ }
    } catch { $invalid++ }
}
$task = [string](Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent').State
$heartbeat = 'NOT_VERIFIED'
try {
    $health = Get-Content -LiteralPath (Join-Path $ownerRoot 'agent-health.json') -Raw |
        ConvertFrom-Json
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$health.observed_utc_epoch
    if ($health.state -ceq 'READY' -and $age -ge 0 -and $age -le 20 -and
        [long]$health.pid -gt 0) {
        $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$health.pid)
        if ($p -and [string]$p.CommandLine -match 'owner_p3_p4_entrypoint[.]py') {
            $heartbeat = 'FRESH_PID_BOUND'
        }
    }
} catch {}
$record = [ordered]@{
    schema = 'TTV-OWNER-BRAIN-R2-DIAG-V1'
    nonce = [string]$request.nonce
    observed_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    prior_log = $priorLog
    reason = $reason
    task = $task
    heartbeat = $heartbeat
    matched = $matched
    missing = $missing
    invalid = $invalid
}
$outbox = Join-Path $spool 'Receipts'
$path = Join-Path $outbox ('owner-brain-r2-diagnostic-' + $request.nonce + '.json')
if (Test-Path -LiteralPath $path) { throw 'OWNER_BRAIN_DIAG_ALREADY_WRITTEN' }
$bytes = [Text.UTF8Encoding]::new($false).GetBytes(
    ($record | ConvertTo-Json -Compress))
if ($bytes.Length -gt 768) { throw 'OWNER_BRAIN_DIAG_TOO_LARGE' }
$temp = $path + '.tmp'
[IO.File]::WriteAllBytes($temp,$bytes)
[IO.File]::Move($temp,$path)
Write-Output 'OWNER_BRAIN_R2_DIAG=SANITIZED_RECEIPT_WRITTEN'
