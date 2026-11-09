# Torrent TV Redmi G1 -- read-only installed OMP app version inventory.
# No APK pull, sideload, file transfer, ADB connect/pair, launching or playback.
# Never print serial numbers, package dumps, personal media, IP or file paths.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'G1_VERSION_PREFLIGHT_BEGIN'
Write-Host 'G1_VERSION_TV_RENDER=NOT_TESTED'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'BLOCKED_RUNNER_IDENTITY' }
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    Write-Host 'G1_VERSION_STATUS=ADB_NOT_FOUND'
    exit 0
}
try {
    $devices = @(& $adb devices -l 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_LIST_FAILED' }
    $authorized = @()
    foreach ($line in $devices) {
        if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $authorized += [string]$Matches[1] }
    }
    Write-Host ('G1_VERSION_AUTHORIZED_DEVICE_COUNT=' + $authorized.Count)
    if ($authorized.Count -ne 1) { Write-Host 'G1_VERSION_STATUS=NO_UNAMBIGUOUS_DEVICE'; exit 0 }
    $serial = $authorized[0]
    $modelRaw = @(& $adb -s $serial shell getprop ro.product.model 2>$null)
    if ($LASTEXITCODE -ne 0 -or $modelRaw.Count -eq 0) { throw 'MODEL_READ_FAILED' }
    $model = (([string]$modelRaw[0]) -replace '[^A-Za-z0-9_-]', '').Trim()
    if ($model -cne 'MiTV-ASTR0') { Write-Host 'G1_VERSION_STATUS=WRONG_MODEL_OR_UNVERIFIED'; exit 0 }
    Write-Host 'G1_VERSION_MODEL=MiTV-ASTR0'
    $pkg = @(& $adb -s $serial shell dumpsys package com.spacesarmat.omp.test 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'PACKAGE_METADATA_UNAVAILABLE' }
    $raw = ($pkg -join "`n")
    # Constrain regex to the Packages block for this exact app; never log the raw dump.
    if ($raw -notmatch 'Package \[com\.spacesarmat\.omp\.test\]') {
        Write-Host 'G1_VERSION_STATUS=TEST_PACKAGE_NOT_FOUND'
        exit 0
    }
    $codeMatch = [regex]::Match($raw, '(?m)^\s*versionCode=(\d+)\b')
    $nameMatch = [regex]::Match($raw, '(?m)^\s*versionName=([^\r\n]+)')
    if (-not $codeMatch.Success) { Write-Host 'G1_VERSION_STATUS=VERSION_CODE_UNKNOWN'; exit 0 }
    $versionCode = $codeMatch.Groups[1].Value
    $versionName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { 'UNKNOWN' }
    $versionName = ($versionName -replace '[^a-zA-Z0-9._-]', '')
    if ($versionName.Length -gt 40) { $versionName = $versionName.Substring(0, 40) }
    Write-Host ('G1_VERSION_CODE=' + $versionCode)
    Write-Host ('G1_VERSION_NAME=' + $versionName)
    if ($versionCode -ceq '200603') {
        Write-Host 'G1_VERSION_MATCHES_HISTORICAL_DEBUG_VERSION_CODE=TRUE'
    } else {
        Write-Host 'G1_VERSION_MATCHES_HISTORICAL_DEBUG_VERSION_CODE=FALSE'
    }
    Write-Host 'G1_VERSION_APK_SHA=UNVERIFIED_NOT_PULLED'
    Write-Host 'G1_VERSION_STATUS=READ_ONLY_VERSION_METADATA_OBSERVED'
} catch {
    # No raw exception: adb errors may contain serial, local paths, or package metadata.
    Write-Host 'G1_VERSION_STATUS=ADB_METADATA_READ_FAILED'
}
Write-Host 'G1_VERSION_NO_APK_OR_MEDIA_TRANSFER=TRUE'
Write-Host 'G1_VERSION_PREFLIGHT_END'
exit 0
