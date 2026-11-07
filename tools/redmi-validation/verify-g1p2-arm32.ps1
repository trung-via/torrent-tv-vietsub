# G1+P2 private Redmi ARM32 handoff, based on run 42331308161.
# No GitHub APK upload, adb install, uninstall, device modification, or Release.
[CmdletBinding()]
param(
    [ValidateSet('Inspect','Stage','CompareInstalled')]
    [string]$Mode = 'Inspect',
    [string]$SourceApk = 'C:\TOOL\TorrentTV-Runner\_work\_temp\p1-g1-prod-42331308161-1\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk',
    [string]$Serial = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$expected = 'c2f71cb8c8accc11821396d20a96490b0a129344cb329e1c5e6d9c3bf2f7b75f'
$package = 'com.spacesarmat.omp.test'
$run = '42331308161'

function Stop-Gate([string]$Reason) { throw ('G1P2_HANDOFF_HOLD: ' + $Reason) }
function Check-Exit([string]$Reason) {
    if ($LASTEXITCODE -ne 0) { Stop-Gate $Reason }
}
function Find-BuildTool([string]$Name) {
    $sdk = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) {
        $env:ANDROID_HOME
    } else { 'C:\TOOL\Android-SDK' }
    $parent = Join-Path $sdk 'build-tools'
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { Stop-Gate 'ANDROID_BUILD_TOOLS_MISSING' }
    $all = @(Get-ChildItem -LiteralPath $parent -Directory |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName $Name } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($all.Count -lt 1) { Stop-Gate ('MISSING_' + $Name) }
    return $all[0]
}
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-Package([string]$Apk,[string]$Aapt) {
    $out = @(& $Aapt dump badging $Apk 2>&1)
    Check-Exit 'AAPT_BADGING_FAILED'
    $line = @($out | Where-Object { "$_" -match "^package:\s+name='([^']+)'" })
    if ($line.Count -ne 1) { Stop-Gate 'PACKAGE_NAME_NOT_UNIQUE' }
    $parsed = [regex]::Match("$($line[0])", "^package:\s+name='([^']+)'")
    if (-not $parsed.Success) { Stop-Gate 'PACKAGE_NAME_NOT_PROVEN' }
    return $parsed.Groups[1].Value
}
function Read-Signers([string]$Apk,[string]$SignerTool) {
    $out = @(& $SignerTool verify --print-certs $Apk 2>&1)
    Check-Exit 'APKSIGNER_VERIFY_FAILED'
    $pattern = '(?im)^\s*Signer\s+#\d+\s+certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$'
    $certMatches = [regex]::Matches(($out -join [Environment]::NewLine),$pattern)
    if ($certMatches.Count -lt 1) { Stop-Gate 'CERT_SHA256_NOT_PROVEN' }
    return @($certMatches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique)
}
if (-not (Test-Path -LiteralPath $SourceApk -PathType Leaf)) {
    Stop-Gate ('SOURCE_APK_NOT_RETAINED_ON_RUNNER run=' + $run)
}
$SourceApk = (Resolve-Path -LiteralPath $SourceApk).Path
if ([IO.Path]::GetFileName($SourceApk) -cne 'app-armeabi-v7a-debug.apk') {
    Stop-Gate 'EXPECTED_ARM32_APK_ONLY'
}
$manifest = Join-Path (Split-Path -Parent $SourceApk) 'SHA256SUMS-G1P2.txt'
if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { Stop-Gate 'MANIFEST_NOT_FOUND' }
$manifestLines = @(Get-Content -LiteralPath $manifest -Encoding UTF8)
$expectedLine = "$expected  app-armeabi-v7a-debug.apk"
if (@($manifestLines | Where-Object { $_ -ceq $expectedLine }).Count -ne 1) {
    Stop-Gate 'MANIFEST_EXPECTED_ARM32_SHA_MISSING'
}
$actual = Get-Sha256 $SourceApk
if ($actual -cne $expected) { Stop-Gate 'APK_SHA256_MISMATCH' }
$aapt = Find-BuildTool 'aapt.exe'
$signerTool = Find-BuildTool 'apksigner.bat'
$newPackage = Read-Package $SourceApk $aapt
if ($newPackage -cne $package) { Stop-Gate 'APP_PACKAGE_CHANGED' }
$newSigners = @(Read-Signers $SourceApk $signerTool)
Write-Host ("G1P2_LOCAL_APK_SHA_AND_PACKAGE_PASS run={0} sha256={1} package={2}" -f $run,$actual,$newPackage)

if ($Mode -ceq 'Stage') {
    $base = [Environment]::GetFolderPath('LocalApplicationData')
    if (-not $base) { Stop-Gate 'LOCAL_APPDATA_UNAVAILABLE' }
    $private = Join-Path $base 'TorrentTVVietsub\PrivateDebug'
    New-Item -ItemType Directory -Path $private -Force | Out-Null
    $target = Join-Path $private ('g1p2-' + $run + '-armeabi-v7a-debug.apk')
    if (Test-Path -LiteralPath $target) {
        if ((Get-Sha256 $target) -cne $expected) { Stop-Gate 'EXISTING_PRIVATE_COPY_DIFFERS' }
        Write-Host ('G1P2_LOCAL_PRIVATE_COPY_ALREADY_VERIFIED path=' + $target)
    } else {
        Copy-Item -LiteralPath $SourceApk -Destination $target -ErrorAction Stop
        if ((Get-Sha256 $target) -cne $expected) {
            Remove-Item -LiteralPath $target -Force
            Stop-Gate 'PRIVATE_COPY_HASH_MISMATCH'
        }
        Write-Host ('G1P2_LOCAL_PRIVATE_COPY_VERIFIED path=' + $target)
    }
}
if ($Mode -ceq 'CompareInstalled') {
    $adb = if (Test-Path -LiteralPath 'C:\TOOL\Android-SDK\platform-tools\adb.exe') {
        'C:\TOOL\Android-SDK\platform-tools\adb.exe'
    } else {
        $cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
        if (-not $cmd) { Stop-Gate 'ADB_UNAVAILABLE' }
        $cmd.Source
    }
    if (-not $Serial) {
        $devices = @(& $adb devices)
        Check-Exit 'ADB_DEVICES_FAILED'
        $serials = @($devices | Where-Object { $_ -match '^(\S+)\s+device\s*$' } |
            ForEach-Object { if ($_ -match '^(\S+)\s+device\s*$') { $Matches[1] } })
        if ($serials.Count -ne 1) { Stop-Gate 'EXACTLY_ONE_AUTHORIZED_DEVICE_REQUIRED' }
        $Serial = $serials[0]
    }
    $paths = @(& $adb -s $Serial shell pm path $package)
    Check-Exit 'ADB_PACKAGE_QUERY_FAILED'
    $basePaths = @($paths | Where-Object { "$_" -match '^package:(.+/base\.apk)\s*$' } |
        ForEach-Object { if ("$_" -match '^package:(.+/base\.apk)\s*$') { $Matches[1] } })
    if ($basePaths.Count -ne 1) { Stop-Gate 'INSTALLED_BASE_APK_PATH_UNVERIFIED' }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('torrent-tv-installed-' + [guid]::NewGuid().ToString('N') + '.apk')
    try {
        & $adb -s $Serial pull $basePaths[0] $temp | Out-Null
        Check-Exit 'READ_ONLY_ADB_PULL_FAILED'
        $installedPackage = Read-Package $temp $aapt
        if ($installedPackage -cne $package) { Stop-Gate 'INSTALLED_PACKAGE_MISMATCH' }
        $installedSigners = @(Read-Signers $temp $signerTool)
        if (($newSigners -join ',') -cne ($installedSigners -join ',')) {
            Stop-Gate 'SIGNING_CERT_MISMATCH_DO_NOT_INSTALL'
        }
        Write-Host 'G1P2_INSTALLED_APP_SIGNATURE_MATCH_PASS_NO_INSTALL_PERFORMED'
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}
Write-Host ('G1P2_PREFLIGHT_COMPLETE mode=' + $Mode + ' NO_ADB_INSTALL_OR_TV_CHANGE')
