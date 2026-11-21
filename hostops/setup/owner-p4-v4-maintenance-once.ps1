# Interactive Owner-only, exact-stage 23-module V2 media-key install.
# Default is read-only Inspect. -Apply needs explicit physical viewer-off
# confirmation; no provider call, P2 checkpoint clear, or TV/ADB action.
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$ViewerOffConfirmed,
    [switch]$Rollback,
    [ValidatePattern('^owner-p4-v4-[0-9a-f]{32}$')][string]$BackupId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stageCommit = 'a3da96d0730cd2ff7fcf7345c0f7c900d568a975'
$manifestSha = '75fdb89a54cbccbb783c75022c99aa2fee91db57432e8ed27e48eb6dea6a75ef'
$taskName = 'TorrentTV-Vietsub-OwnerAgent'
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$app = Join-Path $ownerRoot 'app'
$stage = Join-Path $ownerRoot ('staged-releases\owner-p4-native-178-v4-' + $stageCommit.Substring(0,12))
$healthPath = Join-Path $ownerRoot 'agent-health.json'
$snapshotPath = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\P2\auto-lean120-state'
$ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if (($Apply -and $Rollback) -or ($Apply -and -not $ViewerOffConfirmed) -or
    ($Rollback -and [string]::IsNullOrWhiteSpace($BackupId)) -or
    (-not $Rollback -and -not [string]::IsNullOrWhiteSpace($BackupId))) {
    throw 'OWNER_P4_V4_MODE_INVALID'
}
function Hold([string]$why) {
    Write-Output ('OWNER_P4_V4=HOLD_' + $why)
    throw 'OWNER_P4_V4_HOLD'
}
function Directory([string]$p) {
    if (-not (Test-Path -LiteralPath $p -PathType Container) -or
        ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'DIRECTORY_UNTRUSTED'
    }
}
function File([string]$p) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or
        ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Hold 'FILE_UNTRUSTED'
    }
}
function Hash([string]$p) {
    return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Workers {
    @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.Name -in @('py.exe','python.exe','pythonw.exe') -and
        [string]$_.CommandLine -match 'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py'
    })
}
function Task {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $sid = [string]$task.Principal.UserId
    if ($sid -notmatch '^S-\d+(?:-\d+){2,}$') {
        $sid = ([Security.Principal.NTAccount]::new($sid).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    }
    if ($sid -cne $ownerSid -or [string]$task.Principal.LogonType -ine 'Interactive' -or
        @($task.Actions).Count -ne 1 -or
        -not [IO.Path]::GetFileName([string]$task.Actions[0].Execute).Equals(
            'pwsh.exe',[StringComparison]::OrdinalIgnoreCase) -or
        [string]$task.Actions[0].Arguments -notmatch '(?i)start-owner-session-agent\.ps1') {
        Hold 'OWNER_TASK_IDENTITY_DRIFT'
    }
    return $task
}
function NoOpenWork {
    $inbox = Join-Path $ownerRoot 'inbox'
    Directory $inbox
    if (@(Get-ChildItem -LiteralPath $inbox -File -Filter 'event-*.json').Count -gt 0) {
        Hold 'OWNER_PENDING_EVENTS'
    }
    if (Test-Path -LiteralPath $stateRoot) {
        Directory $stateRoot
        if (@(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'batch-*.inflight').Count -gt 0 -or
            @(Get-ChildItem -LiteralPath $stateRoot -File -Recurse -Filter 'active.lock').Count -gt 0) {
            Hold 'P2_UNCERTAIN_OR_ACTIVE'
        }
    }
}
function SnapshotGate {
    File $snapshotPath
    $item = Get-Item -LiteralPath $snapshotPath -Force
    if ($item.Length -le 0 -or $item.Length -gt 4096) { Hold 'OWNER_SNAPSHOT_SIZE_INVALID' }
    $s = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$s.snapshot_utc_epoch
    if ($s.schema -cnotin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V2',
                           'TTV-HOSTOPS-OWNER-SNAPSHOT-V3',
                           'TTV-HOSTOPS-OWNER-SNAPSHOT-V4') -or
        $s.status -cne 'READY_FRESH' -or $s.mode -cne 'INTEGRATED_P3_P4' -or
        $age -lt 0 -or $age -gt 20 -or
        [string]$s.p2.status -cne 'CLEAR' -or
        [long]$s.p2.pending_events -ne 0 -or [long]$s.p2.inflight_count -ne 0) {
        Hold 'OWNER_NOT_FRESH_OR_P2_NOT_IDLE'
    }
    # STALE cannot prove TV OFF. It is accepted only after the person
    # explicitly confirms the film was closed and AI toggle is OFF.
    if ($s.p3_state -cne 'FRESH_OFF' -and
        -not ($ViewerOffConfirmed -and $s.p3_state -ceq 'STALE')) {
        Hold 'TV_OFF_NOT_CONFIRMED'
    }
}
function StopOwner {
    $t = Task
    if ([string]$t.State -ceq 'Running') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
        Stop-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    } elseif ([string]$t.State -ceq 'Ready') {
        Disable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    } elseif ([string]$t.State -cne 'Disabled') { Hold 'OWNER_TASK_UNEXPECTED_STATE' }
    for ($n=0;$n -lt 10;$n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    $workers = @(Workers)
    if ($workers.Count -gt 4) { Hold 'RESIDUAL_WORKER_COUNT_UNEXPECTED' }
    $allowed = @((Join-Path $app 'poc\p2-sub-discovery\owner_p3_p4_entrypoint.py'),
                 (Join-Path $app 'poc\p2-sub-discovery\owner_session_bridge.py'))
    foreach ($w in $workers) {
        $matches = @($allowed | Where-Object {
            [string]$w.CommandLine -and $w.CommandLine.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0
        })
        $sid = Invoke-CimMethod -InputObject $w -MethodName GetOwnerSid
        if ($matches.Count -ne 1 -or $null -eq $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_IDENTITY_UNVERIFIED'
        }
    }
    foreach ($w in $workers) {
        NoOpenWork
        if ([string](Task).State -cne 'Disabled') { Hold 'OWNER_TASK_REENABLED' }
        $live = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$w.ProcessId)
        if ($null -eq $live) { continue }
        $sid = Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid
        if ($live.CommandLine -cne $w.CommandLine -or $live.CreationDate -ne $w.CreationDate -or
            $sid.ReturnValue -ne 0 -or $sid.Sid -cne $ownerSid) {
            Hold 'RESIDUAL_WORKER_CHANGED'
        }
        Stop-Process -Id ([int]$w.ProcessId) -Force -ErrorAction Stop
    }
    for ($n=0;$n -lt 10;$n++) {
        if (@(Workers).Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    Hold 'OWNER_WORKERS_STILL_RUNNING'
}
function StartAndVerify([long]$beforePid) {
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    Enable-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop | Out-Null
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    for ($n=0;$n -lt 40;$n++) {
        Start-Sleep -Seconds 1
        if ([string](Task).State -cne 'Running' -or
            -not (Test-Path -LiteralPath $healthPath -PathType Leaf)) { continue }
        try {
            $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
            if ($h.schema -cne 'TTV-OWNER-AGENT-HEALTH-V1' -or
                $h.state -cne 'READY' -or [long]$h.pid -le 0 -or
                [long]$h.pid -eq $beforePid -or
                [long]$h.observed_utc_epoch -lt ($since-2)) { continue }
            $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$h.pid)
            if ($null -eq $p -or [string]$p.CommandLine -notmatch
                'owner_p3_p4_entrypoint\.py|owner_session_bridge\.py') { continue }
            $sid = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid
            if ($sid.ReturnValue -eq 0 -and $sid.Sid -ceq $ownerSid) { return $true }
        } catch { continue }
    }
    return $false
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ($PSVersionTable.PSVersion.Major -lt 7 -or $env:GITHUB_ACTIONS -ceq 'true' -or
    -not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $ownerSid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or
    [string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged,[StringComparison]::OrdinalIgnoreCase)) {
    Hold 'INTERACTIVE_OWNER_PWSH7_REQUIRED'
}
foreach ($d in @($ownerRoot,$app,$stage)) { Directory $d }
$task = Task
NoOpenWork
if (-not $Rollback) {
    if ([string]$task.State -cne 'Running') { Hold 'OWNER_MUST_BE_RUNNING_FOR_FRESH_PREFLIGHT' }
    SnapshotGate
}
$receipt = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\ReleaseReceipts\stage.json'
File $receipt
$sr = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
if ($sr.schema -cne 'TTV-OWNER-RELEASE-STAGE-RECEIPT-V1' -or
    $sr.source_commit -cne $stageCommit -or
    $sr.result -cne 'STAGED_VERIFIED_INSTALLED_UNCHANGED') {
    Hold 'OWNER_STAGING_RECEIPT_MISMATCH'
}
$manifestFile = Join-Path $env:TEMP ('ttv-v4-manifest-' + [Guid]::NewGuid().ToString('N') + '.json')
try {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $stageCommit + '/hostops/releases/owner-p4-v4-stage-v1.json'
    Invoke-WebRequest -Uri $uri -OutFile $manifestFile -ErrorAction Stop
    File $manifestFile
    if ((Hash $manifestFile) -cne $manifestSha) { Hold 'OWNER_MANIFEST_PIN_MISMATCH' }
    $manifest = Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json -AsHashtable
    if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
        $manifest.release_id -cne 'p4-native-178-v4' -or
        $manifest.source_tree -cne 'e5f01545cb415720dea4a5e36825212546828639' -or
        $manifest.mode -cne 'STAGE_ONLY' -or @($manifest.files).Count -ne 23) {
        Hold 'OWNER_MANIFEST_SCHEMA_INVALID'
    }
    $rows = [ordered]@{}
    foreach ($f in $manifest.files) {
        $rel = [string]$f.path
        if ($rel -cnotmatch '\Apoc/(p2-aisub|p2-sub-discovery)/[a-z0-9_]+\.py\z' -or
            $rows.Contains($rel) -or [string]$f.sha256 -cnotmatch '\A[0-9a-f]{64}\z') {
            Hold 'OWNER_MANIFEST_FILE_INVALID'
        }
        $candidate = Join-Path $stage $rel.Replace('/','\')
        File $candidate
        if ((Hash $candidate) -cne $f.sha256) { Hold 'OWNER_STAGED_FILE_SHA_MISMATCH' }
        $parent = Join-Path $app ((Split-Path -Parent $rel).Replace('/','\'))
        if (Test-Path -LiteralPath $parent) { Directory $parent }
        $target = Join-Path $app $rel.Replace('/','\')
        if (Test-Path -LiteralPath $target) { File $target }
        $rows[$rel] = [string]$f.sha256
    }
    Write-Output 'OWNER_P4_V4_STAGE=23_FILES_HASH_VERIFIED'
    if (-not $Apply -and -not $Rollback) {
        Write-Output 'OWNER_P4_V4=READ_ONLY_INSPECT_PASS'
        return
    }
    $recovery = Join-Path $ownerRoot 'recovery'
    if ($Rollback) {
        if ([string](Task).State -cne 'Disabled' -or @(Workers).Count -ne 0) {
            Hold 'ROLLBACK_OWNER_MUST_BE_STOPPED'
        }
        Directory $recovery
        $backup = Join-Path $recovery $BackupId
        Directory $backup
        $ledgerFile = Join-Path $backup 'ledger.json'
        File $ledgerFile
        $ledger = Get-Content -LiteralPath $ledgerFile -Raw | ConvertFrom-Json -AsHashtable
        if ($ledger.schema -cne 'TTV-OWNER-P4-V4-BACKUP-V1' -or
            $ledger.source_commit -cne $stageCommit -or
            @($ledger.old.Keys).Count -ne $rows.Count) { Hold 'ROLLBACK_LEDGER_INVALID' }
        foreach ($rel in $rows.Keys) {
            if (-not $ledger.old.ContainsKey($rel)) { Hold 'ROLLBACK_PATH_MISSING' }
            $target = Join-Path $app $rel.Replace('/','\')
            File $target
            if ((Hash $target) -cne $rows[$rel]) { Hold 'ROLLBACK_NEW_BYTES_DRIFT' }
            if ($ledger.old[$rel] -cne 'ABSENT') {
                $saved = Join-Path $backup $rel.Replace('/','\')
                File $saved
                if ((Hash $saved) -cne [string]$ledger.old[$rel]) { Hold 'ROLLBACK_BACKUP_DRIFT' }
            }
        }
        foreach ($rel in $rows.Keys) {
            $target = Join-Path $app $rel.Replace('/','\')
            if ($ledger.old[$rel] -ceq 'ABSENT') {
                [IO.File]::Delete($target)
            } else {
                $temp = Join-Path (Split-Path -Parent $target) ('.p4-v4-rollback-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy((Join-Path $backup $rel.Replace('/','\')),$temp,$false)
                [IO.File]::Move($temp,$target,$true)
            }
        }
        Write-Output 'OWNER_P4_V4=ROLLBACK_VERIFIED_OWNER_STOPPED'
        return
    }
    NoOpenWork
    $oldPid = 0L
    if (Test-Path -LiteralPath $healthPath -PathType Leaf) {
        try { $h = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json; $oldPid = [long]$h.pid }
        catch { $oldPid = 0L }
    }
    StopOwner
    NoOpenWork
    if (-not (Test-Path -LiteralPath $recovery)) {
        New-Item -ItemType Directory -Path $recovery -ErrorAction Stop | Out-Null
    }
    Directory $recovery
    $newBackup = 'owner-p4-v4-' + [Guid]::NewGuid().ToString('N')
    $backup = Join-Path $recovery $newBackup
    New-Item -ItemType Directory -Path $backup -ErrorAction Stop | Out-Null
    $old = [ordered]@{}
    foreach ($rel in $rows.Keys) {
        $target = Join-Path $app $rel.Replace('/','\')
        $old[$rel] = 'ABSENT'
        if (Test-Path -LiteralPath $target) {
            File $target
            $old[$rel] = Hash $target
            $saved = Join-Path $backup $rel.Replace('/','\')
            $savedDir = Split-Path -Parent $saved
            if (-not (Test-Path -LiteralPath $savedDir)) {
                New-Item -ItemType Directory -Path $savedDir -Force -ErrorAction Stop | Out-Null
            }
            [IO.File]::Copy($target,$saved,$false)
            if ((Hash $saved) -cne $old[$rel]) { Hold 'BACKUP_HASH_MISMATCH' }
        }
    }
    $ledger = @{schema='TTV-OWNER-P4-V4-BACKUP-V1'; source_commit=$stageCommit; old=$old}
    [IO.File]::WriteAllText((Join-Path $backup 'ledger.json'),
        ($ledger | ConvertTo-Json -Depth 7 -Compress),[Text.UTF8Encoding]::new($false))
    Write-Output ('OWNER_P4_V4_BACKUP_ID=' + $newBackup)
    $changed = [Collections.Generic.List[string]]::new()
    try {
        foreach ($rel in $rows.Keys) {
            if ([string](Task).State -cne 'Disabled' -or @(Workers).Count -ne 0) {
                Hold 'OWNER_RESTARTED_DURING_INSTALL'
            }
            NoOpenWork
            $target = Join-Path $app $rel.Replace('/','\')
            if ($old[$rel] -ceq 'ABSENT') {
                if (Test-Path -LiteralPath $target) { Hold 'TARGET_CREATED_AFTER_BACKUP' }
            } elseif ((Hash $target) -cne $old[$rel]) { Hold 'TARGET_CHANGED_AFTER_BACKUP' }
            $parent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
            }
            $temp = Join-Path $parent ('.p4-v4-' + [Guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::Copy((Join-Path $stage $rel.Replace('/','\')),$temp,$false)
            if ((Hash $temp) -cne $rows[$rel]) { Hold 'TEMP_HASH_MISMATCH' }
            [IO.File]::Move($temp,$target,$true)
            $changed.Add($rel)
            if ((Hash $target) -cne $rows[$rel]) { Hold 'INSTALLED_HASH_MISMATCH' }
        }
        if (-not (StartAndVerify $oldPid)) { throw 'OWNER_P4_V4_NEW_HEARTBEAT_MISSING' }
        Write-Output 'OWNER_P4_V4=APPLIED_23_NEW_OWNER_HEALTH_VERIFIED'
        Write-Output 'OWNER_P4_V4_P2_CHECKPOINTS=UNCHANGED'
        Write-Output 'OWNER_P4_V4_TV_APK=NOT_INSTALLED_BY_THIS_SCRIPT'
    } catch {
        StopOwner
        NoOpenWork
        foreach ($rel in $changed) {
            $target = Join-Path $app $rel.Replace('/','\')
            if ($old[$rel] -ceq 'ABSENT') {
                if (Test-Path -LiteralPath $target) { [IO.File]::Delete($target) }
            } else {
                $temp = Join-Path (Split-Path -Parent $target) ('.p4-v4-recover-' + [Guid]::NewGuid().ToString('N') + '.tmp')
                [IO.File]::Copy((Join-Path $backup $rel.Replace('/','\')),$temp,$false)
                [IO.File]::Move($temp,$target,$true)
                if ((Hash $target) -cne $old[$rel]) { Hold 'RECOVERY_HASH_MISMATCH_OWNER_DISABLED' }
            }
        }
        if (-not (StartAndVerify $oldPid)) { Hold 'RECOVERED_OWNER_HEARTBEAT_MISSING' }
        Hold 'NEW_OWNER_FAILED_OLD_OWNER_RECOVERED'
    }
} finally {
    if (Test-Path -LiteralPath $manifestFile -PathType Leaf) {
        Remove-Item -LiteralPath $manifestFile -Force -ErrorAction SilentlyContinue
    }
}
