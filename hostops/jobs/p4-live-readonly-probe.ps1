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
        if ($connected) {
            try {
                $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:8090/echo' -Method Get -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop
                Write-Host ('P4_TORRSERVER_CANDIDATE_8090_ECHO_HTTP=' + [int]$resp.StatusCode)
            } catch {
                Write-Host 'P4_TORRSERVER_CANDIDATE_8090_ECHO_HTTP=UNVERIFIED'
            }
        }
    } finally { $client.Dispose() }
} catch {
    Write-Host 'P4_TORRSERVER_CANDIDATE_8090_TCP=UNKNOWN'
}

# ADB read-only device/APP metadata. No ADB shell writes, push, reboot,
# install, logcat/private content, or device selection if multiple targets.
# An Android build runner may keep platform-tools outside PATH.
$adb = Get-Command adb.exe -ErrorAction SilentlyContinue
$adbPath = if ($null -ne $adb) { $adb.Source } else { $null }
if ($null -eq $adbPath) {
    $candidates = @()
    foreach ($sdkRoot in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)) {
        if (-not [string]::IsNullOrWhiteSpace($sdkRoot)) {
            $candidates += Join-Path $sdkRoot 'platform-tools\adb.exe'
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
    }
    $candidates += @(
        'C:\TOOL\Android\Sdk\platform-tools\adb.exe',
        'C:\TOOL\android-sdk\platform-tools\adb.exe',
        'C:\Android\platform-tools\adb.exe',
        'C:\platform-tools\adb.exe'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $adbPath = $candidate
            break
        }
    }
}
if ($null -eq $adbPath) {
    Write-Host 'P4_ADB=NOT_FOUND_PATH_OR_STANDARD_SDK_ROOTS'
    Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=NOT_TESTED'
    Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
    exit 0
}
Write-Host 'P4_ADB=FOUND'
try {
    $rows = @(& $adbPath devices 2>$null)
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
    # Sanitized model/brand hints only; never echo ADB serial, model or user paths.
    $model = @(& $adbPath -s $serial shell getprop ro.product.model 2>$null)
    $modelOk = $LASTEXITCODE -eq 0 -and $model.Count -gt 0
    $brand = @(& $adbPath -s $serial shell getprop ro.product.brand 2>$null)
    $brandOk = $LASTEXITCODE -eq 0 -and $brand.Count -gt 0
    Write-Host ('P4_ANDROID_MODEL_READABLE=' + $modelOk.ToString().ToUpperInvariant())
    Write-Host ('P4_ANDROID_BRAND_READABLE=' + $brandOk.ToString().ToUpperInvariant())
    $redmiFamily = $brandOk -and ($brand[0].Trim() -match '^(?i:redmi|xiaomi)$')
    $modelFamily = $modelOk -and ($model[0].Trim() -match '(?i:redmi|a.?pro|mi.?tv|l55)')
    Write-Host ('P4_REDMi_XIAOMI_BRAND_HINT=' + $redmiFamily.ToString().ToUpperInvariant())
    Write-Host ('P4_REDMi_TV_MODEL_HINT=' + $modelFamily.ToString().ToUpperInvariant())
    $packages = @(& $adbPath -s $serial shell pm list packages 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_PM_FAILED' }
    $release = @($packages | Where-Object { $_.Trim() -ceq 'package:com.spacesarmat.omp' }).Count -gt 0
    $debug = @($packages | Where-Object { $_.Trim() -ceq 'package:com.spacesarmat.omp.test' }).Count -gt 0
    Write-Host ('P4_OMP_RELEASE_INSTALLED=' + $release.ToString().ToUpperInvariant())
    Write-Host ('P4_OMP_DEBUG_INSTALLED=' + $debug.ToString().ToUpperInvariant())
    foreach ($candidate in @(
        @{ id='com.spacesarmat.omp'; variant='RELEASE'; installed=$release },
        @{ id='com.spacesarmat.omp.test'; variant='DEBUG'; installed=$debug }
    )) {
        if (-not $candidate.installed) { continue }
        $target = $candidate.id
        $variant = $candidate.variant
        $paths = @(& $adbPath -s $serial shell pm path $target 2>$null)
        $hasApkPath = $LASTEXITCODE -eq 0 -and @($paths | Where-Object { $_ -match '^package:' }).Count -gt 0
        Write-Host ('P4_OMP_' + $variant + '_APK_PATH_CONFIRMED=' + $hasApkPath.ToString().ToUpperInvariant())
        $pkgDump = @(& $adbPath -s $serial shell dumpsys package $target 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $version = [regex]::Match(($pkgDump -join ' '), 'versionName=([A-Za-z0-9.+_-]{1,60})')
            if ($version.Success) {
                Write-Host ('P4_OMP_' + $variant + '_VERSION=' + $version.Groups[1].Value)
            } else { Write-Host ('P4_OMP_' + $variant + '_VERSION=UNAVAILABLE') }
        } else { Write-Host ('P4_OMP_' + $variant + '_VERSION=UNAVAILABLE') }
        $pidText = @(& $adbPath -s $serial shell pidof $target 2>$null)
        $isRunning = $LASTEXITCODE -eq 0 -and (@($pidText | Where-Object { $_ -match '^\d+(?:\s+\d+)*\s*$' }).Count -gt 0)
        Write-Host ('P4_OMP_' + $variant + '_PROCESS_RUNNING=' + $isRunning.ToString().ToUpperInvariant())
    }
    if (-not $release -and -not $debug) {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_BOTH_OMP_VARIANTS_ABSENT'
    } else {
        Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=OMP_PRESENT_PAIRED_LAN_AND_RENDER_UNVERIFIED'
    }
} catch {
    Write-Host 'P4_REAL_REDMi_AND_LAN_GATE=BLOCKED_READONLY_ADB_PROBE_FAILED'
}
Write-Host 'P4_LIVE_READONLY_PROBE_COMPLETE_NO_REAL_TV_PASS'
