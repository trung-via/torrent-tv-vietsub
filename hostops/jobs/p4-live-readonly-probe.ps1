# Torrent TV PR #162: read-only physical preflight from dedicated Windows runner.
# NEVER install APK, push subtitles, start LAN listener or access private owner keys.
# Public workflow logs MUST NOT contain ADB serial/IP, usernames, media names or secrets.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'P4_READONLY_WRONG_RUNNER'
}
Write-Host 'P4_LIVE_READONLY_PROBE_START'
Write-Host 'P4_PROBE_SCOPE=READ_ONLY_NO_INSTALL_NO_API_NO_SUBTITLE_NO_LAN_MUTATION'
Write-Host 'P4_EXPECTED_PR=162'
Write-Host 'P4_EXPECTED_SOURCE_SHA=f484818d97fbd7bb892c399b41f71e1f59593e19'

# Runner is not the interactive Windows owner. Never claim access to DPAPI.
$sessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId
$interactive = [Environment]::UserInteractive
Write-Host ('P4_RUNNER_INTERACTIVE=' + ($interactive -and $sessionId -gt 0).ToString().ToUpperInvariant())
Write-Host ('P4_RUNNER_SESSION0=' + ($sessionId -eq 0).ToString().ToUpperInvariant())

# Read-only query of the existing owner agent task. Access denial is inconclusive.
try {
    $ownerTask = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -ErrorAction Stop
    Write-Host 'P4_OWNER_TASK_QUERY=PRESENT'
    Write-Host ('P4_OWNER_TASK_RUNNING=' + ($ownerTask.State -eq 'Running').ToString().ToUpperInvariant())
} catch {
    Write-Host 'P4_OWNER_TASK_QUERY=NOT_ACCESSIBLE_OR_NOT_FOUND'
}
try {
    $ts = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -match '^(torrserver|torrserver-windows|torrserver-matrixtv)$' })
    Write-Host ('P4_TORRSERVER_PROCESS_VISIBLE=' + ($ts.Count -gt 0).ToString().ToUpperInvariant())
} catch {
    Write-Host 'P4_TORRSERVER_PROCESS_VISIBLE=UNKNOWN'
}

# Probing a known candidate localhost port is non-destructive; it is NOT a
# claim about the actual deployed TorrServer port or /torrents schema.
try {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $pending = $client.BeginConnect('127.0.0.1', 8090, $null, $null)
        $reached = $pending.AsyncWaitHandle.WaitOne(1200, $false)
        if ($reached) {
            try { $client.EndConnect($pending); $connected = $true }
            catch { $connected = $false }
        } else { $connected = $false }
        Write-Host ('P4_TORRSERVER_CANDIDATE_8090_TCP=' + $connected.ToString().ToUpperInvariant())
    } finally { $client.Dispose() }
} catch {
    Write-Host 'P4_TORRSERVER_CANDIDATE_8090_TCP=UNKNOWN'
}

# ADB read-only device/APP metadata. No ADB shell writes, push, reboot,
# install, logcat/private content, or device selection if multiple targets.
$adb = Get-Command adb.exe -ErrorAction SilentlyContinue
if ($null -eq $adb) {
    Write-Host 'P4_ADB=NOT_INSTALLED_ON_RUNNER'
    Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=NOT_TESTED'
    Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
    exit 0
}
Write-Host 'P4_ADB=FOUND'
try {
    $rows = @(& $adb.Source devices 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_FAILED' }
    $connectedRows = @($rows | Where-Object { $_ -match '^([^\s]+)\s+(device|unauthorized|offline)(\s|$)' })
    $authorized = @($connectedRows | Where-Object { $_ -match '^([^\s]+)\s+device(\s|$)' })
    Write-Host ('P4_ADB_AUTHORIZED_COUNT=' + $authorized.Count)
    Write-Host ('P4_ADB_UNAVAILABLE_COUNT=' + ($connectedRows.Count - $authorized.Count))
    if ($connectedRows.Count -ne 1 -or $authorized.Count -ne 1) {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_NO_UNIQUE_AUTHORIZED_ADB_DEVICE'
        Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
        exit 0
    }
    $serial = ([regex]::Match($authorized[0], '^([^\s]+)\s+device(\s|$)')).Groups[1].Value
    if ($serial -notmatch '^[a-zA-Z0-9.:-]{1,128}$') {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_INVALID_SERIAL'
        Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
        exit 0
    }
    $model = @(& $adb.Source -s $serial shell getprop ro.product.model 2>$null)
    Write-Host ('P4_ANDROID_MODEL_READABLE=' + ($LASTEXITCODE -eq 0 -and $model.Count -gt 0).ToString().ToUpperInvariant())
    $packages = @(& $adb.Source -s $serial shell pm list packages 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_PM_FAILED' }
    $isOmp = @($packages | Where-Object { $_ -match '^package:com\.spacesarmat\.omp\s*$' }).Count -gt 0
    Write-Host ('P4_OMP_PACKAGE_INSTALLED=' + $isOmp.ToString().ToUpperInvariant())
    if (-not $isOmp) {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_OMP_APP_NOT_FOUND'
    } else {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=DEVICE_REACHABLE_ONLY_PAIRED_LAN_NOT_TESTED'
    }
} catch {
    Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_READONLY_ADB_PROBE_FAILED'
}
Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
