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
$phase = 'NOT_OBSERVED'
$errorKind = 'NONE'
$sourceLine = 0
if (Test-Path -LiteralPath $private -PathType Container) {
    $folders = @(Get-ChildItem -LiteralPath $private -Directory -Filter 'run-*' |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 12)
    foreach ($folder in $folders) {
        if ($folder.Name -ceq ('run-' + $request.nonce)) { continue }
        # The previous diagnostic's own log also contains OWNER_BRAIN_R2.
        # Select the actual failed install using its Owner-private manifest,
        # never by a broad substring match of arbitrary log text.
        $manifestFile = Join-Path $folder.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf) -or
            (Get-Item -LiteralPath $manifestFile).Length -gt 8192) { continue }
        try {
            $priorManifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json
            if ($priorManifest.operation -cne 'owner-brain-r2-install') { continue }
        } catch { continue }
        $log = Join-Path $folder.FullName 'full-owner-output.log'
        if (-not (Test-Path -LiteralPath $log -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $log).Length -gt 4194304) { continue }
        $tail = @(Get-Content -LiteralPath $log -Tail 300 -ErrorAction SilentlyContinue)
        $priorLog = $true
        $joined = $tail -join [string][char]10
        if ($joined.Contains('OWNER_BRAIN_R2_BACKUP=ALL_14_ORIGINALS_RECORDED')) {
            $phase = 'BACKUP_CREATED'
        } elseif ($joined.Contains('OWNER_BRAIN_R2_PREFLIGHT=PASS_OWNER_RUNNING_IDLE_STAGED_IMPORT')) {
            $phase = 'PREFLIGHT_COMPLETE'
        } else { $phase = 'BEFORE_PREFLIGHT' }
        if ($joined -match '(?i)owner-brain-r2-install[.]ps1:(\d{1,3})' -or
            $joined -match '(?i)operation[.]ps1:(\d{1,3})') {
            $sourceLine = [int]$Matches[1]
        }
        if ($joined -match 'PropertyNotFoundException|property.*cannot be found') {
            $errorKind = 'PS_MISSING_PROPERTY'
        } elseif ($joined -match 'CommandNotFoundException|term.*not recognized') {
            $errorKind = 'PS_COMMAND_NOT_FOUND'
        } elseif ($joined -match 'ParserError|Unexpected token') {
            $errorKind = 'PS_PARSE'
        } elseif ($joined -match 'ParameterBindingException|Cannot bind argument') {
            $errorKind = 'PS_ARGUMENT'
        } elseif ($joined -match 'FileNotFoundException|PathNotFound') {
            $errorKind = 'FILE_NOT_FOUND'
        } elseif ($joined -match 'OperationStopped|RuntimeException') {
            $errorKind = 'PS_RUNTIME'
        } else { $errorKind = 'OTHER_PRIVATE_EXCEPTION' }
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
# One discriminating offline import probe of the identical staged overlay.
# Python prints only fixed source module and exception categories; no media/AGY.
$overlayStatus = 'NO_PYTHON_RESULT'
$overlayAt = 'NONE'
$overlayMissing = 'NONE'
$overlayError = 'NONE'
$probePython = @'
import importlib, pathlib, sys, re
stage, app = (pathlib.Path(p) for p in sys.argv[1:3])
sys.path[:0] = [str(stage / "poc/p2-sub-discovery"),
                str(app / "poc/p2-sub-discovery"),
                str(app / "poc/p2-aisub"),
                str(app / "poc/p3-vietsub-trigger")]
names = ("brain_english_inbox", "automatic_vietsub_flow",
         "owner_p3_p4_runtime", "owner_r2_progressive_registry",
         "p3_signed_signal_to_owner", "owner_session_bridge",
         "owner_p3_p4_entrypoint")
for name in names:
    try:
        mod = importlib.import_module(name)
        if not str(mod.__file__).lower().startswith(str(stage).lower()):
            print("TTV_R2_IMPORT=FAIL:" + name + ":WRONG_IMPORT_PATH:NONE")
            sys.exit(0)
    except Exception as error:
        typ = type(error).__name__
        if typ not in ("ModuleNotFoundError", "ImportError", "SyntaxError",
                       "AttributeError", "TypeError", "ValueError",
                       "AssertionError", "RuntimeError"):
            typ = "OTHER"
        missing = getattr(error, "name", None) or name
        if not re.fullmatch(r"[a-zA-Z0-9_]{1,80}", str(missing)):
            missing = "OTHER"
        print("TTV_R2_IMPORT=FAIL:" + name + ":" + typ + ":" + str(missing))
        sys.exit(0)
print("TTV_R2_IMPORT=PASS:NONE:NONE:NONE")
'@
try {
    $stageRoot = Split-Path (Split-Path $stage -Parent) -Parent
    $out = @(& py -3 -I -B -c $probePython $stageRoot (Join-Path $ownerRoot 'app') 2>&1)
    $hits = @($out | ForEach-Object {
        if ([string]$_ -match '^TTV_R2_IMPORT=(PASS|FAIL):([A-Za-z0-9_]{2,80}):([A-Za-z0-9_]{2,80}):([A-Za-z0-9_]{2,80})$') {
            @($Matches[1],$Matches[2],$Matches[3],$Matches[4]) -join ':'
        }
    } | Select-Object -Last 1)
    if ($hits.Count -eq 1) {
        $parts = ([string]$hits[0]).Split(':')
        $overlayStatus,$overlayAt,$overlayError,$overlayMissing = $parts
    }
} catch {
    $overlayStatus = 'PYTHON_LAUNCH_FAILED'
}
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
    phase = $phase
    error_kind = $errorKind
    source_line = $sourceLine
    overlay_status = $overlayStatus
    overlay_at = $overlayAt
    overlay_error = $overlayError
    overlay_missing = $overlayMissing
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
