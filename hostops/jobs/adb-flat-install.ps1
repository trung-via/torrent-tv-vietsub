# Owner-approved, one-device FLAT Debug APK replacement using an already built,
# private staged APK from exact PR #172 source. No uninstall, data clear, TV
# reboot, ADB pairing change, provider call, or public APK upload.
# Execute solely through the existing SHA-pinned Torrent TV HostOps #82 inbox.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repo = 'trung-via/torrent-tv-vietsub'
$branch = 'feature/r0-flat-integrated-source-20261117'
$head = '6710dca6cae8e6c499c6b397f1f27b4bfd877955'
$expectedApkSha = 'e548329835ed9a938e30f0c44270e718a623eaacb472c697fbd5665178e6536a'
$expectedCert = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$pkg = 'com.spacesarmat.omp.test'
$runnerRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'

function Hold([string]$Reason) { throw ('TTV_FLAT_INSTALL_HOLD_' + $Reason) }
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') { Hold 'WRONG_OWNER_RUNNER' }
$allowed = [IO.Path]::GetFullPath($runnerRoot).TrimEnd('\') + '\'
foreach ($key in @('RUNNER_WORKSPACE', 'RUNNER_TEMP', 'GITHUB_WORKSPACE')) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if ([string]::IsNullOrWhiteSpace($value) -or
        -not ([IO.Path]::GetFullPath($value).TrimEnd('\') + '\').StartsWith(
            $allowed, [StringComparison]::OrdinalIgnoreCase)) {
        Hold 'RUNNER_WORKSPACE_IDENTITY'
    }
}

# Do not install a formerly current head after the PR has moved.
try {
    $ref = Invoke-RestMethod -Uri (
        'https://api.github.com/repos/' + $repo + '/git/ref/heads/' + $branch) `
        -Headers @{'Accept'='application/vnd.github+json'; 'User-Agent'='TorrentTV-FLAT-APK-Install'} `
        -Method Get -TimeoutSec 20 -ErrorAction Stop
} catch { Hold 'LATEST_PR_HEAD_UNAVAILABLE' }
if ($ref.object.type -cne 'commit' -or $ref.object.sha -cne $head) {
    Hold 'PR_HEAD_CHANGED'
}
Write-Host 'TTV_FLAT_INSTALL_SOURCE_HEAD=PINNED_CURRENT'

$cache = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache'
$staged = Join-Path $cache ('p4-flat-staged\' + $head)
$apk = Join-Path $staged 'app-armeabi-v7a-debug.apk'
$receipt = Join-Path $staged 'stage-receipt.txt'
foreach ($file in @($apk, $receipt, $adb)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Hold 'REQUIRED_PRIVATE_FILE_MISSING' }
    $item = Get-Item -LiteralPath $file -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Hold 'REPARSE_POINT' }
}
$lines = @(Get-Content -LiteralPath $receipt -ErrorAction Stop)
foreach ($required in @(
    'schema=TTV-P4-FLAT-APK-STAGE-V1',
    ('app_commit=' + $head),
    'variant=app-armeabi-v7a-debug.apk',
    ('sha256=' + $expectedApkSha),
    'artifact_placement=dedicated_windows_runner_private_cache',
    'device_installed=no'
)) {
    if (@($lines | Where-Object { $_ -ceq $required }).Count -ne 1) {
        Hold 'STAGED_RECEIPT_NOT_EXACT'
    }
}
$apkBytes = (Get-Item -LiteralPath $apk).Length
if ($apkBytes -lt 5000000 -or $apkBytes -gt 600000000) { Hold 'APK_SIZE_INVALID' }
$candidateHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($candidateHash -cne $expectedApkSha) { Hold 'STAGED_APK_HASH_MISMATCH' }
Write-Host 'TTV_FLAT_INSTALL_APK_SHA256=EXACT_BUILD_RECEIPT_PASS'

$buildToolsRoot = 'C:\TOOL\Android-SDK\build-tools'
if (-not (Test-Path -LiteralPath $buildToolsRoot -PathType Container)) { Hold 'BUILD_TOOLS_MISSING' }
$buildTools = @(Get-ChildItem -LiteralPath $buildToolsRoot -Directory |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
    } | Sort-Object Name -Descending)
if ($buildTools.Count -lt 1) { Hold 'APK_VERIFY_TOOLS_MISSING' }
$aapt = Join-Path $buildTools[0].FullName 'aapt.exe'
$apksigner = Join-Path $buildTools[0].FullName 'apksigner.bat'
$jdk = @(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory |
    Where-Object { $_.Name -like 'jdk-21*' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') -PathType Leaf) } |
    Sort-Object Name -Descending | Select-Object -First 1)
if ($jdk.Count -ne 1) { Hold 'JDK21_MISSING' }
$env:JAVA_HOME = $jdk[0].FullName
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH

function GetPackageVersion([string]$Path) {
    $badging = @(& $aapt dump badging $Path 2>$null)
    if ($LASTEXITCODE -ne 0) { Hold 'AAPT_BADGING_FAILED' }
    $pkgLines = @($badging | Where-Object { $_ -match '^package: name=' })
    if ($pkgLines.Count -ne 1 -or
        $pkgLines[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
        Hold 'APK_PACKAGE_IDENTITY_UNREADABLE'
    }
    return @{ package = [string]$Matches[1]; version = [long]::Parse($Matches[2]) }
}
function GetSigner([string]$Path) {
    $report = @(& $apksigner verify --verbose --print-certs $Path 2>$null)
    if ($LASTEXITCODE -ne 0 -or
        @($report | Where-Object { ([string]$_).Trim() -ceq 'Verifies' }).Count -ne 1) {
        Hold 'APK_SIGNATURE_VERIFICATION_FAILED'
    }
    $counts = @($report | Where-Object { $_ -match '^\s*Number of signers:\s*1\s*$' })
    if ($counts.Count -ne 1) { Hold 'SIGNER_COUNT_NOT_ONE' }
    $allCertLines = @($report | Where-Object { $_ -match '(?i)certificate\s+SHA-256\s+digest:' })
    if ($allCertLines.Count -lt 1) { Hold 'CERT_DIGEST_MISSING' }
    $parsed = @()
    foreach ($line in $allCertLines) {
        if ($line -match '(?i)^\s*(?:Signer\s*#\s*1|V[1-9][0-9]*(?:\.[0-9]+)?\s+Signer:)\s*certificate\s+SHA-256\s+digest:\s*([a-f0-9]{64})\s*$') {
            $parsed += $Matches[1].ToLowerInvariant()
        } else { Hold 'CERT_DIGEST_FORMAT_UNKNOWN' }
    }
    $unique = @($parsed | Sort-Object -Unique)
    if ($unique.Count -ne 1 -or $parsed.Count -ne $allCertLines.Count) {
        Hold 'CERT_SCHEME_DIGEST_DIVERGENCE'
    }
    return [string]$unique[0]
}

if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -lt 1) {
    Hold 'ADB_SERVER_NOT_RUNNING'
}
$allDevices = @(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) { Hold 'ADB_LIST_FAILED' }
$ready = @($allDevices | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' })
$bad = @($allDevices | Where-Object { $_ -match '^\S+\s+(unauthorized|offline)(?:\s|$)' })
if ($ready.Count -ne 1 -or $bad.Count -ne 0) { Hold 'NOT_EXACTLY_ONE_AUTHORIZED_TV' }
$serial = ($ready[0].Trim() -split '\s+')[0]

$temp = Join-Path $env:RUNNER_TEMP ('tv-flat-install-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -ErrorAction Stop | Out-Null
try {
    function Adb([string[]]$ArgsList) {
        $out = Join-Path $temp 'adb-output.txt'
        $err = Join-Path $temp 'adb-error.txt'
        try {
            $proc = Start-Process -FilePath $adb -ArgumentList (@('-s', $serial) + $ArgsList) `
                -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out `
                -RedirectStandardError $err -ErrorAction Stop
            $text = @(Get-Content -LiteralPath $out -ErrorAction Stop)
            return @{ code = [int]$proc.ExitCode; lines = @($text) }
        } finally {
            foreach ($p in @($out, $err)) {
                if (Test-Path -LiteralPath $p) {
                    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    function GetTvProp([string]$Name) {
        $result = Adb @('shell', 'getprop', $Name)
        if ($result.code -ne 0 -or $result.lines.Count -ne 1) {
            Hold 'DEVICE_PROPERTY_UNREADABLE'
        }
        return ([string]$result.lines[0]).Trim()
    }
    if ((GetTvProp 'ro.product.model') -cne 'MiTV-ASTR0' -or
        (GetTvProp 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
        (GetTvProp 'ro.build.version.sdk') -cne '30') {
        Hold 'DEVICE_IDENTITY_CHANGED'
    }
    Write-Host 'TTV_FLAT_INSTALL_TARGET=EXACT_REDMi_VERIFIED'

    function GetInstalledBase {
        $result = Adb @('shell', 'pm', 'path', $pkg)
        if ($result.code -ne 0) { Hold 'APP_NOT_INSTALLED' }
        $base = @($result.lines | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
        if ($base.Count -ne 1) { Hold 'INSTALLED_BASE_UNKNOWN' }
        return ([string]$base[0]).Trim().Substring(8)
    }
    $oldPath = GetInstalledBase
    $oldApk = Join-Path $temp 'installed-before.apk'
    $oldPull = Adb @('pull', $oldPath, $oldApk)
    if ($oldPull.code -ne 0 -or -not (Test-Path -LiteralPath $oldApk -PathType Leaf)) {
        Hold 'INSTALLED_APK_READBACK_FAILED'
    }
    $before = GetPackageVersion $oldApk
    $after = GetPackageVersion $apk
    if ($before.package -cne $pkg -or $after.package -cne $pkg) {
        Hold 'PACKAGE_NAME_MISMATCH'
    }
    if ($after.version -lt $before.version) { Hold 'VERSION_DOWNGRADE' }
    Write-Host 'TTV_FLAT_INSTALL_PACKAGE_VERSION=NO_DOWNGRADE'
    $beforeCert = GetSigner $oldApk
    $afterCert = GetSigner $apk
    if ($beforeCert -cne $afterCert -or $afterCert -cne $expectedCert) {
        Hold 'SIGNATURE_MISMATCH_KEEP_INSTALLED_APP'
    }
    Write-Host 'TTV_FLAT_INSTALL_SIGNER=EXACT_MATCH'
    $beforeHash = (Get-FileHash -LiteralPath $oldApk -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($beforeHash -ceq $expectedApkSha) {
        Write-Host 'TTV_FLAT_INSTALL=ALREADY_INSTALLED_EXACT_SHA'
        exit 0
    }

    # Save the prior *code APK only* in a private recoverable cache. No app data.
    $recovery = Join-Path $cache 'tv-install-recovery'
    New-Item -ItemType Directory -Path $recovery -Force -ErrorAction Stop | Out-Null
    $backup = Join-Path $recovery ('before-' + $beforeHash + '.apk')
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $oldApk -Destination $backup -ErrorAction Stop
    }
    if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $beforeHash) {
        Hold 'OLD_APK_BACKUP_MISMATCH'
    }
    Write-Host 'TTV_FLAT_INSTALL_PRIOR_APK=BACKED_UP_PRIVATELY'

    # Sole TV mutation: same-package same-signer replacement; -r preserves data.
    $result = Adb @('install', '-r', $apk)
    if ($result.code -ne 0 -or
        @($result.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
        Hold 'ADB_REPLACE_FAILED_NO_UNINSTALL'
    }
    Write-Host 'TTV_FLAT_INSTALL_ADB_REPLACE=SUCCESS_PRESERVE_DATA'
    $newPath = GetInstalledBase
    $readback = Join-Path $temp 'installed-after.apk'
    $pulled = Adb @('pull', $newPath, $readback)
    if ($pulled.code -ne 0 -or -not (Test-Path -LiteralPath $readback -PathType Leaf)) {
        Hold 'POSTINSTALL_READBACK_FAILED'
    }
    $seen = (Get-FileHash -LiteralPath $readback -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($seen -cne $expectedApkSha) { Hold 'POSTINSTALL_HASH_MISMATCH' }
    Write-Host 'TTV_FLAT_INSTALL=PASS_VERIFIED_EXACT_APK_SHA256'
    Write-Host 'TTV_FLAT_INSTALL_APP_DATA=CLEARED_NO'
    Write-Host 'TTV_FLAT_INSTALL_REAL_SUBTITLE_E2E=NOT_RUN'
} finally {
    if (Test-Path -LiteralPath $temp -PathType Container) {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
