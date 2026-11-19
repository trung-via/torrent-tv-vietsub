# Torrent TV one-shot Owner-approved Redmi OMP P3 UI fix install.
# Invoke ONLY via the trusted /tv-hostops run <exact-branch-SHA> omp-fix-install.
# No rebuild, download, release, uninstall, data clear, Owner restart or provider call.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sourceSha = '02a8dc3a6a53c6386fe84c22fb7a44348fe37289'
$expectedApkSha = 'd91960538824394d22f08bffc74af6f5765674f2fd7a319edb3669deb704f8a9'
$expectedCert = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$package = 'com.spacesarmat.omp.test'
$runnerRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$toolsRoot = 'C:\TOOL\Android-SDK\build-tools'

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTOR -cne 'trung-via' -or
    $env:HOSTOPS_REQUEST -cnotmatch '^/tv-hostops run [a-f0-9]{40} omp-fix-install$') {
    throw 'OMP_FIX_INSTALL_WRONG_HOSTOPS_CONTEXT'
}
$root = [IO.Path]::GetFullPath($runnerRoot).TrimEnd('\') + '\'
foreach ($key in @('RUNNER_WORKSPACE','RUNNER_TEMP','GITHUB_WORKSPACE')) {
    $value = [Environment]::GetEnvironmentVariable($key)
    if (-not $value -or -not ([IO.Path]::GetFullPath($value).TrimEnd('\') + '\').StartsWith(
        $root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OMP_FIX_INSTALL_UNEXPECTED_RUNNER_PATH'
    }
}

# The exact source build was already compiled by FLAT Android CI #44575977840.
# Never use an arbitrary APK or a later build's similarly named artifact.
$stage = Join-Path $env:RUNNER_WORKSPACE ('_omp-fast-cache\p4-flat-staged\' + $sourceSha)
$apk = Join-Path $stage 'app-armeabi-v7a-debug.apk'
$receiptPath = Join-Path $stage 'stage-receipt.txt'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf) -or
    -not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or
    (Get-Item -LiteralPath $apk).Length -lt 5000000) {
    throw 'OMP_FIX_INSTALL_STAGED_APK_NOT_AVAILABLE'
}
$receipt = @(Get-Content -LiteralPath $receiptPath -ErrorAction Stop)
$required = @(
    'schema=TTV-P4-FLAT-APK-STAGE-V1',
    ('app_commit=' + $sourceSha),
    'variant=app-armeabi-v7a-debug.apk',
    ('sha256=' + $expectedApkSha),
    'artifact_placement=dedicated_windows_runner_private_cache',
    'device_installed=no'
)
if (@($required | Where-Object { $receipt -cnotcontains $_ }).Count -ne 0 -or
    (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkSha) {
    throw 'OMP_FIX_INSTALL_APK_OR_RECEIPT_SHA_MISMATCH'
}
Write-Host 'OMP_FIX_SOURCE_AND_APK_SHA256=VERIFIED'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    -not (Test-Path -LiteralPath $toolsRoot -PathType Container) -or
    @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    throw 'OMP_FIX_INSTALL_ADB_NOT_READY'
}
$sdk = @(Get-ChildItem -LiteralPath $toolsRoot -Directory |
    Where-Object { (Test-Path (Join-Path $_.FullName 'aapt.exe')) -and
                   (Test-Path (Join-Path $_.FullName 'apksigner.bat')) } |
    Sort-Object Name -Descending | Select-Object -First 1)
$jdk = @(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory |
    Where-Object { $_.Name -like 'jdk-21*' -and
                   (Test-Path (Join-Path $_.FullName 'bin\java.exe')) } |
    Sort-Object Name -Descending | Select-Object -First 1)
if ($sdk.Count -ne 1 -or $jdk.Count -ne 1) { throw 'OMP_FIX_INSTALL_SIGNER_TOOLS_MISSING' }
$env:JAVA_HOME = $jdk[0].FullName
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH
$aapt = Join-Path $sdk[0].FullName 'aapt.exe'
$apksigner = Join-Path $sdk[0].FullName 'apksigner.bat'

$tmp = Join-Path $env:RUNNER_TEMP ('omp-fix-install-' + $env:GITHUB_RUN_ID + '-' + $env:GITHUB_RUN_ATTEMPT)
if (Test-Path -LiteralPath $tmp) { throw 'OMP_FIX_INSTALL_TEMP_ALREADY_EXISTS' }
New-Item -ItemType Directory -Path $tmp -ErrorAction Stop | Out-Null
try {
    # ADB output stays in private temporary files. The public job log has no
    # device serial, movie URL, personal data or certificate material.
    function Invoke-QuietAdb([string[]]$arguments) {
        $out = Join-Path $tmp 'adb-out.txt'
        $err = Join-Path $tmp 'adb-err.txt'
        try {
            $p = Start-Process -FilePath $adb -ArgumentList $arguments -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $out -RedirectStandardError $err -ErrorAction Stop
            $lines = if (Test-Path -LiteralPath $out -PathType Leaf) {
                @(Get-Content -LiteralPath $out -ErrorAction Stop)
            } else { @() }
            return [pscustomobject]@{ code=[int]$p.ExitCode; lines=@($lines) }
        } finally {
            foreach ($file in @($out,$err)) {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    function Require-Adb([string[]]$arguments) {
        $result = Invoke-QuietAdb $arguments
        if ($result.code -ne 0) { throw 'OMP_FIX_INSTALL_ADB_COMMAND_FAILED' }
        return $result
    }
    $devices = Require-Adb @('devices')
    $authorized = @($devices.lines | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
    $unready = @($devices.lines | Where-Object { $_ -match '^[^\s]+\s+(offline|unauthorized)(\s|$)' })
    if ($authorized.Count -ne 1 -or $unready.Count -ne 0) {
        throw 'OMP_FIX_INSTALL_REQUIRE_EXACTLY_ONE_AUTHORIZED_TV'
    }
    $serial = ($authorized[0].Trim() -split '\s+')[0]
    function Tv-Value([string]$name) {
        $result = Require-Adb @('-s',$serial,'shell','getprop',$name)
        if ($result.lines.Count -ne 1) { throw 'OMP_FIX_INSTALL_TV_PROPERTY_MISSING' }
        return ([string]$result.lines[0]).Trim()
    }
    if ((Tv-Value 'ro.product.model') -cne 'MiTV-ASTR0' -or
        (Tv-Value 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
        (Tv-Value 'ro.build.version.sdk') -cne '30') {
        throw 'OMP_FIX_INSTALL_WRONG_TV_MODEL_ABI_OR_SDK'
    }
    Write-Host 'OMP_FIX_TV_MODEL_ABI_SDK=VERIFIED'

    function Base-ApkPath() {
        $paths = Require-Adb @('-s',$serial,'shell','pm','path',$package)
        $base = @($paths.lines | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
        if ($base.Count -ne 1) { throw 'OMP_FIX_INSTALL_EXISTING_PACKAGE_MISSING' }
        return ([string]$base[0]).Trim().Substring(8)
    }
    function Apk-Info([string]$file) {
        $lines = @(& $aapt dump badging $file 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'OMP_FIX_INSTALL_PACKAGE_BADGING_FAILED' }
        $row = @($lines | Where-Object { $_ -match '^package: name=' })
        if ($row.Count -ne 1 -or
            $row[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
            throw 'OMP_FIX_INSTALL_PACKAGE_IDENTITY_UNREADABLE'
        }
        return @{ name=$Matches[1]; version=[long]::Parse($Matches[2]) }
    }
    . (Join-Path $env:GITHUB_WORKSPACE 'poc\p4-auto-sub\cert-parser.ps1')
    function Apk-Cert([string]$file) {
        $lines = @(& $apksigner verify --verbose --print-certs $file 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'OMP_FIX_INSTALL_SIGNER_VERIFY_FAILED' }
        return [string](Get-P4SingleSignerDigest -Lines $lines)
    }

    $before = Join-Path $tmp 'before.apk'
    $read = Require-Adb @('-s',$serial,'pull',(Base-ApkPath),$before)
    if (-not (Test-Path -LiteralPath $before -PathType Leaf)) {
        throw 'OMP_FIX_INSTALL_CURRENT_APK_UNREADABLE'
    }
    $old = Apk-Info $before
    $new = Apk-Info $apk
    if ($old.name -cne $package -or $new.name -cne $package -or
        $new.version -lt $old.version) {
        throw 'OMP_FIX_INSTALL_PACKAGE_OR_DOWNGRADE_BLOCKED'
    }
    if ((Apk-Cert $before) -cne $expectedCert -or
        (Apk-Cert $apk) -cne $expectedCert) {
        throw 'OMP_FIX_INSTALL_DEBUG_SIGNER_MISMATCH'
    }
    Write-Host 'OMP_FIX_INSTALLED_AND_CANDIDATE_PACKAGE_SIGNER=VERIFIED'

    $beforeHash = (Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($beforeHash -cne $expectedApkSha) {
        $install = Require-Adb @('-s',$serial,'install','-r',$apk)
        if (@($install.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
            throw 'OMP_FIX_INSTALL_REPLACE_NOT_CONFIRMED'
        }
        Write-Host 'OMP_FIX_ADB_REPLACE=SUCCESS_DATA_PRESERVED'
    } else {
        Write-Host 'OMP_FIX_ADB_REPLACE=ALREADY_CURRENT_NO_WRITE'
    }

    $after = Join-Path $tmp 'after.apk'
    $verify = Require-Adb @('-s',$serial,'pull',(Base-ApkPath),$after)
    if (-not (Test-Path -LiteralPath $after -PathType Leaf) -or
        (Get-FileHash -LiteralPath $after -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkSha) {
        throw 'OMP_FIX_INSTALL_READBACK_HASH_MISMATCH'
    }
    Write-Host ('OMP_FIX_INSTALLED_ARM32_SHA256=' + $expectedApkSha)
    Write-Host 'OMP_FIX_TV_APK=VERIFIED_NOT_SUBTITLE_E2E'
} finally {
    if (Test-Path -LiteralPath $tmp -PathType Container) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$global:LASTEXITCODE = 0
