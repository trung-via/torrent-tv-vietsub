# Read-only Owner-session inspection after a failed one-shot P2 clear.
# The runner sees only fixed status enums and bounded counts, never paths,
# media names, private exception strings, or translation payloads.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$result = [ordered]@{
    schema = 'TTV-P2-FRESH-INSPECT-V2'
    utc_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    status = 'HOLD'
    phase = 'IDENTITY'
    task_state = 'UNKNOWN'
    task_contract = 'UNKNOWN'
    abandoned_count = -1
    archived_count = -1
    inflight_count = -1
    lock_count = -1
    pending_count = -1
    owner_python_count = -1
    uninspectable_python_count = -1
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
    if ($env:GITHUB_ACTIONS -ceq 'true' -or
        [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
        $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
        [string]::IsNullOrWhiteSpace($logged) -or
        -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'P2_FRESH_INSPECT_V2_IDENTITY_HOLD'
    }

    $result.phase = 'TASK'
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
    $result.task_state = [string]$task.State
    $action = @($task.Actions)
    if ($action.Count -eq 1 -and
        [string]$task.Principal.LogonType -ieq 'Interactive' -and
        [IO.Path]::GetFileName([string]$action[0].Execute) -ieq 'pwsh.exe' -and
        [string]$action[0].Arguments -match '(?i)start-owner-session-agent\.ps1') {
        $result.task_contract = 'MATCH'
    } else { $result.task_contract = 'MISMATCH' }
    if ($result.task_state -cnotin @('Running','Ready','Disabled')) {
        throw 'P2_FRESH_INSPECT_V2_UNKNOWN_TASK'
    }

    $result.phase = 'STATE'
    $stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
    $archiveRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\ArchivedRetryJobs'
    $inbox = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\inbox'
    if (-not (Test-Path -LiteralPath $stateRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $inbox -PathType Container)) {
        throw 'P2_FRESH_INSPECT_V2_STATE_ROOT_MISSING'
    }
    $result.abandoned_count = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'batch-*.abandoned.json' -Recurse -ErrorAction Stop).Count
    $result.inflight_count = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse -ErrorAction Stop).Count
    $result.lock_count = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'active.lock' -Recurse -ErrorAction Stop).Count
    $result.pending_count = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json' -ErrorAction Stop).Count
    $result.archived_count = if (Test-Path -LiteralPath $archiveRoot -PathType Container) {
        @(Get-ChildItem -LiteralPath $archiveRoot -Directory -Filter 'approved-fresh-*' -ErrorAction Stop).Count
    } else { 0 }

    $result.phase = 'PROCESSES'
    $python = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
    $result.owner_python_count = @($python | Where-Object {
        [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    }).Count
    $result.uninspectable_python_count = @($python | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.CommandLine)
    }).Count
    $result.status = 'OBSERVED'
    $result.phase = 'COMPLETE'
} catch {
    # Phase only: never serialize exception text or a private pathname.
    $result.status = 'HOLD'
}

try {
    $receiptDir = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps\Receipts'
    if (-not (Test-Path -LiteralPath $receiptDir -PathType Container)) {
        throw 'P2_FRESH_INSPECT_V2_RECEIPT_DIRECTORY_MISSING'
    }
    $output = Join-Path $receiptDir 'p2-fresh-inspect-v2.json'
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($result | ConvertTo-Json -Compress))
    if ($bytes.Length -gt 512) { throw 'P2_FRESH_INSPECT_V2_RECEIPT_TOO_LARGE' }
    $temp = $output + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllBytes($temp, $bytes)
    [IO.File]::Move($temp, $output, $true)
    Write-Output 'P2_FRESH_INSPECT_V2=SANITIZED_RECEIPT_WRITTEN'
} catch {
    # Constant code only, so the private Owner log remains safe to inspect.
    Write-Output 'P2_FRESH_INSPECT_V2=RECEIPT_WRITE_FAILED'
    exit 1
}
