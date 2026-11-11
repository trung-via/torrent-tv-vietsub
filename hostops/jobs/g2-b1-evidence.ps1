# Bounded read-only verification of G2-B1 successful build run #42942320322.
# No Android installation, ADB, Windows services, runner configuration or network modifications.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = 'C:\TOOL\TorrentTV-Runner\_work\_temp\p1-g1-prod-42942320322-1'
$reportDir = Join-Path $root 'android\app\build\test-results\testDebugUnitTest'
$apkDir = Join-Path $root 'android\app\build\outputs\apk\debug'
if (-not (Test-Path -LiteralPath $reportDir -PathType Container)) {
    throw 'G2_EVIDENCE_MISSING: Gradle XML test reports no longer retained on runner'
}
if (-not (Test-Path -LiteralPath $apkDir -PathType Container)) {
    throw 'G2_EVIDENCE_MISSING: APK directory no longer retained on runner'
}

$reports = @(Get-ChildItem -LiteralPath $reportDir -Filter 'TEST-*.xml' -File -ErrorAction Stop)
if ($reports.Count -eq 0) { throw 'G2_EVIDENCE_MISSING: no JUnit XML files' }
$tests = 0
$failures = 0
$errors = 0
$skipped = 0
foreach ($file in $reports) {
    [xml]$doc = Get-Content -LiteralPath $file.FullName -Raw
    $suite = $doc.testsuite
    if (-not $suite) { throw ('G2_EVIDENCE_INVALID_TEST_XML: ' + $file.Name) }
    $tests += [int]$suite.tests
    $failures += [int]$suite.failures
    $errors += [int]$suite.errors
    $skipped += [int]$suite.skipped
}
Write-Host "G2_B1_GRADLE_TEST_TOTAL=$tests"
Write-Host "G2_B1_GRADLE_TEST_FAILURES=$failures"
Write-Host "G2_B1_GRADLE_TEST_ERRORS=$errors"
Write-Host "G2_B1_GRADLE_TEST_SKIPPED=$skipped"
Write-Host "G2_B1_GRADLE_TEST_REPORT_FILES=$($reports.Count)"
if ($tests -lt 600 -or $failures -ne 0 -or $errors -ne 0) {
    throw 'G2_B1_TEST_REPORT_UNACCEPTABLE'
}

$expected = [ordered]@{
    'app-arm64-v8a-debug.apk' = '2d8e7a1d57fff0f44694b96862d5cea433593a93ae7e6419256af287b25682bd'
    'app-armeabi-v7a-debug.apk' = '6be09b91fa28317c946d095d612e34f18f4282c89bbdd02cb2636a6b5f892541'
    'app-universal-debug.apk' = '889e2b278cbb4e5e3db63fb29d74c536381b35ae50a5a521d8d4c9e717a13937'
}
foreach ($name in $expected.Keys) {
    $apk = Join-Path $apkDir $name
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
        throw ('G2_EVIDENCE_MISSING_APK: ' + $name)
    }
    $actual = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $expected[$name]) {
        throw ('G2_EVIDENCE_APK_SHA_MISMATCH: ' + $name)
    }
    Write-Host ("G2_B1_APK_SHA_VERIFIED " + $name + " " + $actual)
}
Write-Host 'G2_B1_ON_RUNNER_JUNIT_AND_APK_EVIDENCE_PASS_NOT_TV_PASS'
