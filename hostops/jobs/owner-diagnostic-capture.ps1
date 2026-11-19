# Trusted HostOps only: start the Owner-enrolled, read-only diagnostic Task.
# The service never reads Owner-private files or runs private arbitrary code.
# Then consume only the sanitized, at-most-4KiB ProgramData snapshot.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $serviceSid -cne 'S-1-5-20') {
    throw 'HOSTOPS_OWNER_CAPTURE_TRUSTED_RUNNER_REQUIRED'
}

function GetTaskSid($Principal) {
    $id = [string]$Principal.UserId
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw 'HOSTOPS_OWNER_CAPTURE_TASK_PRINCIPAL_MISSING'
    }
    try {
        if ($id -match '^S-\d+(?:-\d+){2,}$') {
            return ([Security.Principal.SecurityIdentifier]::new($id)).Value
        }
        return ([Security.Principal.NTAccount]::new($id).Translate(
            [Security.Principal.SecurityIdentifier])).Value
    } catch {
        throw 'HOSTOPS_OWNER_CAPTURE_TASK_PRINCIPAL_UNRESOLVABLE'
    }
}

$ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' `
    -TaskPath '\' -ErrorAction Stop
if ([string]$ownerTask.State -cne 'Running') {
    Write-Output 'HOSTOPS_OWNER_CAPTURE=HOLD_OWNER_NOT_RUNNING'
    Write-Output 'HOSTOPS_OWNER_RESTART_OR_REPLAY=NOT_AUTHORIZED'
    return
}
$taskName = 'TorrentTV-Vietsub-Owner-Diagnostic-Capture'
try {
    $task = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
} catch {
    Write-Output 'HOSTOPS_OWNER_CAPTURE=HOSTOPS_SETUP_REQUIRED'
    Write-Output 'HOSTOPS_OWNER_CAPTURE_MISSING=OWNER_INTERACTIVE_DIAGNOSTIC_TASK'
    return
}
$count = if ($null -eq $task.Triggers) { 0 } else { @($task.Triggers).Count }
if ($task.State.ToString() -cne 'Ready' -or
    [string]$task.Description -cne 'TTV_OWNER_HOSTOPS_P3_P2_CAPTURE_READONLY_V1' -or
    [string]$task.Principal.LogonType -ine 'Interactive' -or
    [string]$task.Principal.RunLevel -ine 'Limited' -or
    (GetTaskSid $task.Principal) -cne (GetTaskSid $ownerTask.Principal) -or
    $count -ne 0 -or
    [string]$task.Settings.MultipleInstances -ine 'IgnoreNew' -or
    @($task.Actions).Count -ne 1) {
    throw 'HOSTOPS_OWNER_CAPTURE_TASK_IDENTITY_DRIFT'
}
$action = @($task.Actions)[0]
$exe = [string]$action.Execute
$argPattern = '(?i)\A-NoLogo -NoProfile -NonInteractive -File "[A-Z]:\\[^"\r\n]*\\TorrentTVVietsub\\OwnerBridge\\Maintenance\\owner-p2-snapshot-once\.ps1"\z'
if (-not [IO.Path]::IsPathRooted($exe) -or
    -not [IO.Path]::GetFileName($exe).Equals('pwsh.exe', [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::IsNullOrWhiteSpace([string]$action.WorkingDirectory) -or
    -not [regex]::IsMatch([string]$action.Arguments, $argPattern)) {
    throw 'HOSTOPS_OWNER_CAPTURE_TASK_ACTION_DRIFT'
}

$file = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
$beforeEpoch = -1L
try {
    if (Test-Path -LiteralPath $file -PathType Leaf) {
        $prior = Get-Item -LiteralPath $file -Force -ErrorAction Stop
        if ($prior.Length -gt 0 -and $prior.Length -le 4096 -and
            -not ($prior.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $beforeDoc = Get-Content -LiteralPath $file -Raw -Encoding UTF8 |
                ConvertFrom-Json -ErrorAction Stop
            if ($beforeDoc.snapshot_utc_epoch -is [ValueType]) {
                $beforeEpoch = [long]$beforeDoc.snapshot_utc_epoch
            }
        }
    }
} catch {
    # An untrusted old receipt must not become a precondition to Owner capture.
    $beforeEpoch = -1L
}

$startedLocal = Get-Date
$startedEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
try {
    Start-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
} catch {
    Write-Output 'HOSTOPS_OWNER_CAPTURE=HOSTOPS_SETUP_REQUIRED_TASK_EXECUTE'
    throw 'HOSTOPS_OWNER_CAPTURE_START_DENIED'
}
Write-Output 'HOSTOPS_OWNER_CAPTURE_TRIGGER=OWNER_TASK_START_REQUESTED'

$verified = $false
$failed = $false
$receiptVersion = 'V2'
for ($attempt = 0; $attempt -lt 50; $attempt++) {
    Start-Sleep -Seconds 1
    $nowTask = Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $info = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath '\' -ErrorAction Stop
    $thisRun = $info.LastRunTime -ge $startedLocal.AddSeconds(-3)
    if ($thisRun -and [string]$nowTask.State -ceq 'Ready' -and
        [long]$info.LastTaskResult -ne 0) {
        $failed = $true
        break
    }
    if (-not $thisRun -or [string]$nowTask.State -cne 'Ready' -or
        [long]$info.LastTaskResult -ne 0) { continue }
    try {
        $entry = Get-Item -LiteralPath $file -Force -ErrorAction Stop
        if ($entry.Length -le 0 -or $entry.Length -gt 4096 -or
            ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $receipt = Get-Content -LiteralPath $file -Raw -Encoding UTF8 |
            ConvertFrom-Json -ErrorAction Stop
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() -
            [long]$receipt.snapshot_utc_epoch
        if ($receipt.schema -cin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V2',
                                  'TTV-HOSTOPS-OWNER-SNAPSHOT-V3') -and
            [long]$receipt.snapshot_utc_epoch -gt $beforeEpoch -and
            [long]$receipt.snapshot_utc_epoch -ge ($startedEpoch - 3) -and
            $age -ge 0 -and $age -le 30) {
            $verified = $true
            if ($receipt.schema -ceq 'TTV-HOSTOPS-OWNER-SNAPSHOT-V3') {
                $receiptVersion = 'V3'
            }
            break
        }
    } catch {
        # A concurrent Owner atomic replacement can briefly race this read.
        continue
    }
}
if ($verified) {
    Write-Output "HOSTOPS_OWNER_CAPTURE=FRESH_${receiptVersion}_RECEIPT_VERIFIED"
} elseif ($failed) {
    Write-Output 'HOSTOPS_OWNER_CAPTURE=OWNER_TASK_FAILED_NO_RETRY'
} else {
    Write-Output 'HOSTOPS_OWNER_CAPTURE=TRIGGERED_NOT_VERIFIED'
}
Write-Output 'HOSTOPS_OWNER_CAPTURE_PRIVATE_DATA=NOT_ACCESSED_BY_RUNNER'
Write-Output 'HOSTOPS_OWNER_CAPTURE_OWNER_AGENT=NOT_RESTARTED'
Write-Output 'HOSTOPS_OWNER_CAPTURE_PROVIDER_TV=NOT_RUN_BY_RUNNER'

# Reuse the existing strict fixed-schema consumer, including independent P3/P2
# freshness checks. A successful capture does NOT imply P3 dispatch or P4 PASS.
& (Join-Path $PSScriptRoot 'owner-diagnostic-snapshot.ps1')
