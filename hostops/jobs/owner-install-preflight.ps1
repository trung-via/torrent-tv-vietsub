# Read-only Owner installation preflight via trusted issue #82 HostOps.
# No app/module mutation, no provider call, no TV command and no private paths.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'OWNER_INSTALL_PREFLIGHT_RUNNER_IDENTITY_REQUIRED'
}

$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
Write-Output ('OWNER_PREFLIGHT_TASK_STATE=' + [string]$task.State)
Write-Output ('OWNER_PREFLIGHT_TASK_ACTION_COUNT=' + @($task.Actions).Count)
Write-Output ('OWNER_PREFLIGHT_OWNER_LOGON=' + [string]$task.Principal.LogonType)
if (@($task.Actions).Count -eq 1) {
    $action = @($task.Actions)[0]
    Write-Output ('OWNER_PREFLIGHT_PWSH=' + $(if (
        [IO.Path]::GetFileName([string]$action.Execute) -ieq 'pwsh.exe') { 'YES' } else { 'NO' }))
    Write-Output ('OWNER_PREFLIGHT_ORIGINAL_LAUNCHER=' + $(if (
        [string]$action.Arguments -match '(?i)start-owner-session-agent\.ps1') { 'YES' } else { 'NO' }))
}
foreach ($name in @('TorrentTV-Vietsub-Laptop-HostOps',
                   'TorrentTV-Vietsub-Owner-Release-Stage')) {
    $bridge = Get-ScheduledTask -TaskName $name -TaskPath '\' -ErrorAction SilentlyContinue
    $key = $(if ($name -like '*Laptop*') { 'LAPTOP_OPS' } else { 'RELEASE_STAGE' })
    $value = $(if ($null -eq $bridge) { 'NOT_ENROLLED' } else { [string]$bridge.State })
    Write-Output ('OWNER_PREFLIGHT_' + $key + '=' + $value)
}

$file = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
    Write-Output 'OWNER_PREFLIGHT_SNAPSHOT=MISSING'
    return
}
$item = Get-Item -LiteralPath $file -Force -ErrorAction Stop
if ($item.Length -le 0 -or $item.Length -gt 8192 -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Write-Output 'OWNER_PREFLIGHT_SNAPSHOT=INVALID_SIZE_OR_LINK'
    return
}
try {
    $report = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Output 'OWNER_PREFLIGHT_SNAPSHOT=INVALID_JSON'
    return
}
$schema = [string]$report.schema
Write-Output ('OWNER_PREFLIGHT_SCHEMA=' + $(if ($schema -cmatch '^TTV-HOSTOPS-OWNER-SNAPSHOT-V[1-9]$') { $schema } else { 'UNKNOWN' }))
if ($report.PSObject.Properties.Name -contains 'snapshot_utc_epoch') {
    $seconds = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$report.snapshot_utc_epoch
    Write-Output ('OWNER_PREFLIGHT_SNAPSHOT_AGE_SECONDS=' + $seconds)
}
if ($report.PSObject.Properties.Name -contains 'p2' -and $null -ne $report.p2) {
    $p2 = $report.p2
    foreach ($field in @('status','pending_events','inflight_count','active_lock_present','outcome')) {
        if ($p2.PSObject.Properties.Name -contains $field) {
            $value = [string]$p2.$field
            if ($value -cmatch '^[A-Za-z0-9_-]{1,50}$') {
                Write-Output ('OWNER_PREFLIGHT_P2_' + $field.ToUpperInvariant() + '=' + $value)
            }
        }
    }
}
Write-Output 'OWNER_PREFLIGHT_EFFECT=READ_ONLY'
