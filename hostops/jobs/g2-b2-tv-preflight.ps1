# Torrent TV G2-B2 read-only readiness preflight.
# No ADB execution (not even "adb devices"), pairing, network probe, APK install,
# service restart, registry/filesystem modification, secret read, or TV mutation.
# Retention evidence is local to dedicated Torrent TV runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Proof([string]$why) { throw ('G2_TV_PREFLIGHT_HOLD: ' + $why) }
function Assert-NoLink([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { Stop-Proof 'REQUIRED_LOCAL_PATH_MISSING' }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Stop-Proof 'REPARSE_POINT_REFUSED'
    }
}
function Assert-ExclusiveDirectory([string]$path) {
    Assert-NoLink $path
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowed = @($identity,'S-1-5-18','S-1-5-32-544') | Select-Object -Unique
    $acl = (New-Object IO.DirectoryInfo($path)).GetAccessControl(
        [Security.AccessControl.AccessControlSections]::Access)
    if (-not $acl.AreAccessRulesProtected) { Stop-Proof 'ACL_INHERITANCE_ENABLED' }
    $aces = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    foreach ($ace in $aces) {
        if ($ace.IsInherited -or
            $ace.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            $ace.IdentityReference.Value -notin $allowed) {
            Stop-Proof 'VAULT_ACCESS_NOT_EXCLUSIVE'
        }
    }
    foreach ($sid in $allowed) {
        if (@($aces | Where-Object { $_.IdentityReference.Value -eq $sid }).Count -ne 1) {
            Stop-Proof 'VAULT_REQUIRED_ACE_MISSING'
        }
    }
}
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') { Stop-Proof 'UNTRUSTED_HOSTOPS_CONTEXT' }
$root = 'C:\TOOL\TorrentTV-Runner'
$private = Join-Path $root 'private-artifacts'
$vault = Join-Path $private 'G2B2'
$source = Join-Path $vault 'run-42949951699-1'
foreach ($dir in @($root,$private,$vault,$source)) {
    Assert-NoLink $dir
}
foreach ($dir in @($private,$vault,$source)) { Assert-ExclusiveDirectory $dir }

$apk = Join-Path $source 'app-armeabi-v7a-debug.apk'
$shaFile = Join-Path $source 'SHA256SUMS-G2-REFRESH.txt'
$proofFile = Join-Path $source 'G2-REFRESH-BUILD-EVIDENCE.txt'
$signatureFile = Join-Path $source 'SIGNATURE-STATUS.txt'
foreach ($path in @($apk,$shaFile,$proofFile,$signatureFile)) { Assert-NoLink $path }
if ((Get-Content -LiteralPath $signatureFile -Raw -Encoding Ascii).Trim() -cne 'SIGNATURE_VERIFIED') {
    Stop-Proof 'SIGNATURE_STATUS_NOT_VERIFIED'
}
$expectedSha = 'ba1f6485107f94ad855e8284cd48d5a1724b29b20b4d30916636525bfaa5a931'
$actualSha = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha -cne $expectedSha) { Stop-Proof 'RETAINED_APK_SHA_CHANGED' }

$matches = @((Get-Content -LiteralPath $shaFile -Encoding Ascii) |
    Where-Object { $_ -match '^[a-fA-F0-9]{64}  app-armeabi-v7a-debug\.apk$' })
if ($matches.Count -ne 1 -or $matches[0].Substring(0,64).ToLowerInvariant() -cne $expectedSha) {
    Stop-Proof 'RETAINED_SHA_MANIFEST_MISMATCH'
}
$evidence = @(Get-Content -LiteralPath $proofFile -Encoding UTF8)
$required = @(
    'app_commit=b0994c7b33b7dac1d8fdacda1c49af853c32285d',
    'run_id=42949951699',
    'source_set=feature/g2-refresh-vietsub-inplace-20261111'
)
foreach ($line in $required) {
    if (@($evidence | Where-Object { $_ -ceq $line }).Count -ne 1) {
        Stop-Proof 'RETAINED_PROVENANCE_MISMATCH'
    }
}
$buildTools = 'C:\TOOL\Android-SDK\build-tools'
if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) {
    Stop-Proof 'ANDROID_BUILD_TOOLS_ABSENT'
}
$signers = @(Get-ChildItem -LiteralPath $buildTools -Directory -ErrorAction Stop |
    Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
$aapts = @(Get-ChildItem -LiteralPath $buildTools -Directory -ErrorAction Stop |
    Sort-Object Name -Descending | ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
if ($signers.Count -lt 1 -or $aapts.Count -lt 1) {
    Stop-Proof 'APK_READ_ONLY_INSPECTION_TOOLS_ABSENT'
}
$signerResult = @(& $signers[0] verify --print-certs $apk 2>&1)
if ($LASTEXITCODE -ne 0) { Stop-Proof 'APK_SIGNATURE_VERIFY_FAILED' }
$digests = @($signerResult | ForEach-Object { "$_" } |
    Select-String -Pattern '(?i)certificate SHA-256 digest:\s*([0-9a-f]{64})' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.ToLowerInvariant() } |
    Select-Object -Unique)
if ($digests.Count -ne 1 -or $digests[0] -cne
    '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84') {
    Stop-Proof 'APK_DEBUG_CERT_MISMATCH'
}
$badging = @(& $aapts[0] dump badging $apk 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($badging | Where-Object { "$_" -match "^package:\s+name='com\.spacesarmat\.omp\.test'" }).Count -ne 1) {
    Stop-Proof 'APK_PACKAGE_NOT_EXPECTED'
}
Write-Host 'G2_TV_PREFLIGHT_PRIVATE_ARM32_SHA_AND_SIGNER_PASS'
Write-Host 'G2_TV_PREFLIGHT_PRIVATE_NTFS_ACL_PASS'
Write-Host 'G2_TV_PREFLIGHT_PROVENANCE_RUN_42949951699_PASS'

# Passive ADB tool/process inventory. DO NOT execute ADB or inspect device IDs,
# cached adb keys, LAN IP addresses, serials, names or TV media.
$adbTool = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$adbExists = Test-Path -LiteralPath $adbTool -PathType Leaf
$adbProcessCount = @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count
Write-Host ('G2_TV_PREFLIGHT_ADB_BINARY_PRESENT=' + "$adbExists".ToLowerInvariant())
Write-Host ('G2_TV_PREFLIGHT_ADB_PROCESS_RUNNING=' + ($adbProcessCount -gt 0).ToString().ToLowerInvariant())
Write-Host 'G2_TV_PREFLIGHT_TV_CONNECTION_NOT_CHECKED_NO_ADB_EXECUTED'
Write-Host 'G2_TV_PREFLIGHT_READ_ONLY_COMPLETE_NO_DEVICE_ACTION'
