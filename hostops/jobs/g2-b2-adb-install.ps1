# G2-B2: Human-authorized, bounded keep-data Debug APK update on one pre-authorized Xiaomi TV.
# No ADB connect/pair/root/uninstall/downgrade, app-data clear, media access, service/network change.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Install([string]$reason) { throw ('G2_TV_INSTALL_HOLD: ' + $reason) }
function Assert-NoLink([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { Stop-Install 'REQUIRED_LOCAL_PATH_MISSING' }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Install 'REPARSE_POINT_DENIED'
    }
}
function Assert-ExclusiveDirectory([string]$path) {
    Assert-NoLink $path
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed = @($identity,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
    $acl = (New-Object IO.DirectoryInfo($path)).GetAccessControl(
        [Security.AccessControl.AccessControlSections]::Access)
    if (-not $acl.AreAccessRulesProtected) { Stop-Install 'VAULT_ACL_NOT_PRIVATE' }
    $aces = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    foreach ($ace in $aces) {
        if ($ace.IsInherited -or
            $ace.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            $ace.IdentityReference.Value -notin $allowed) {
            Stop-Install 'VAULT_ACL_UNEXPECTED_ACE'
        }
    }
    foreach ($sid in $allowed) {
        if (@($aces | Where-Object { $_.IdentityReference.Value -eq $sid }).Count -ne 1) {
            Stop-Install 'VAULT_ACL_REQUIRED_ACE_MISSING'
        }
    }
}
function Read-BuildTool([string]$name) {
    $root = 'C:\TOOL\Android-SDK\build-tools'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { Stop-Install 'SDK_BUILD_TOOLS_ABSENT' }
    $items = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction Stop |
        Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName $name } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($items.Count -lt 1) { Stop-Install 'SDK_INSPECTION_TOOL_MISSING' }
    return $items[0]
}
function Read-DeviceProp([string]$key) {
    $raw = @(& $adb -s $serial shell getprop $key 2>&1)
    if ($LASTEXITCODE -ne 0) { Stop-Install 'ADB_PROPERTY_READ_FAILED' }
    $val = ($raw -join '').Trim()
    if ($val.Length -gt 100 -or $val -notmatch '^[a-zA-Z0-9 _.,-]*$') {
        Stop-Install 'ADB_PROPERTY_UNEXPECTED'
    }
    return $val
}

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    Stop-Install 'UNTRUSTED_HOSTOPS_RUNNER'
}
# Verify the private retained artifact from the exact successful CI run, not a new public upload.
$private = 'C:\TOOL\TorrentTV-Runner\private-artifacts'
$vault = Join-Path $private 'G2B2'
$source = Join-Path $vault 'run-42949951699-1'
foreach ($dir in @($private,$vault,$source)) { Assert-ExclusiveDirectory $dir }
$apk = Join-Path $source 'app-armeabi-v7a-debug.apk'
$manifest = Join-Path $source 'SHA256SUMS-G2-REFRESH.txt'
$evidenceFile = Join-Path $source 'G2-REFRESH-BUILD-EVIDENCE.txt'
$signatureFile = Join-Path $source 'SIGNATURE-STATUS.txt'
foreach ($f in @($apk,$manifest,$evidenceFile,$signatureFile)) { Assert-NoLink $f }
$expectedHash = 'ba1f6485107f94ad855e8284cd48d5a1724b29b20b4d30916636525bfaa5a931'
if ((Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedHash) {
    Stop-Install 'APK_SHA256_MISMATCH'
}
if ((Get-Content -LiteralPath $signatureFile -Raw -Encoding Ascii).Trim() -cne 'SIGNATURE_VERIFIED') {
    Stop-Install 'APK_SIGNATURE_STATUS_NOT_VERIFIED'
}
$hashEntries = @((Get-Content -LiteralPath $manifest -Encoding Ascii) |
    Where-Object { $_ -match '^[a-fA-F0-9]{64}  app-armeabi-v7a-debug\.apk$' })
if ($hashEntries.Count -ne 1 -or $hashEntries[0].Substring(0,64).ToLowerInvariant() -cne $expectedHash) {
    Stop-Install 'APK_MANIFEST_HASH_MISMATCH'
}
$proof = @(Get-Content -LiteralPath $evidenceFile -Encoding UTF8)
foreach ($line in @('app_commit=b0994c7b33b7dac1d8fdacda1c49af853c32285d',
                    'run_id=42949951699',
                    'source_set=feature/g2-refresh-vietsub-inplace-20261111')) {
    if (@($proof | Where-Object { $_ -ceq $line }).Count -ne 1) {
        Stop-Install 'APK_SOURCE_PROVENANCE_MISMATCH'
    }
}
$apksigner = Read-BuildTool 'apksigner.bat'
$aapt = Read-BuildTool 'aapt.exe'
$certOutput = @(& $apksigner verify --print-certs $apk 2>&1)
if ($LASTEXITCODE -ne 0) { Stop-Install 'APK_VERIFICATION_FAILED' }
$certs = @($certOutput | ForEach-Object { "$_" } |
    Select-String -Pattern '(?i)certificate SHA-256 digest:\s*([0-9a-f]{64})' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.ToLowerInvariant() } |
    Select-Object -Unique)
if ($certs.Count -ne 1 -or
    $certs[0] -cne '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84') {
    Stop-Install 'APK_UNEXPECTED_DEBUG_CERTIFICATE'
}
$badging = @(& $aapt dump badging $apk 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($badging | Where-Object { "$_" -match "^package:\s+name='com\.spacesarmat\.omp\.test'" }).Count -ne 1) {
    Stop-Install 'APK_UNEXPECTED_PACKAGE_NAME'
}
Write-Host 'G2_TV_INSTALL_PINNED_PRIVATE_APK_VERIFIED'

$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Stop-Install 'ADB_BINARY_ABSENT' }
$devices = @(& $adb devices 2>&1 | ForEach-Object { "$_" })
if ($LASTEXITCODE -ne 0) { Stop-Install 'ADB_DEVICES_FAILED' }
$entries = @($devices | ForEach-Object {
    if ($_ -match '^(?<serial>\S+)\s+(?<status>device|unauthorized|offline)\s*$') {
        [PSCustomObject]@{ serial = $Matches['serial']; status = $Matches['status'] }
    }
})
Write-Host ('G2_TV_INSTALL_ADB_COUNT=' + $entries.Count)
if ($entries.Count -ne 1 -or $entries[0].status -cne 'device') {
    Stop-Install 'EXACT_ONE_AUTHORIZED_DEVICE_REQUIRED'
}
$serial = $entries[0].serial
$model = Read-DeviceProp 'ro.product.model'
$brand = Read-DeviceProp 'ro.product.brand'
$maker = Read-DeviceProp 'ro.product.manufacturer'
$device = Read-DeviceProp 'ro.product.device'
$api = Read-DeviceProp 'ro.build.version.sdk'
$abi = Read-DeviceProp 'ro.product.cpu.abilist'
$characteristics = Read-DeviceProp 'ro.build.characteristics'
if ($model -cne 'MiTV-ASTR0' -or $brand -cne 'Xiaomi' -or
    $maker -cne 'xiaomi' -or $device -cne 'blueplanet' -or
    $api -cne '30' -or $abi -cne 'armeabi-v7a,armeabi' -or
    -not $characteristics.Contains('tv')) {
    Stop-Install 'TARGET_XIAOMI_TV_IDENTITY_CHANGED'
}
Write-Host 'G2_TV_INSTALL_XIAOMI_BLUEPLANET_ANDROID11_ARM32_IDENTITY_PASS'
# Previously installed package must exist; this is an in-place upgrade, not fresh install.
$pathsBefore = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($pathsBefore | Where-Object { "$_" -match '^package:/.*\.apk\s*$' }).Count -lt 1) {
    Stop-Install 'EXISTING_DEBUG_APP_NOT_FOUND_NO_NEW_INSTALL'
}
Write-Host 'G2_TV_INSTALL_EXISTING_DEBUG_PACKAGE_PRESENT'

# The ONLY device-mutating command in this job. -r preserves app data; no -d, -g, -t or uninstall.
$result = @(& $adb -s $serial install -r $apk 2>&1 | ForEach-Object { "$_" })
$exit = $LASTEXITCODE
if ($exit -ne 0 -or @($result | Where-Object { "$_".Trim() -ceq 'Success' }).Count -ne 1) {
    if (($result -join ' ') -match 'INSTALL_FAILED_UPDATE_INCOMPATIBLE') {
        Stop-Install 'SIGNATURE_MISMATCH_ANDROID_REFUSED_REPLACE_DATA_UNCHANGED'
    }
    if (($result -join ' ') -match 'INSTALL_FAILED_VERSION_DOWNGRADE') {
        Stop-Install 'VERSION_DOWNGRADE_REFUSED_NO_FORCE'
    }
    Stop-Install 'ADB_INSTALL_R_FAILED_NO_FALLBACK_OR_UNINSTALL'
}
Write-Host 'G2_TV_INSTALL_R_KEEP_DATA_COMMAND_SUCCESS'
$pathsAfter = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($pathsAfter | Where-Object { "$_" -match '^package:/.*\.apk\s*$' }).Count -lt 1) {
    Stop-Install 'POST_INSTALL_DEBUG_PACKAGE_NOT_FOUND'
}
Write-Host 'G2_TV_INSTALL_PACKAGE_PRESENT_AFTER_UPDATE'
Write-Host 'G2_TV_INSTALL_NO_LAUNCH_NO_MEDIA_NO_TORRSERVER_NO_TV_E2E_CLAIM'
