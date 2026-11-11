# G2-B2 device discovery, explicitly authorized by Human 2026-11-11.
# Read-only device checks; DO NOT connect/pair to new endpoints, install APK,
# read user media, print serial/IP, mutate TV/Windows or invoke TorrServer.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Check([string]$reason) { throw ('G2_ADB_CHECK_HOLD: ' + $reason) }

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    Stop-Check 'UNTRUSTED_HOSTOPS_CONTEXT'
}

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    Stop-Check 'DEDICATED_ADB_BINARY_ABSENT'
}
$devices = @(& $adb devices 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { Stop-Check 'ADB_DEVICES_FAILED' }

# Keep device serials and LAN addresses entirely out of GitHub logs.
$entries = @($devices | ForEach-Object {
    if ($_ -match '^(?<serial>\S+)\s+(?<status>device|unauthorized|offline)\s*$') {
        [PSCustomObject]@{ serial = $Matches['serial']; status = $Matches['status'] }
    }
})
Write-Host ('G2_ADB_DEVICES_VISIBLE_COUNT=' + $entries.Count)
Write-Host ('G2_ADB_DEVICES_AUTHORIZED_COUNT=' + @($entries | Where-Object { $_.status -eq 'device' }).Count)
Write-Host ('G2_ADB_DEVICES_UNAUTHORIZED_COUNT=' + @($entries | Where-Object { $_.status -eq 'unauthorized' }).Count)
Write-Host ('G2_ADB_DEVICES_OFFLINE_COUNT=' + @($entries | Where-Object { $_.status -eq 'offline' }).Count)

if ($entries.Count -ne 1 -or $entries[0].status -cne 'device') {
    Stop-Check 'EXACTLY_ONE_AUTHORIZED_ALREADY_CONNECTED_DEVICE_REQUIRED_NO_CONNECT_ATTEMPTED'
}
$serial = $entries[0].serial
$state = @(& $adb -s $serial get-state 2>&1)
if ($LASTEXITCODE -ne 0 -or ($state -join '').Trim() -cne 'device') {
    Stop-Check 'TARGET_DEVICE_NOT_READY'
}
function Read-Prop([string]$key) {
    $raw = @(& $adb -s $serial shell getprop $key 2>&1)
    if ($LASTEXITCODE -ne 0) { Stop-Check 'DEVICE_PROPERTY_READ_FAILED' }
    $value = ($raw -join '').Trim()
    if ($value.Length -gt 100 -or $value -notmatch '^[\w .,-]*$') {
        Stop-Check 'DEVICE_PROPERTY_UNSAFE_OR_MALFORMED'
    }
    return $value
}
$model = Read-Prop 'ro.product.model'
$brand = Read-Prop 'ro.product.brand'
$manufacturer = Read-Prop 'ro.product.manufacturer'
$device = Read-Prop 'ro.product.device'
$sdk = Read-Prop 'ro.build.version.sdk'
$abi = Read-Prop 'ro.product.cpu.abilist'
Write-Host ('G2_ADB_PRODUCT_MODEL=' + $model)
Write-Host ('G2_ADB_PRODUCT_BRAND=' + $brand)
Write-Host ('G2_ADB_PRODUCT_MANUFACTURER=' + $manufacturer)
Write-Host ('G2_ADB_PRODUCT_DEVICE=' + $device)
Write-Host ('G2_ADB_ANDROID_API=' + $sdk)
Write-Host ('G2_ADB_CPU_ABILIST=' + $abi)

# No package mutation. This only checks whether the specific debug app exists.
$package = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>&1)
$packageExit = $LASTEXITCODE
$installed = $packageExit -eq 0 -and
    @($package | Where-Object { "$_" -match '^package:/.*\.apk\s*$' }).Count -ge 1
Write-Host ('G2_ADB_DEBUG_PACKAGE_INSTALLED=' + $installed.ToString().ToLowerInvariant())
Write-Host 'G2_ADB_CHECK_CONNECTED_ONE_DEVICE_PASS_NO_INSTALL'
