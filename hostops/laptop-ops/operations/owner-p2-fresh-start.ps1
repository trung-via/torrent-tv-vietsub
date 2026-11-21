# One-time, owner-authorized fresh start for the exact quarantined P2 batch.
# Archive the whole old job before allowing a new TV request to translate from
# window one. Never call the provider, replay a blocked event, or clear TV data.
[CmdletBinding()]
param([switch]$ApplyClear)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $ApplyClear) { throw 'P2_FRESH_START_EXPLICIT_APPLY_REQUIRED' }
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0) {
    throw 'P2_FRESH_START_OWNER_INTERACTIVE_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_FRESH_START_OWNER_SESSION_MISMATCH'
}

$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
$actions = @($task.Actions)
if ([string]$task.State -cne 'Running' -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    $actions.Count -ne 1 -or
    [IO.Path]::GetFileName([string]$actions[0].Execute) -ine 'pwsh.exe' -or
    [string]$actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
    throw 'P2_FRESH_START_OWNER_TASK_CONTRACT_HOLD'
}
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$inbox = Join-Path $ownerRoot 'inbox'
$worker = Join-Path $ownerRoot 'app\poc\p2-aisub\automatic_lean120_worker.py'
$expectedWorkerSha = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
$expectedOriginalMarkerSha = '302e646ecf30301a9476be737a82f31484c9a25973abedab6da9d6a02999528f'

function AssertPlain([string]$Path, [bool]$Directory) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint -or
        ($Directory -and -not $item.PSIsContainer) -or
        (-not $Directory -and $item.PSIsContainer)) {
        throw 'P2_FRESH_START_UNTRUSTED_PATH'
    }
}
foreach ($path in @($ownerRoot, $stateRoot, $inbox)) { AssertPlain $path $true }
AssertPlain $worker $false
if ((Get-FileHash -LiteralPath $worker -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedWorkerSha) {
    throw 'P2_FRESH_START_INSTALLED_WORKER_DRIFT'
}
$inflight = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse -ErrorAction Stop)
$locks = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'active.lock' -Recurse -ErrorAction Stop)
$pending = @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json' -ErrorAction Stop)
if ($inflight.Count -ne 0 -or $locks.Count -ne 0 -or $pending.Count -ne 0) {
    throw 'P2_FRESH_START_BUSY_OR_UNRESOLVED_HOLD'
}

$ledgers = @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'batch-*.abandoned.json' -Recurse -ErrorAction Stop)
if ($ledgers.Count -ne 1 -or $ledgers[0].Name -cne 'batch-0001.abandoned.json' -or
    $ledgers[0].Directory.Name -cnotmatch '^[0-9a-f]{64}$') {
    throw 'P2_FRESH_START_EXACTLY_ONE_QUARANTINED_JOB_REQUIRED'
}
$ledger = $ledgers[0]
$folder = $ledger.Directory.FullName
if (-not $ledger.Directory.Parent.FullName.Equals(
        $stateRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P2_FRESH_START_NESTED_JOB_HOLD'
}
AssertPlain $folder $true
AssertPlain $ledger.FullName $false
$doc = Get-Content -LiteralPath $ledger.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if (@($doc.Keys | Sort-Object) -join ',' -cne
        'acknowledged_utc,job,marker_sha256,result,schema,version' -or
    $doc.schema -cne 'TTV-P2-ABANDONED-UNKNOWN-EFFECT-V1' -or
    $doc.result -cne 'UNKNOWN_EFFECT_NO_RETRY' -or
    $doc.job -cne $ledger.Directory.Name -or $doc.version -ne 1 -or
    $doc.marker_sha256 -cne $expectedOriginalMarkerSha) {
    throw 'P2_FRESH_START_QUARANTINE_LEDGER_MISMATCH'
}
$original = Join-Path $folder 'batch-0001.quarantined'
AssertPlain $original $false
if ((Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedOriginalMarkerSha -or
    (Test-Path -LiteralPath (Join-Path $folder 'batch-0001.json')) -or
    @(Get-ChildItem -LiteralPath $folder -File -Filter 'batch-*.json' -ErrorAction Stop |
        Where-Object { $_.Name -ne 'batch-0001.abandoned.json' }).Count -ne 0) {
    throw 'P2_FRESH_START_OLD_JOB_CONTENT_HOLD'
}
Write-Output 'P2_FRESH_START_PREFLIGHT=EXACT_QUARANTINED_JOB_IDLE'

# Keep the old job fully recoverable outside the translator's searchable root.
$archiveRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\ArchivedRetryJobs'
if (Test-Path -LiteralPath $archiveRoot) { AssertPlain $archiveRoot $true }
$archiveName = 'approved-fresh-' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + '-' +
    [Guid]::NewGuid().ToString('N')
$destination = Join-Path $archiveRoot $archiveName
$mutated = $false
$disabled = $false
try {
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $disabled = $true
    Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $stopped = $false
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        Start-Sleep -Seconds 1
        $python = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe' OR Name='py.exe'" -ErrorAction Stop)
        $remaining = @($python | Where-Object {
            [string]$_.CommandLine -match '(?i)owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
        })
        $uninspectable = @($python | Where-Object {
            [string]::IsNullOrWhiteSpace([string]$_.CommandLine)
        })
        $currentTask = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        if ($remaining.Count -eq 0 -and $uninspectable.Count -eq 0 -and
            [string]$currentTask.State -ceq 'Disabled') {
            $stopped = $true
            break
        }
    }
    if (-not $stopped) { throw 'P2_FRESH_START_OWNER_DID_NOT_STOP_HOLD' }
    # Recheck private state after stopping the only Owner process.
    if (@(Get-ChildItem -LiteralPath $stateRoot -File -Filter '*.inflight' -Recurse).Count -ne 0 -or
        @(Get-ChildItem -LiteralPath $stateRoot -File -Filter 'active.lock' -Recurse).Count -ne 0 -or
        @(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -ne 0) {
        throw 'P2_FRESH_START_STATE_CHANGED_AFTER_STOP'
    }
    if (-not (Test-Path -LiteralPath $archiveRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $archiveRoot -ErrorAction Stop | Out-Null
    }
    Move-Item -LiteralPath $folder -Destination $destination -ErrorAction Stop
    $mutated = $true
    if ((Test-Path -LiteralPath $folder) -or
        (Get-FileHash -LiteralPath (Join-Path $destination 'batch-0001.quarantined') -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedOriginalMarkerSha) {
        throw 'P2_FRESH_START_ARCHIVE_VERIFY_HOLD'
    }
    Write-Output 'P2_FRESH_START_OLD_JOB=ARCHIVED_RECOVERABLY'
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    $disabled = $false
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    Write-Output 'P2_FRESH_START_OWNER=START_REQUEST_ACCEPTED'
    Write-Output 'P2_FRESH_START_NEW_PROVIDER_CALL=NOT_RUN'
    Write-Output 'P2_FRESH_START_BLOCKED_EVENTS=NOT_REPLAYED'
} catch {
    if ($disabled -and -not $mutated) {
        # No P2 state was changed. Restore task availability without assuming
        # that a detached Owner process can be started twice safely.
        Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue | Out-Null
    }
    throw
}
