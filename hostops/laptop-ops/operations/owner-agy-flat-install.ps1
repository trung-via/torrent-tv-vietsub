# Owner-interactive, source-pinned one-path AGY upgrade.
# Downloads no movie/subtitle, invokes no model, changes no cache/checkpoints.
# Source files must already be staged by the separate Owner release task.
[CmdletBinding()]
param([switch]$Apply)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCommit = 'c4081d8e51d7b857fafcc5abc105d44844587285'
$manifestSha = '4d04209fc1248d5655ed792c09bfa83aa8dc1a03c91eb7d5771c02c5b01613f8'
$releaseName = 'agy-flat-179-r1'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $root 'app'
$installed = Join-Path $app 'poc\p2-sub-discovery'
$p2Modules = Join-Path $app 'poc\p2-aisub'
$stage = Join-Path $root ('staged-releases\owner-' + $releaseName + '-' +
    $sourceCommit.Substring(0,12))
$health = Join-Path $root 'agent-health.json'
$state = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Hold([string]$code) {
    Write-Output ('OWNER_AGY_FLAT=HOLD_' + $code)
    throw 'OWNER_AGY_FLAT_HOLD'
}
function SafeDirectory([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Container) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) { Hold 'DIRECTORY_UNTRUSTED' }
}
function SafeFile([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        ((Get-Item -LiteralPath $path -Force).Attributes -band
            [IO.FileAttributes]::ReparsePoint)) { Hold 'FILE_UNTRUSTED' }
}
function Hash([string]$path) {
    (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function NoOpenWork {
    $inbox = Join-Path $root 'inbox'
    SafeDirectory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'PENDING_OWNER_REQUEST'
    }
    if (Test-Path -LiteralPath $state) {
        SafeDirectory $state
        foreach ($pattern in @('batch-*.inflight', 'active.lock')) {
            if (@(Get-ChildItem -LiteralPath $state -File -Recurse -Filter $pattern).Count -gt 0) {
                Hold 'P2_ACTIVE_OR_UNKNOWN'
            }
        }
    }
    # Discovery can run AGY before a translation batch creates an inflight marker.
    # Do not terminate an AGY process, even if it could belong to another project.
    $agents = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('agy.exe','antigravity.exe') -or
        ([string]$_.CommandLine -match '(?i)(^|\s)agy(?:\.cmd|\.exe)?(\s|$)')
    })
    if ($agents.Count -gt 0) { Hold 'AGY_PROCESS_PRESENT' }
}
function OwnerWorkers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function CheckTask {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne $ownerSid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function StopOwner {
    $task = CheckTask
    if ([string]$task.State -in @('Running','Ready')) {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        if ([string]$task.State -eq 'Running') {
            Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
        }
    } elseif ([string]$task.State -ne 'Disabled') { Hold 'OWNER_TASK_STATE_UNEXPECTED' }
    for ($i=0;$i -lt 5;$i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    NoOpenWork
    $workers = @(OwnerWorkers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT' }
    $allowed = @((Join-Path $installed 'owner_p3_p4_entrypoint.py'),
                 (Join-Path $installed 'owner_session_bridge.py'))
    foreach ($worker in $workers) {
        $match = @($allowed | Where-Object {
            [string]$worker.CommandLine -and
            $worker.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $identity = Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid
        if ($match.Count -ne 1 -or $null -eq $worker.CreationDate -or
            $identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($worker in $workers) {
        NoOpenWork
        if ([string](CheckTask).State -cne 'Disabled') { Hold 'OWNER_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$worker.ProcessId)
        if ($null -eq $live) { continue }
        $id = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $worker.CommandLine -or
            $live.CreationDate -ne $worker.CreationDate -or
            $id.ReturnValue -ne 0 -or $id.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_CHANGED'
        }
        Stop-Process -Id ([int]$worker.ProcessId) -Force -ErrorAction Stop
    }
    for ($i=0;$i -lt 10;$i++) {
        if (@(OwnerWorkers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'RESIDUAL_WORKERS_NOT_STOPPED'
}
function StartAndVerify([long]$previousPid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($i=0;$i -lt 35;$i++) {
        Start-Sleep -Seconds 1
        if ([string](CheckTask).State -cne 'Running' -or
            -not (Test-Path -LiteralPath $health -PathType Leaf)) { continue }
        try {
            $h = Get-Content -LiteralPath $health -Raw | ConvertFrom-Json
            if ($h.state -cne 'READY' -or [long]$h.pid -eq $previousPid -or
                [long]$h.observed_utc_epoch -lt ($since - 2)) { continue }
            $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
            if ($null -eq $process -or
                [string]$process.CommandLine -notmatch 'owner_p3_p4_entrypoint\.py') { continue }
            $identity = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid
            if ($identity.ReturnValue -ne 0 -or $identity.Sid -cne $ownerSid) { continue }
            return $true
        } catch { continue }
    }
    return $false
}

if ($env:GITHUB_ACTIONS -ceq 'true' -or -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    -not [string](Get-CimInstance Win32_ComputerSystem).UserName) {
    Hold 'INTERACTIVE_OWNER_REQUIRED'
}
$interactive = [string](Get-CimInstance Win32_ComputerSystem).UserName
if (-not ([Security.Principal.WindowsIdentity]::GetCurrent().Name).Equals(
        $interactive,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'SIGNED_IN_OWNER_CHANGED'
}
foreach ($dir in @($root,$app,$installed,$p2Modules,$stage,
                   (Join-Path $root 'staged-releases'))) { SafeDirectory $dir }
$task = CheckTask
if ([string]$task.State -cnotin @('Running','Ready')) { Hold 'OWNER_TASK_NOT_AVAILABLE' }
NoOpenWork
if ($null -eq (Get-Command agy -ErrorAction SilentlyContinue)) {
    Hold 'AGY_CLI_NOT_ON_OWNER_PATH'
}
if ($null -eq (Get-Command py -ErrorAction SilentlyContinue)) {
    Hold 'OWNER_PYTHON_NOT_AVAILABLE'
}

# The pinned immutable release manifest enumerates exactly 31 permitted files.
$tempManifest = Join-Path $env:TEMP ('ttv-agy-manifest-' +
    [Guid]::NewGuid().ToString('N') + '.json')
$manifestUri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
    $sourceCommit + '/hostops/releases/owner-agy-flat-179-v1.json'
Invoke-WebRequest -Uri $manifestUri -OutFile $tempManifest -ErrorAction Stop
try {
    SafeFile $tempManifest
    if ((Get-Item -LiteralPath $tempManifest).Length -gt 8192 -or
        (Hash $tempManifest) -cne $manifestSha) { Hold 'MANIFEST_HASH_MISMATCH' }
    $manifest = Get-Content -LiteralPath $tempManifest -Raw -Encoding UTF8 |
        ConvertFrom-Json -AsHashtable
    if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
        $manifest.release_id -cne $releaseName -or
        $manifest.source_tree -cne '47726ef48719d3e807e764c3454dea44c2887ff0' -or
        $manifest.mode -cne 'STAGE_ONLY' -or
        $manifest.files -isnot [array] -or $manifest.files.Count -ne 31) {
        Hold 'MANIFEST_SCOPE_INVALID'
    }
    $files = [ordered]@{}
    foreach ($f in $manifest.files) {
        $rel = [string]$f.path
        if ($rel -cnotmatch '\Apoc/(p2-aisub|p2-sub-discovery)/(?!test_)[a-z0-9_]+\.py\z' -or
            [string]$f.sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
            $files.Contains($rel)) { Hold 'MANIFEST_ENTRY_INVALID' }
        $files[$rel] = [string]$f.sha256
        $source = Join-Path $stage ($rel.Replace('/','\'))
        $target = Join-Path $app ($rel.Replace('/','\'))
        SafeFile $source
        SafeDirectory (Split-Path -Parent $target)
        if ((Hash $source) -cne $files[$rel]) { Hold 'STAGED_BYTES_DRIFT' }
        if (Test-Path -LiteralPath $target) { SafeFile $target }
    }
    Write-Output 'OWNER_AGY_FLAT_STAGE=31_SHA256_PASS'
    # No pending events, no uncertain batch, no AGY subprocess. Check again
    # immediately before stopping Owner, and after stop before any writes.
    NoOpenWork
    if (-not $Apply) {
        Write-Output 'OWNER_AGY_FLAT=PRECHECK_READY_NO_INSTALL'
        return
    }
    $previousPid = 0L
    if (Test-Path -LiteralPath $health -PathType Leaf) {
        try { $previousPid = [long](Get-Content -LiteralPath $health -Raw |
            ConvertFrom-Json).pid } catch { $previousPid = 0L }
    }
    StopOwner
    NoOpenWork
    $backups = Join-Path $root ('backups\owner-agy-flat-' +
        [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($backups) | Out-Null
    $previous = [ordered]@{}
    $changed = [Collections.Generic.List[string]]::new()
    try {
        # Save and verify every original before changing a single module.
        foreach ($rel in $files.Keys) {
            NoOpenWork
            if ([string](CheckTask).State -cne 'Disabled') { Hold 'OWNER_REENABLED' }
            $target = Join-Path $app ($rel.Replace('/','\'))
            if (Test-Path -LiteralPath $target) {
                SafeFile $target
                $saved = Join-Path $backups ($rel.Replace('/','\'))
                [IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
                [IO.File]::Copy($target,$saved,$false)
                $previous[$rel] = Hash $saved
                if ((Hash $target) -cne $previous[$rel]) { Hold 'BACKUP_MISMATCH' }
            } else { $previous[$rel] = 'ABSENT' }
        }
        $ledger = [ordered]@{
            schema = 'TTV-OWNER-AGY-FLAT-ROLLBACK-V1'
            source_commit = $sourceCommit
            previous = $previous
        }
        [IO.File]::WriteAllText((Join-Path $backups 'ledger.json'),
            ($ledger | ConvertTo-Json -Depth 5),
            [Text.UTF8Encoding]::new($false))
        foreach ($rel in $files.Keys) {
            NoOpenWork
            if ([string](CheckTask).State -cne 'Disabled') { Hold 'OWNER_REENABLED' }
            $target = Join-Path $app ($rel.Replace('/','\'))
            $source = Join-Path $stage ($rel.Replace('/','\'))
            if ((Hash $source) -cne $files[$rel]) { Hold 'STAGE_CHANGED_DURING_INSTALL' }
            if ($previous[$rel] -ceq 'ABSENT') {
                if (Test-Path -LiteralPath $target) { Hold 'NEW_TARGET_APPEARED' }
            } elseif ((Hash $target) -cne $previous[$rel]) {
                Hold 'OWNER_BASELINE_CHANGED'
            }
            $next = Join-Path (Split-Path -Parent $target) (
                '.agy-flat-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy($source,$next,$false)
            if ((Hash $next) -cne $files[$rel]) { Hold 'TEMP_BYTES_MISMATCH' }
            $changed.Add($rel)
            if ($previous[$rel] -ceq 'ABSENT') {
                [IO.File]::Move($next,$target)
            } else {
                $displaced = Join-Path $backups (
                    'displaced-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Replace($next,$target,$displaced)
            }
            if ((Hash $target) -cne $files[$rel]) { Hold 'INSTALLED_BYTES_MISMATCH' }
        }
        # Import modules without opening a LAN listener or invoking AGY.
        $oldPythonPath = $env:PYTHONPATH
        try {
            $env:PYTHONPATH = $installed + ';' + $p2Modules +
                $(if ($oldPythonPath) { ';' + $oldPythonPath } else { '' })
            Push-Location -LiteralPath $installed
            try {
                & py -3 -B -c 'import owner_p3_p4_entrypoint; import agy_opensubtitles_acquisition; print("OWNER_AGY_FLAT_IMPORT_PASS")'
                if ($LASTEXITCODE -ne 0) { throw 'OWNER_AGY_FLAT_OFFLINE_IMPORT_FAILED' }
            } finally { Pop-Location }
        } finally { $env:PYTHONPATH = $oldPythonPath }
        if (-not (StartAndVerify $previousPid)) {
            throw 'OWNER_AGY_FLAT_NEW_HEARTBEAT_UNVERIFIED'
        }
        Write-Output 'OWNER_AGY_FLAT=INSTALLED_FRESH_OWNER_READY'
        Write-Output 'OWNER_AGY_FLAT_PROVIDER_TV=NOT_INVOKED'
    } catch {
        $original = $_
        Write-Output 'OWNER_AGY_FLAT=ROLLBACK_ATTEMPTED'
        try {
            StopOwner
            for ($index=$changed.Count-1;$index -ge 0;$index--) {
                $rel = $changed[$index]
                NoOpenWork
                $target = Join-Path $app ($rel.Replace('/','\'))
                if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                    if ($previous[$rel] -ceq 'ABSENT') { continue }
                    Hold 'ROLLBACK_PREVIOUS_TARGET_MISSING'
                }
                SafeFile $target
                $currentHash = Hash $target
                if ($currentHash -ceq $previous[$rel]) { continue }
                if ($currentHash -cne $files[$rel]) { Hold 'ROLLBACK_TARGET_DRIFT' }
                if ($previous[$rel] -ceq 'ABSENT') {
                    [IO.File]::Delete($target) # Only a file introduced by this installer.
                } else {
                    $saved = Join-Path $backups ($rel.Replace('/','\'))
                    SafeFile $saved
                    if ((Hash $saved) -cne $previous[$rel]) { Hold 'ROLLBACK_BACKUP_DRIFT' }
                    $restore = Join-Path (Split-Path -Parent $target) (
                        '.agy-restore-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Copy($saved,$restore,$false)
                    $discard = Join-Path $backups (
                        'failed-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                    [IO.File]::Replace($restore,$target,$discard)
                }
            }
            if (-not (StartAndVerify $previousPid)) { Hold 'ROLLBACK_OWNER_NOT_READY' }
            Write-Output 'OWNER_AGY_FLAT=ROLLBACK_OLD_OWNER_READY'
        } catch {
            Write-Output 'OWNER_AGY_FLAT=ROLLBACK_RECOVERY_REQUIRED'
            throw
        }
        throw $original
    }
} finally {
    if (Test-Path -LiteralPath $tempManifest -PathType Leaf) {
        Remove-Item -LiteralPath $tempManifest -Force -ErrorAction SilentlyContinue
    }
}
