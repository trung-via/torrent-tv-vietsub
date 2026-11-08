# Torrent TV G1 Thor v0.3.5 — read-only existing ADB device preflight.
# Runs only on the repository's dedicated Windows HostOps runner.
# Does not pair/connect, install, launch, capture screen, modify files, or seek media.
# Public-repository output: NEVER print ADB serial, MAC, IP, media path or subtitle content.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'TV_G1_THOR_PREFLIGHT_BEGIN'
Write-Host 'TV_G1_TARGET=THOR_VI_V035'
Write-Host 'TV_G1_CONTENT_RENDER=NOT_RUN'
Write-Host 'TV_G1_SEEK_SYNC=NOT_RUN'
Write-Host 'TV_G1_SRT_SHA256_EXPECTED=3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'BLOCKED: unexpected runner identity'
}
$adbCmd = Get-Command 'adb.exe' -ErrorAction SilentlyContinue
if ($null -eq $adbCmd) {
    Write-Host 'TV_G1_ADB_STATUS=ADB_NOT_INSTALLED_OR_NOT_ON_PATH'
    Write-Host 'TV_G1_DEVICE_STATUS=UNVERIFIED'
    Write-Host 'TV_G1_THOR_RESULT=NO_DEVICE_EVIDENCE'
    exit 0
}
$adb = $adbCmd.Source
Write-Host 'TV_G1_ADB_STATUS=FOUND'
try {
    # adb devices may start the local ADB server. No network pairing or adb connect is issued.
    $lines = @(& $adb devices -l 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_DEVICE_LIST_FAILED' }
    $authorized = @()
    $offlineCount = 0
    $unauthorizedCount = 0
    foreach ($line in $lines) {
        if ($line -match '^\s*(\S+)\s+(device|offline|unauthorized)(?:\s|$)') {
            $state = $Matches[2]
            if ($state -eq 'device') { $authorized += $Matches[1] }
            elseif ($state -eq 'offline') { $offlineCount++ }
            elseif ($state -eq 'unauthorized') { $unauthorizedCount++ }
        }
    }
    Write-Host ('TV_G1_AUTHORIZED_DEVICES=' + $authorized.Count)
    Write-Host ('TV_G1_OFFLINE_DEVICES=' + $offlineCount)
    Write-Host ('TV_G1_UNAUTHORIZED_DEVICES=' + $unauthorizedCount)
    if ($authorized.Count -ne 1) {
        Write-Host 'TV_G1_DEVICE_STATUS=NO_UNAMBIGUOUS_AUTHORIZED_DEVICE'
        Write-Host 'TV_G1_THOR_RESULT=NO_DEVICE_EVIDENCE'
        exit 0
    }
    $serial = [string]$authorized[0]
    function Get-DeviceProp([string]$name) {
        $value = @(& $adb -s $serial shell getprop $name 2>$null)
        if ($LASTEXITCODE -ne 0 -or $value.Count -eq 0) { return 'UNKNOWN' }
        $clean = (([string]$value[0]) -replace '[^A-Za-z0-9 _.-]', '').Trim()
        if ($clean.Length -gt 80) { $clean = $clean.Substring(0,80) }
        if (!$clean) { return 'UNKNOWN' }
        return $clean
    }
    $model = Get-DeviceProp 'ro.product.model'
    $android = Get-DeviceProp 'ro.build.version.release'
    $abi = Get-DeviceProp 'ro.product.cpu.abi'
    Write-Host ('TV_G1_DEVICE_MODEL=' + $model)
    Write-Host ('TV_G1_ANDROID_RELEASE=' + $android)
    Write-Host ('TV_G1_ABI=' + $abi)
    $installed = @(& $adb -s $serial shell pm list packages 'com.spacesarmat.omp.test' 2>$null)
    $hasTest = (@($installed | Where-Object { ([string]$_).Trim() -eq 'package:com.spacesarmat.omp.test' }).Count -gt 0)
    Write-Host ('TV_G1_OMP_TEST_PACKAGE_PRESENT=' + $hasTest.ToString().ToUpperInvariant())
    Write-Host 'TV_G1_DEVICE_STATUS=READ_ONLY_PROPERTIES_OBSERVED'
    Write-Host 'TV_G1_THOR_RESULT=DEVICE_PREFLIGHT_ONLY'
}
catch {
    # Do not print raw ADB errors, which might include device serial or private paths.
    Write-Host 'TV_G1_DEVICE_STATUS=ADB_READ_FAILED_OR_UNAVAILABLE'
    Write-Host 'TV_G1_THOR_RESULT=NO_DEVICE_EVIDENCE'
}
Write-Host 'TV_G1_PRIVACY=NO_SERIAL_IP_PATH_MEDIA_OR_SUBTITLE_UPLOADED'
Write-Host 'TV_G1_ACTUATION=NONE'
Write-Host 'TV_G1_THOR_PREFLIGHT_END'
exit 0
