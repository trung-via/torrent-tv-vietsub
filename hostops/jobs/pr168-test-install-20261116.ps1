# Human-authorized 2026-11-16: replace only the existing OMP test APK on Redmi.
# HostOps exact-SHA owner command. No uninstall, data clear, reboot, launch,
# network configuration, foreground playback changes or release APK operation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceSha = 'd93504bcd6941c078f230ae14fd4ba3d7988ec65'
$expectedApkHash = 'e548329835ed9a938e30f0c44270e718a623eaacb472c697fbd5665178e6536a'
$packageName = 'com.spacesarmat.omp.test'
$apk = Join-Path $env:RUNNER_WORKSPACE ("_omp-fast-cache\p4-pr168-staged\$sourceSha\app-armeabi-v7a-debug.apk")
$preflightFile = Join-Path $PSScriptRoot 'pr168-apk-preflight-20261116.ps1'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') {
    throw 'TTV_INSTALL_UNTRUSTED_CONTEXT'
}

# No mutation until a fresh, fully pinned preflight succeeds on this runner.
if (-not (Test-Path -LiteralPath $preflightFile -PathType Leaf)) {
    throw 'TTV_INSTALL_PREFLIGHT_SCRIPT_MISSING'
}
$preflight = @(& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflightFile 2>&1 |
    ForEach-Object { $_.ToString() })
if ($LASTEXITCODE -ne 0 -or
    -not ($preflight -contains 'TTV_APK_UPDATE_GATE=PRECHECK_PASS_HUMAN_INSTALL_AUTH_REQUIRED')) {
    Write-Host 'TTV_INSTALL_PREFLIGHT=HOLD'
    throw 'TTV_INSTALL_FRESH_PREFLIGHT_NOT_PASSED'
}
Write-Host 'TTV_INSTALL_PREFLIGHT=PASS'

if (-not (Test-Path -LiteralPath $apk -PathType Leaf) -or
    (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkHash) {
    throw 'TTV_INSTALL_APK_HASH_DRIFT'
}

# Use the existing ADB daemon only; do not acquire, pair or connect to a TV.
$listeners = @(Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) { throw 'TTV_INSTALL_ADB_NOT_RUNNING' }
$deviceRows = @(& $adb devices 2>&1 | ForEach-Object { $_.ToString() } |
    Where-Object { $_ -match '^\S+\s+device\s*$' })
if ($deviceRows.Count -ne 1) { throw 'TTV_INSTALL_DEVICE_COUNT_NOT_EXACT_ONE' }
$deviceId = ($deviceRows[0] -split '\s+')[0]
$oldPackage = @(& $adb -s $deviceId shell pm path $packageName 2>&1)
if (-not ($oldPackage -match '^package:')) { throw 'TTV_INSTALL_TARGET_NOT_ALREADY_INSTALLED' }

# Exactly one authorized install -r -t attempt, preserving installed test data.
# Never print the TV identifier or Android/Windows private paths in public CI.
Write-Host 'TTV_INSTALL_ACTION=ONE_SHOT_REPLACE_TEST_ONLY'
$savedPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $installOutput = @(& $adb -s $deviceId install -r -t $apk 2>&1 | ForEach-Object { $_.ToString() })
    $installExit = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $savedPreference
}
if ($installExit -ne 0 -or -not ($installOutput -match '^Success\s*$')) {
    Write-Host 'TTV_INSTALL_ADB_RESULT=FAILED_HOLD'
    throw 'TTV_INSTALL_ADB_REPLACE_FAILED_NO_RETRY'
}
Write-Host 'TTV_INSTALL_ADB_RESULT=SUCCESS'

# Verify the installed package binary after the replace; read-only ADB pull.
$newPackage = @(& $adb -s $deviceId shell pm path $packageName 2>&1)
$basePaths = @($newPackage | Where-Object {
    ([string]$_) -match '^package:/data/app/.+/base\.apk\s*$'
})
if ($basePaths.Count -ne 1) {
    Write-Host 'TTV_INSTALL_POSTCHECK=BASE_APK_PATH_UNVERIFIED'
    throw 'TTV_INSTALL_POSTCHECK_PATH_HOLD'
}
$remoteBase = ([string]$basePaths[0]).Substring(8).Trim()
$localBase = Join-Path $env:RUNNER_TEMP ("ttv-installed-pr168-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT.apk")
if (Test-Path -LiteralPath $localBase) { throw 'TTV_INSTALL_POSTCHECK_TEMP_ALREADY_EXISTS' }
try {
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $pullOutput = @(& $adb -s $deviceId pull $remoteBase $localBase 2>&1 | ForEach-Object { $_.ToString() })
        $pullExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    if ($pullExit -ne 0 -or -not (Test-Path -LiteralPath $localBase -PathType Leaf)) {
        Write-Host 'TTV_INSTALL_POSTCHECK=ADB_READ_FAILED'
        throw 'TTV_INSTALL_POSTCHECK_READ_HOLD'
    }
    $installedHash = (Get-FileHash -LiteralPath $localBase -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedHash -cne $expectedApkHash) {
        Write-Host 'TTV_INSTALL_POSTCHECK=APK_HASH_MISMATCH'
        throw 'TTV_INSTALL_POSTCHECK_HASH_HOLD'
    }
    Write-Host 'TTV_INSTALL_POSTCHECK=EXACT_APK_HASH_MATCH'
} finally {
    if (Test-Path -LiteralPath $localBase -PathType Leaf) {
        Remove-Item -LiteralPath $localBase -Force -ErrorAction SilentlyContinue
    }
}
Write-Host 'TTV_INSTALL_RESULT=INSTALLED_EXACT_TEST_APK_REAL_TV_VISUAL_UNVERIFIED'
