# One-time preservation-first P2 batch-0011 quarantine approved by the Owner.
# No provider/TV call, no replay, no deletion of committed translation content.
# The running Owner task is left DISABLED after the unknown-effect tombstone.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedBatch = 'batch-0011'
$expectedMarker = '40f98035778158467cce7b8e2016166763a3f5085381c0b90e2349e19f7252c5'
$sourceCommit = 'cac462c1dd854a7b19fd0eb02018c9bd1aebb7fe'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'

function Hold([string]$code) { throw ('OWNER_P2_B11_QUARANTINE_HOLD_' + $code) }
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function StopVerifiedOwnerWorkers {
    for ($i=0; $i -lt 8; $i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $remaining = @(OwnerWorkers)
    if ($remaining.Count -gt 4) { Hold 'UNEXPECTED_OWNER_WORKER_COUNT' }
    $appRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app\poc\p2-sub-discovery'
    $allowed = @((Join-Path $appRoot 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $appRoot 'owner_session_bridge.py'))
    foreach ($worker in $remaining) {
        $matchesPath = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $owner = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid -ErrorAction Stop
        if ($matchesPath.Count -ne 1 -or $owner.ReturnValue -ne 0 -or
            $owner.Sid -cne $identity.User.Value -or $null -eq $worker.CreationDate) {
            Hold 'OWNER_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $remaining) {
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    if (@(OwnerWorkers).Count -ne 0) { Hold 'OWNER_WORKER_STILL_PRESENT' }
    Write-Output 'OWNER_P2_B11_RESIDUAL_WORKERS=VERIFIED_STOPPED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$loggedUser = [string](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $identity.User.Value -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($loggedUser) -or
    -not $identity.Name.Equals($loggedUser,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}

# Reconstitute the previously reviewed offline reconciler in an isolated stage.
# Its installed-worker comparison and tombstone-first ordering are unchanged.
$files = [ordered]@{
    'hostops/setup/p2-inflight-reconcile-offline.ps1' = '7121616cf9286776400bb0cbfb6ce970121014688ed0175a348f42d4be10b21d'
    'hostops/setup/owner-p2-snapshot-once.ps1' = '5ea41dfbcddd4b447dc1bf839a3048654e89f1a2c31a6e50fe3945ae70a753f4'
    'poc/p2-aisub/automatic_lean120_worker.py' = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'
    'poc/p2-sub-discovery/owner-task-principal-identity.ps1' = '9fd3c43f10cf9694d6ecc396aae6a3e6fc724a51750c7d51a2d287d431f778d9'
    'poc/p2-sub-discovery/owner-task-action-identity.ps1' = 'f3c497123af4d38c806aa631684e0a77fa926285c4d31ccba8d88f802cb27caf'
}
$stage = Join-Path $env:TEMP ('ttv-p2-b11-quarantine-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($stage) | Out-Null
try {
    foreach ($path in $files.Keys) {
        $target = Join-Path $stage $path
        [IO.Directory]::CreateDirectory((Split-Path -Path $target -Parent)) | Out-Null
        $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' + $sourceCommit + '/' + $path
        Invoke-WebRequest -Uri $uri -OutFile $target -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $files[$path]) {
            Hold 'RECONCILER_SOURCE_HASH_MISMATCH'
        }
    }
    $reconciler = Join-Path $stage 'hostops/setup/p2-inflight-reconcile-offline.ps1'
    $snapshot = Join-Path $stage 'hostops/setup/owner-p2-snapshot-once.ps1'

    $inspection = @(& pwsh -NoProfile -File $reconciler)
    if ($LASTEXITCODE -ne 0) { Hold 'READ_ONLY_INSPECTION_FAILED' }
    $f = @{}
    foreach ($line in $inspection) {
        if ($line -cmatch '^(P2_RECONCILE_[A-Z0-9_]+)=(.*)$') { $f[$Matches[1]] = $Matches[2] }
    }
    if ($f['P2_RECONCILE_RESULT'] -cne 'INSPECT_ONLY_NO_CHANGES' -or
        $f['P2_RECONCILE_INFLIGHT_COUNT'] -cne '1' -or
        $f['P2_RECONCILE_BATCH'] -cne $expectedBatch -or
        $f['P2_RECONCILE_MARKER_SHA256'] -cne $expectedMarker -or
        $f['P2_RECONCILE_CHECKPOINT_PRESENT'] -cne 'False' -or
        $f['P2_RECONCILE_ACTIVE_LOCK_PRESENT'] -cne 'False' -or
        $f['P2_RECONCILE_PENDING_EVENTS'] -cne '0' -or
        $f['P2_RECONCILE_INSTALLED_NO_RETRY_WORKER_MATCH'] -cne 'True' -or
        $f['P2_RECONCILE_TASK_STATE'] -cne 'Running') {
        Hold 'CURRENT_BATCH_PREFLIGHT_CHANGED'
    }
    $ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub'
    $marker = @(Get-ChildItem -LiteralPath (Join-Path $ownerRoot 'P2\auto-lean120-state') -Recurse -File -Filter 'batch-0011.inflight')
    if ($marker.Count -ne 1) { Hold 'MARKER_PATH_AMBIGUOUS' }
    foreach ($name in @('batch-0011.abandoned.json','batch-0011.quarantined')) {
        if (Test-Path -LiteralPath (Join-Path $marker[0].DirectoryName $name)) { Hold 'ALREADY_RECONCILED' }
    }
    Write-Output 'OWNER_P2_B11_PREFLIGHT=PASS_MARKER_HASH_AND_NO_RETRY_WORKER'

    # Atomic no-retry protection is performed by the reviewed reconciler, not here.
    # If anything fails after disabling, leave the task disabled for inspection.
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    if ([string]$task.State -cne 'Running') { Hold 'OWNER_TASK_STATE_DRIFT' }
    Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Write-Output 'OWNER_P2_B11_OWNER_TASK=DISABLED'
    try {
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        Start-Sleep -Seconds 3
        # Some launcher descendants survive Task Scheduler stop. Only known
        # same-Owner, exact-installed worker commands may be terminated.
        StopVerifiedOwnerWorkers
        $outcome = @(& pwsh -NoProfile -File $reconciler -ApplyQuarantine `
            -AcknowledgeUnknownEffect -ExpectedMarkerSha256 $expectedMarker)
        if ($LASTEXITCODE -ne 0 -or
            $outcome -cnotcontains 'P2_RECONCILE_RESULT=UNKNOWN_EFFECT_QUARANTINED_NO_RETRY' -or
            $outcome -cnotcontains 'P2_RECONCILE_ORIGINAL_MARKER_BYTES=PRESERVED') {
            Hold 'OFFLINE_QUARANTINE_NOT_PROVEN'
        }
    } catch {
        Write-Output 'OWNER_P2_B11_RESULT=HOLD_TASK_DISABLED_NO_RETRY'
        throw
    }
    Write-Output 'OWNER_P2_B11_RESULT=UNKNOWN_EFFECT_QUARANTINED_NO_RETRY'
    Write-Output 'OWNER_P2_B11_ORIGINAL_MARKER=PRESERVED'
    try {
        $after = @(& pwsh -NoProfile -File $snapshot)
        if ($LASTEXITCODE -eq 0 -and
            $after -ccontains 'OWNER_P2_SNAPSHOT_EXPORT=SUCCESS' -and
            $after -ccontains 'OWNER_P2_SNAPSHOT_INFLIGHT_COUNT=0') {
            Write-Output 'OWNER_P2_B11_HOSTOPS_SNAPSHOT=EXPORTED'
        } else { Write-Output 'OWNER_P2_B11_HOSTOPS_SNAPSHOT=NOT_VERIFIED' }
    } catch { Write-Output 'OWNER_P2_B11_HOSTOPS_SNAPSHOT=NOT_VERIFIED' }
    Write-Output 'OWNER_P2_B11_OWNER_TASK=LEFT_DISABLED_FOR_PINNED_INSTALL'
    Write-Output 'OWNER_P2_B11_PROVIDER_AND_TV=NOT_CALLED'
} finally {
    # Only the GUID-scoped scratch directory is disposable; P2 state is retained.
    if (Test-Path -LiteralPath $stage -PathType Container) {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
