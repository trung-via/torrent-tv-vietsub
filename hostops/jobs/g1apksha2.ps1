# Read-only SHA256 attestation of the installed OMP test APK on authorized Redmi.
# No APK pull/transfer, install, sideload, shell write, media access, pairing or playback.
# No serial/IP/package path printed to public GitHub Actions logs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'G1_APKSHA_PREFLIGHT_BEGIN'
Write-Host 'G1_APKSHA_MEDIA_RENDER=NOT_RUN'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'BLOCKED_RUNNER_IDENTITY' }
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Write-Host 'G1_APKSHA_STATUS=ADB_NOT_FOUND'; exit 0 }
try {
    $lines = @(& $adb devices -l 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_LIST_FAILED' }
    $ids = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $ids += [string]$Matches[1] }
    }
    Write-Host ('G1_APKSHA_DEVICE_COUNT=' + $ids.Count)
    if ($ids.Count -ne 1) { Write-Host 'G1_APKSHA_STATUS=NO_UNAMBIGUOUS_DEVICE'; exit 0 }
    $serial = $ids[0]
    $m = @(& $adb -s $serial shell getprop ro.product.model 2>$null)
    if ($LASTEXITCODE -ne 0 -or @($m).Count -ne 1 -or ([string]$m[0]).Trim() -cne 'MiTV-ASTR0') {
        Write-Host 'G1_APKSHA_STATUS=UNEXPECTED_TV_MODEL'
        exit 0
    }
    $packages = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'PM_PATH_FAILED' }
    $paths = @()
    foreach ($line in $packages) {
        $q = ([string]$line).Trim()
        if ($q.StartsWith('package:')) { $paths += $q.Substring(8) }
    }
    Write-Host ('G1_APKSHA_PACKAGE_PATH_COUNT=' + $paths.Count)
    $bases = @($paths | Where-Object { $_ -match '^/[A-Za-z0-9_./+=~-]+/base\.apk$' })
    if ($bases.Count -ne 1) { Write-Host 'G1_APKSHA_STATUS=BASE_APK_PATH_UNVERIFIED'; exit 0 }
    $remotePath = [string]$bases[0]
    # Only a strictly sanitized package-manager-provided path is passed to adb shell.
    $output = @(& $adb -s $serial shell sha256sum $remotePath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        $output = @(& $adb -s $serial shell toybox sha256sum $remotePath 2>$null)
    }
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw 'HASH_READ_FAILED' }
    $line = ([string]$output[0]).Trim()
    if ($line -notmatch '^([a-fA-F0-9]{64})\s+') { throw 'HASH_FORMAT_UNEXPECTED' }
    $actual = $Matches[1].ToLowerInvariant()
    $historical = 'c5a5bbd265e1353012165111d114b692b66ad783775eebdbc1408e1a668e82b6'
    Write-Host ('G1_APKSHA_MATCH_HISTORICAL_G1=' + ($actual -ceq $historical).ToString().ToUpperInvariant())
    Write-Host 'G1_APKSHA_HASH_OBSERVED=TRUE'
    Write-Host 'G1_APKSHA_STATUS=READ_ONLY_HASH_OK'
} catch {
    # Do not print raw ADB failure: it may contain private paths or identifiers.
    Write-Host 'G1_APKSHA_STATUS=READ_FAILED'
}
Write-Host 'G1_APKSHA_NO_APK_TRANSFER=TRUE'
Write-Host 'G1_APKSHA_NO_TV_ACTUATION=TRUE'
Write-Host 'G1_APKSHA_PREFLIGHT_END'
exit 0
