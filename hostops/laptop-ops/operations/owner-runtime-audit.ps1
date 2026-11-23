# Owner-context read-only installed-file attestation. No restarts, provider, P4 or media access.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -in
    @('S-1-5-18','S-1-5-19','S-1-5-20')) {
    throw 'OWNER_AUDIT_INTERACTIVE_OWNER_REQUIRED'
}
$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestPath = Join-Path $spool 'Requests\request.json'
if (-not (Test-Path -LiteralPath $requestPath -PathType Leaf)) {
    throw 'OWNER_AUDIT_REQUEST_MISSING'
}
$request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'OWNER_AUDIT_REQUEST_INVALID'
}
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$appRoot = Join-Path $ownerRoot 'app\poc\p2-sub-discovery'
$health = Join-Path $ownerRoot 'agent-health.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$taskState = 'UNKNOWN'
try {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\'
    $taskState = [string]$task.State
} catch {}
$heartbeat = 'NOT_VERIFIED'
try {
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        $h = Get-Content -LiteralPath $health -Raw -Encoding UTF8 | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$h.observed_utc_epoch
        if ($h.state -ceq 'READY' -and $age -ge 0 -and $age -le 10 -and
            [long]$h.pid -gt 0) {
            $proc = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
            if ($null -ne $proc -and
                [string]$proc.CommandLine -match 'owner_p3_p4_entrypoint[.]py') {
                $heartbeat = 'FRESH_PID_BOUND'
            }
        }
    }
} catch { $heartbeat = 'NOT_VERIFIED' }
$inflightCount = -1
try {
    $inflightCount = 0
    if (Test-Path -LiteralPath $stateRoot -PathType Container) {
        $inflightCount = @(Get-ChildItem -LiteralPath $stateRoot -File
            -Recurse -Filter 'batch-*.inflight' -ErrorAction Stop).Count
    }
} catch { $inflightCount = -1 }
$names = @(
    'owner_p3_p4_entrypoint.py',
    'owner_p3_p4_runtime.py',
    'p3_signed_signal_to_owner.py',
    'owner_session_bridge.py',
    'automatic_vietsub_flow.py',
    'brain_english_inbox.py',
    'owner_r2_progressive_registry.py',
    'owner_full_flow_snapshot_v4.py',
    'dual_subtitle_catalog.py',
    'p3_p4_shared_https_route_r0.py'
)
$modules = [ordered]@{}
foreach ($name in $names) {
    $file = Join-Path $appRoot $name
    $value = 'MISSING'
    try {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $info = Get-Item -LiteralPath $file -Force
            if ($info.Length -gt 0 -and $info.Length -le 1048576 -and
                -not ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $value = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            } else { $value = 'INVALID' }
        }
    } catch { $value = 'UNREADABLE' }
    $modules[$name] = $value
}
$report = [ordered]@{
    schema = 'TTV-OWNER-RUNTIME-AUDIT-V1'
    nonce = [string]$request.nonce
    observed_utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    task_state = $taskState
    heartbeat = $heartbeat
    inflight_count = $inflightCount
    modules = $modules
}
$outbox = Join-Path $spool 'Receipts'
$destination = Join-Path $outbox ('owner-runtime-' + $request.nonce + '.json')
if (Test-Path -LiteralPath $destination) { throw 'OWNER_AUDIT_RECEIPT_ALREADY_EXISTS' }
$raw = [Text.UTF8Encoding]::new($false).GetBytes(
    ($report | ConvertTo-Json -Depth 5 -Compress))
if ($raw.Length -gt 4096) { throw 'OWNER_AUDIT_RECEIPT_TOO_LARGE' }
$temp = Join-Path $outbox ('owner-runtime-' + $request.nonce + '.tmp')
try {
    [IO.File]::WriteAllBytes($temp, $raw)
    [IO.File]::Move($temp, $destination)
} finally {
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
Write-Output 'OWNER_RUNTIME_AUDIT=READ_ONLY_RECEIPT_WRITTEN'
