# Owner-interactive, offline, read-only discriminator AFTER successful V2 probe.
# Does not start the Owner, bind LAN, invoke any provider, read credentials,
# alter queues/checkpoints, repair secrets, or retry a translation batch.
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'TTV_RUNTIME_PROBE_VERSION=V3_OFFLINE_STAGES'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_WINDOWS_REQUIRED'
    exit 2
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
if (-not [Environment]::UserInteractive -or $session -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_INTERACTIVE_OWNER_REQUIRED'
    exit 2
}

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
try {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction Stop
    $configured = [string]$task.Principal.UserId
    $sid = if ($configured -match '^S-1-') {
        $configured
    } else {
        ([Security.Principal.NTAccount]::new($configured)).Translate(
            [Security.Principal.SecurityIdentifier]).Value
    }
    if ($sid -cne $identity.User.Value -or
        [string]$task.Principal.LogonType -ne 'Interactive') {
        throw 'WRONG_TASK_OWNER'
    }
} catch {
    Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_TASK_OWNER'
    exit 2
}
Write-Host ('TTV_RUNTIME_TASK_LAST_RESULT=' + [string]$taskInfo.LastTaskResult)

$homeRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
$ownerRoot = Join-Path $homeRoot 'OwnerBridge'
$sub = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$cache = Join-Path $homeRoot 'subtitle-trials'
$state = Join-Path $homeRoot 'P2\auto-lean120-state'

# Health is an existing small private receipt; output only fixed state/age
# categories. A stale receipt must not be promoted to a live Owner process.
$healthResult = 'ABSENT_OR_INVALID'
$healthFile = Join-Path $ownerRoot 'agent-health.json'
try {
    if (Test-Path -LiteralPath $healthFile -PathType Leaf) {
        $item = Get-Item -LiteralPath $healthFile -ErrorAction Stop
        if ($item.Length -le 512 -and
            -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $h = Get-Content -LiteralPath $healthFile -Raw -ErrorAction Stop |
                ConvertFrom-Json -ErrorAction Stop
            if ([string]$h.schema -ceq 'TTV-OWNER-AGENT-HEALTH-V1' -and
                [string]$h.state -in @('STARTING','BLOCKED','READY','STOPPED') -and
                $h.observed_utc_epoch -is [ValueType]) {
                $timestamp = [DateTimeOffset]::FromUnixTimeSeconds(
                    [long]$h.observed_utc_epoch).LocalDateTime
                $ageFromRun = ($timestamp - $taskInfo.LastRunTime).TotalSeconds
                if ($ageFromRun -ge -5 -and $ageFromRun -le 90) {
                    $healthResult = 'AT_LAST_TASK_' + [string]$h.state
                } else {
                    $healthResult = 'OLDER_OR_UNRELATED_TO_LAST_TASK'
                }
            }
        }
    }
} catch {
    $healthResult = 'ABSENT_OR_INVALID'
}
Write-Host ('TTV_RUNTIME_HEALTH=' + $healthResult)

foreach ($module in @(
    (Join-Path $sub 'automatic_vietsub_flow.py'),
    (Join-Path $sub 'owner_session_bridge.py'),
    (Join-Path $sub 'owner_p3_p4_runtime.py'),
    (Join-Path $ownerRoot 'app\poc\p2-aisub\translator_profile.json')
)) {
    if (-not (Test-Path -LiteralPath $module -PathType Leaf)) {
        Write-Host 'TTV_RUNTIME_FLOW_INIT=SOURCE_MISSING'
        Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_FLOW_SOURCE'
        exit 2
    }
}

# The exact installed auto-flow constructors are exercised without user
# credentials. -B suppresses pycache writes. Transport sockets and urllib
# are disabled BEFORE importing the installed modules. No real media is read.
$smoke = @'
import os, socket, sys, urllib.request
from pathlib import Path
def no_transport(*args, **kwargs):
    raise RuntimeError("OFFLINE_PROBE_NO_NETWORK")
socket.socket.connect = no_transport
socket.socket.connect_ex = no_transport
socket.socket.bind = no_transport
socket.socket.listen = no_transport
urllib.request.urlopen = no_transport
urllib.request.build_opener = no_transport
os.environ["OPENSUBTITLES_API_KEY"] = "TTV_OFFLINE_PLACEHOLDER_NOT_A_CREDENTIAL"
os.environ.pop("GEMINI_API_KEY", None)
os.environ.pop("GOOGLE_API_KEY", None)
sub, cache, state = map(Path, sys.argv[1:4])
sys.path[:0] = [str(sub), str(sub.parent / "p2-aisub"),
                str(sub.parent / "p3-vietsub-trigger")]
try:
    from automatic_vietsub_flow import build_owner_auto_flow
    from lean120_api import load_profile
    from translator_gateway import provider_enabled
    from owner_vietsub_pipeline import _P2
except Exception:
    print("IMPORT_FAILED")
    sys.exit(2)
try:
    profile = load_profile(_P2 / "translator_profile.json")
    if not provider_enabled(profile.provider):
        raise ValueError("PROVIDER_DISABLED")
except Exception:
    print("PROFILE_FAILED")
    sys.exit(3)
try:
    flow = build_owner_auto_flow(
        enabled=True, cache_root=cache, state_root=state)
    if not callable(getattr(flow, "selected_media", None)):
        raise ValueError("FLOW_INVALID")
except Exception:
    print("INIT_FAILED")
    sys.exit(4)
print("PASS")
'@
try {
    $output = @(& py -3 -B -c $smoke $sub $cache $state 2>$null)
    $exitCode = $LASTEXITCODE
    $signal = if ($output.Count -eq 1) { ([string]$output[0]).Trim() } else { '' }
    if ($exitCode -eq 0 -and $signal -ceq 'PASS') {
        Write-Host 'TTV_RUNTIME_FLOW_INIT=PASS_OFFLINE'
        Write-Host 'TTV_RUNTIME_PROBE_RESULT=STAGE_PASS_LIVE_RUNTIME_UNVERIFIED'
        exit 0
    }
    $category = switch ($signal) {
        'IMPORT_FAILED' { 'IMPORT_FAILED' }
        'PROFILE_FAILED' { 'PROFILE_FAILED' }
        'INIT_FAILED' { 'INIT_FAILED' }
        default { 'PYTHON_OR_SIGNAL_FAILED' }
    }
    Write-Host ('TTV_RUNTIME_FLOW_INIT=' + $category)
    Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_FLOW_INITIALIZATION'
    exit 2
} catch {
    Write-Host 'TTV_RUNTIME_FLOW_INIT=PYTHON_OR_SIGNAL_FAILED'
    Write-Host 'TTV_RUNTIME_PROBE_RESULT=HOLD_FLOW_INITIALIZATION'
    exit 2
}
