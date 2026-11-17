# Read-only Redmi/ADB status for the personal FLAT upgrade.
# Runs via the already-merged, exact-commit Torrent TV HostOps inbox (#82).
# Never installs, removes, launches, reboots or clears anything on the TV.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub') {
    throw 'TTV_FLAT_ADB_HOLD_WRONG_RUNNER'
}

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'TTV_FLAT_ADB_HOLD_TOOL_NOT_FOUND'
}

# Do not implicitly start a different ADB server/session on the shared PC.
if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -lt 1) {
    throw 'TTV_FLAT_ADB_HOLD_SERVER_NOT_RUNNING'
}

function ReadAdb([string[]]$Arguments) {
    $output = @(& $adb @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'TTV_FLAT_ADB_HOLD_READ_FAILED'
    }
    return @($output)
}

$all = @(ReadAdb @('devices', '-l'))
$authorized = @($all | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' })
$notReady = @($all | Where-Object { $_ -match '^\S+\s+(unauthorized|offline)(?:\s|$)' })
Write-Host ('TTV_FLAT_ADB_AUTHORIZED_COUNT=' + $authorized.Count)
Write-Host ('TTV_FLAT_ADB_NOT_READY_COUNT=' + $notReady.Count)
if ($authorized.Count -ne 1 -or $notReady.Count -ne 0) {
    throw 'TTV_FLAT_ADB_HOLD_EXPECT_EXACTLY_ONE_READY_DEVICE'
}

$serial = ($authorized[0].Trim() -split '\s+')[0]
function DeviceValue([string]$Name) {
    $lines = @(ReadAdb @('-s', $serial, 'shell', 'getprop', $Name))
    if ($lines.Count -ne 1) {
        throw 'TTV_FLAT_ADB_HOLD_UNREADABLE_DEVICE_PROPERTY'
    }
    return ([string]$lines[0]).Trim()
}

if ((DeviceValue 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (DeviceValue 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (DeviceValue 'ro.build.version.sdk') -cne '30') {
    throw 'TTV_FLAT_ADB_HOLD_TV_IDENTITY_MISMATCH'
}
Write-Host 'TTV_FLAT_ADB_REDMi_MODEL_ABI_API=VERIFIED'

$pkg = 'com.spacesarmat.omp.test'
$installed = @(ReadAdb @('-s', $serial, 'shell', 'pm', 'path', $pkg))
$bases = @($installed | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
if ($bases.Count -ne 1) {
    throw 'TTV_FLAT_ADB_HOLD_INSTALLED_DEBUG_APP_UNVERIFIED'
}
Write-Host 'TTV_FLAT_ADB_EXISTING_OMP_DEBUG=VERIFIED'
Write-Host 'TTV_FLAT_ADB_PREFLIGHT=PASS_READ_ONLY'
Write-Host 'TTV_FLAT_ADB_APK_INSTALL=NOT_RUN'
Write-Host 'TTV_FLAT_ADB_LIVE_SUBTITLE=NOT_RUN'
