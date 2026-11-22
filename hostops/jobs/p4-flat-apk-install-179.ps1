# Exactly one owner-authorized, non-destructive ARM32 Debug APK replacement.
# HostOps (NETWORK_SERVICE) uses the SHA-pinned private Android build cache.
# ADB install -r only; never uninstall, clear data, reboot, or alter pairing.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = '07fa06200cdb22074aee5b306a9c18d93895b8de'
$expectedPkg = 'com.spacesarmat.omp.test'
$expectedCert = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$buildTools = 'C:\TOOL\Android-SDK\build-tools'
$runnerRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

function Hold([string]$reason) { throw ('TTV_P4_INSTALL_HOLD_' + $reason) }
function ExactHash([string]$file) {
    (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function SingleTvProperty([string]$serial, [string]$key) {
    $values = @(& $adb -s $serial shell getprop $key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $values.Count -ne 1) { Hold 'TV_PROPERTY_UNAVAILABLE' }
    return ([string]$values[0]).Trim()
}

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $mySid -cne 'S-1-5-20') { Hold 'TRUSTED_WINDOWS_HOSTOPS_REQUIRED' }
foreach ($key in @('RUNNER_TEMP','RUNNER_WORKSPACE','GITHUB_WORKSPACE')) {
    if (-not [Environment]::GetEnvironmentVariable($key)) { Hold 'RUNNER_PATH_UNAVAILABLE' }
}
$allowedRoot = [IO.Path]::GetFullPath($runnerRoot).TrimEnd('\') + '\'
foreach ($path in @($env:RUNNER_WORKSPACE,$env:RUNNER_TEMP,$env:GITHUB_WORKSPACE)) {
    if (-not ([IO.Path]::GetFullPath($path).TrimEnd('\') + '\').StartsWith(
        $allowedRoot,[StringComparison]::OrdinalIgnoreCase)) {
        Hold 'RUNNER_PATH_OUTSIDE_TRUSTED_ROOT'
    }
}
$checkout = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $checkout -cnotmatch '^[0-9a-f]{40}$') {
    Hold 'HOSTOPS_PINNED_CHECKOUT_INVALID'
}
$jobPath = Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\p4-flat-apk-install-179.ps1'
if (-not (Test-Path -LiteralPath $jobPath -PathType Leaf)) { Hold 'EXACT_JOB_NOT_PRESENT' }

$stageDir = Join-Path $env:RUNNER_WORKSPACE ('_omp-fast-cache\p4-flat-staged\' + $source)
$receiptPath = Join-Path $stageDir 'stage-receipt.txt'
$apk = Join-Path $stageDir 'app-armeabi-v7a-debug.apk'
if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $apk -PathType Leaf)) {
    Hold 'EXACT_APK_NOT_STAGED'
}
if (((Get-Item -LiteralPath $receiptPath).Length -gt 2048) -or
    ((Get-Item -LiteralPath $apk).Length -lt 5000000) -or
    ((Get-Item -LiteralPath $apk).Length -gt 600000000)) {
    Hold 'STAGE_SIZE_UNEXPECTED'
}
$lines = @(Get-Content -LiteralPath $receiptPath -Encoding Ascii)
$needed = @(
    'schema=TTV-P4-FLAT-APK-STAGE-V1',
    ('app_commit=' + $source),
    'variant=app-armeabi-v7a-debug.apk',
    'artifact_placement=dedicated_windows_runner_private_cache',
    'device_installed=no'
)
foreach ($line in $needed) {
    if (@($lines | Where-Object { $_ -ceq $line }).Count -ne 1) {
        Hold 'STAGE_SOURCE_OR_SCHEMA_DRIFT'
    }
}
$shaLines = @($lines | Where-Object { $_ -cmatch '^sha256=[0-9a-f]{64}$' })
if ($shaLines.Count -ne 1) { Hold 'STAGE_HASH_RECEIPT_INVALID' }
$expectedHash = $shaLines[0].Substring(7)
if ((ExactHash $apk) -cne $expectedHash) { Hold 'STAGED_APK_HASH_MISMATCH' }
Write-Output 'TTV_P4_APK_STAGE=PINNED_ARM32_HASH_VERIFIED'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    -not (Test-Path -LiteralPath $buildTools -PathType Container)) {
    Hold 'ANDROID_SDK_MISSING'
}
$tools = @(Get-ChildItem -LiteralPath $buildTools -Directory | Where-Object {
    (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
} | Sort-Object Name -Descending)
if ($tools.Count -lt 1) { Hold 'APK_VERIFICATION_TOOLS_MISSING' }
$aapt = Join-Path $tools[0].FullName 'aapt.exe'
$apksigner = Join-Path $tools[0].FullName 'apksigner.bat'
$jdk = @(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory |
    Where-Object { $_.Name -like 'jdk-21*' -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe')) } |
    Sort-Object Name -Descending | Select-Object -First 1)
if ($jdk.Count -ne 1) { Hold 'JDK21_MISSING' }
$env:JAVA_HOME = $jdk[0].FullName
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH

if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    Hold 'ADB_SERVER_NOT_RUNNING'
}
$devices = @(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) { Hold 'ADB_DEVICES_FAILED' }
$online = @($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$bad = @($devices | Where-Object { $_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)' })
if ($online.Count -ne 1 -or $bad.Count -ne 0) { Hold 'SINGLE_AUTHORIZED_TV_NOT_AVAILABLE' }
$serial = ($online[0].Trim() -split '\s+')[0]
if ((SingleTvProperty $serial 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (SingleTvProperty $serial 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (SingleTvProperty $serial 'ro.build.version.sdk') -cne '30') {
    Hold 'TV_MODEL_ABI_OR_API_CHANGED'
}
Write-Output 'TTV_P4_TARGET=REDMI_ARM32_API30_CONFIRMED'

$packagePaths = @(& $adb -s $serial shell pm path $expectedPkg 2>$null)
if ($LASTEXITCODE -ne 0) { Hold 'EXISTING_OMP_DEBUG_NOT_INSTALLED' }
$basePaths = @($packagePaths | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
if ($basePaths.Count -ne 1) { Hold 'EXISTING_PACKAGE_BASE_NOT_UNIQUE' }
$baseOnTv = ([string]$basePaths[0]).Trim().Substring(8)
$scratch = Join-Path $env:RUNNER_TEMP ('p4-flat-install-179-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null

function QuietAdb([string[]]$arguments) {
    $out = Join-Path $scratch 'adb-out.txt'
    $err = Join-Path $scratch 'adb-err.txt'
    try {
        $process = Start-Process -FilePath $adb -ArgumentList (@('-s',$serial)+$arguments) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out `
            -RedirectStandardError $err -ErrorAction Stop
        $rows = if (Test-Path -LiteralPath $out -PathType Leaf) {
            @(Get-Content -LiteralPath $out)
        } else { @() }
        return @{exit=[int]$process.ExitCode;lines=@($rows)}
    } finally {
        foreach ($file in @($out,$err)) {
            if (Test-Path -LiteralPath $file -PathType Leaf) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
function PackageAndVersion([string]$file) {
    $badging = @(& $aapt dump badging $file 2>$null)
    if ($LASTEXITCODE -ne 0) { Hold 'AAPT_BADGING_FAILED' }
    $p = @($badging | Where-Object { $_ -match '^package: name=' })
    if ($p.Count -ne 1 -or $p[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
        Hold 'APK_PACKAGE_OR_VERSION_UNREADABLE'
    }
    return @{package=$Matches[1];version=[long]::Parse($Matches[2])}
}
function Certificate([string]$file) {
    $raw = @(& $apksigner verify --verbose --print-certs $file 2>$null)
    if ($LASTEXITCODE -ne 0) { Hold 'APK_CERT_VERIFY_FAILED' }
    return [string](Get-P4SingleSignerDigest -Lines $raw)
}

try {
    $oldApk = Join-Path $scratch 'omp-before.apk'
    $oldPull = QuietAdb @('pull',$baseOnTv,$oldApk)
    if ($oldPull.exit -ne 0 -or -not (Test-Path -LiteralPath $oldApk -PathType Leaf)) {
        Hold 'TV_EXISTING_APK_PULL_FAILED'
    }
    $oldInfo = PackageAndVersion $oldApk
    $newInfo = PackageAndVersion $apk
    if ($oldInfo.package -cne $expectedPkg -or $newInfo.package -cne $expectedPkg -or
        $newInfo.version -lt $oldInfo.version) {
        Hold 'PACKAGE_OR_VERSION_INCOMPATIBLE'
    }
    . (Join-Path $env:GITHUB_WORKSPACE 'poc\p4-auto-sub\cert-parser.ps1')
    $oldCert = Certificate $oldApk
    $newCert = Certificate $apk
    if ($oldCert -cne $newCert -or $newCert -cne $expectedCert) {
        Hold 'APP_SIGNING_CERT_MISMATCH'
    }
    Write-Output 'TTV_P4_PACKAGE_AND_SIGNER=COMPATIBLE'

    # Single mutation. Do not downgrade, uninstall or clear application data.
    $install = QuietAdb @('install','-r',$apk)
    if ($install.exit -ne 0 -or
        @($install.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
        Hold 'ADB_REPLACE_NOT_SUCCESSFUL'
    }
    Write-Output 'TTV_P4_ADB_REPLACE=SUCCESS_KEEP_APP_DATA'

    $afterPaths = @(& $adb -s $serial shell pm path $expectedPkg 2>$null)
    if ($LASTEXITCODE -ne 0) { Hold 'TV_POST_INSTALL_PACKAGE_MISSING' }
    $afterBases = @($afterPaths | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($afterBases.Count -ne 1) { Hold 'TV_POST_INSTALL_BASE_NOT_UNIQUE' }
    $afterFile = Join-Path $scratch 'omp-after.apk'
    $post = QuietAdb @('pull',([string]$afterBases[0]).Trim().Substring(8),$afterFile)
    if ($post.exit -ne 0 -or -not (Test-Path -LiteralPath $afterFile -PathType Leaf)) {
        Hold 'TV_POST_INSTALL_APK_PULL_FAILED'
    }
    if ((ExactHash $afterFile) -cne $expectedHash) { Hold 'TV_INSTALLED_HASH_MISMATCH' }
    Write-Output 'TTV_P4_INSTALL=REDMI_INSTALLED_EXACT_APK_HASH_VERIFIED'
    Write-Output ('TTV_P4_SOURCE=' + $source)
    Write-Output 'TTV_P4_SUBTITLE_E2E=NOT_TESTED'
} finally {
    if (Test-Path -LiteralPath $scratch -PathType Container) {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$global:LASTEXITCODE = 0
