# Owner-approved one-shot OMP ARM32 Debug replacement on the dedicated
# Torrent TV runner. Reuse the exact privately staged FLAT CI APK; no rebuild.
# No uninstall, data clear, downgrade, TV reboot, provider or LAN changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$source = '5e3ce11f76828daa2d5aa72cacc7514e74dc152e'
$expectedApkHash = 'a0240a4eaa814225d8e512da3c9a7ca860cda1ede8a1303b49db1ee1bb719ba3'
$expectedCert = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$pkg = 'com.spacesarmat.omp.test'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$buildTools = 'C:\TOOL\Android-SDK\build-tools'

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_ACTOR -cne 'trung-via' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'FLAT_INSTALL_TRUSTED_HOSTOPS_RUNNER_REQUIRED'
}
$runnerRoot = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
foreach ($dir in @($env:GITHUB_WORKSPACE, $env:RUNNER_WORKSPACE, $env:RUNNER_TEMP)) {
    if ([string]::IsNullOrWhiteSpace($dir) -or
        -not ([IO.Path]::GetFullPath($dir).TrimEnd('\') + '\').StartsWith(
            $runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'FLAT_INSTALL_RUNNER_WORKSPACE_INVALID'
    }
}
$stage = Join-Path $env:RUNNER_WORKSPACE ('_omp-fast-cache\p4-flat-staged\' + $source)
$apk = Join-Path $stage 'app-armeabi-v7a-debug.apk'
$receiptFile = Join-Path $stage 'stage-receipt.txt'
foreach ($path in @($stage, $apk, $receiptFile)) {
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'FLAT_INSTALL_UNTRUSTED_STAGE_PATH'
    }
}
$receipt = @(Get-Content -LiteralPath $receiptFile -ErrorAction Stop)
$required = @(
    'schema=TTV-P4-FLAT-APK-STAGE-V1',
    ('app_commit=' + $source),
    'omp_commit=52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f',
    'submodule_commit=6ba6edd39f5d986ddfae29b5425b8ac0b319844e',
    'variant=app-armeabi-v7a-debug.apk',
    ('sha256=' + $expectedApkHash),
    'artifact_placement=dedicated_windows_runner_private_cache',
    'device_installed=no',
    'real_lan_tested=no'
)
if ($receipt.Count -ne $required.Count -or
    @($required | Where-Object { $receipt -cnotcontains $_ }).Count -ne 0 -or
    (Get-Item -LiteralPath $apk).Length -lt 5000000 -or
    (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkHash) {
    throw 'FLAT_INSTALL_STAGE_RECEIPT_OR_APK_HASH_MISMATCH'
}
Write-Output 'FLAT_INSTALL_STAGE=EXACT_SOURCE_AND_APK_SHA_VERIFIED'

if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    -not (Test-Path -LiteralPath $buildTools -PathType Container) -or
    @(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    throw 'FLAT_INSTALL_ADB_NOT_READY'
}
$versions = @(Get-ChildItem -LiteralPath $buildTools -Directory -ErrorAction Stop |
    Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe')) -and
                   (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat')) } |
    Sort-Object Name -Descending)
if ($versions.Count -eq 0) { throw 'FLAT_INSTALL_BUILD_TOOLS_NOT_READY' }
$aapt = Join-Path $versions[0].FullName 'aapt.exe'
$apksigner = Join-Path $versions[0].FullName 'apksigner.bat'
$jdk = @(Get-ChildItem -LiteralPath 'C:\Program Files\Eclipse Adoptium' -Directory |
    Where-Object { $_.Name -like 'jdk-21*' -and
                   (Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe')) } |
    Sort-Object Name -Descending | Select-Object -First 1)
if ($jdk.Count -ne 1) { throw 'FLAT_INSTALL_JDK21_REQUIRED' }
$env:JAVA_HOME = $jdk[0].FullName
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH

$devices = @(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'FLAT_INSTALL_ADB_DEVICES_FAILED' }
$authorized = @($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$other = @($devices | Where-Object { $_ -match '^[^\s]+\s+(offline|unauthorized)(\s|$)' })
if ($authorized.Count -ne 1 -or $other.Count -ne 0) {
    Write-Output 'FLAT_INSTALL_ADB=ONE_AUTHORIZED_REDMi_REQUIRED'
    throw 'FLAT_INSTALL_ADB_NOT_SINGLE_AUTHORIZED_TV'
}
$serial = ($authorized[0].Trim() -split '\s+')[0]
function ReadProp([string]$name) {
    $value = @(& $adb -s $serial shell getprop $name 2>$null)
    if ($LASTEXITCODE -ne 0 -or $value.Count -ne 1) {
        throw 'FLAT_INSTALL_TV_PROPERTIES_UNAVAILABLE'
    }
    return ([string]$value[0]).Trim()
}
if ((ReadProp 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (ReadProp 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (ReadProp 'ro.build.version.sdk') -cne '30') {
    throw 'FLAT_INSTALL_TV_IDENTITY_MISMATCH'
}
Write-Output 'FLAT_INSTALL_REDMi=EXACT_MODEL_ABI_API'

$installed = @(& $adb -s $serial shell pm path $pkg 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'FLAT_INSTALL_EXISTING_DEBUG_PACKAGE_REQUIRED' }
$bases = @($installed | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
if ($bases.Count -ne 1) { throw 'FLAT_INSTALL_EXISTING_BASE_APK_REQUIRED' }
$remoteBase = ([string]$bases[0]).Trim().Substring(8)
$tmp = Join-Path $env:RUNNER_TEMP ('ttv-flat-install-' + $env:GITHUB_RUN_ID + '-' + $env:GITHUB_RUN_ATTEMPT)
if (Test-Path -LiteralPath $tmp) { throw 'FLAT_INSTALL_TEMP_COLLISION' }
New-Item -ItemType Directory -Path $tmp -ErrorAction Stop | Out-Null
function InvokeQuietAdb([string[]]$argsList) {
    $outFile = Join-Path $tmp 'adb-out.txt'
    $errFile = Join-Path $tmp 'adb-err.txt'
    try {
        $p = Start-Process -FilePath $adb -ArgumentList (@('-s', $serial) + $argsList) `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile -ErrorAction Stop
        $lines = if (Test-Path -LiteralPath $outFile) {
            @(Get-Content -LiteralPath $outFile -ErrorAction Stop)
        } else { @() }
        return @{ code = [int]$p.ExitCode; lines = @($lines) }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}
function ReadApkIdentity([string]$path) {
    $lines = @(& $aapt dump badging $path 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'FLAT_INSTALL_AAPT_FAILED' }
    $packageLines = @($lines | Where-Object { $_ -match '^package: name=' })
    if ($packageLines.Count -ne 1 -or
        $packageLines[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
        throw 'FLAT_INSTALL_PACKAGE_IDENTITY_UNREADABLE'
    }
    return @{ name = $Matches[1]; version = [long]::Parse($Matches[2]) }
}
. (Join-Path $env:GITHUB_WORKSPACE 'poc\p4-auto-sub\cert-parser.ps1')
function ReadSigner([string]$path) {
    $lines = @(& $apksigner verify --verbose --print-certs $path 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'FLAT_INSTALL_APK_SIGNATURE_VERIFY_FAILED' }
    return (Get-P4SingleSignerDigest -Lines $lines)
}
try {
    $oldApk = Join-Path $tmp 'installed-before.apk'
    $pulled = InvokeQuietAdb @('pull', $remoteBase, $oldApk)
    if ($pulled.code -ne 0 -or -not (Test-Path -LiteralPath $oldApk -PathType Leaf)) {
        throw 'FLAT_INSTALL_EXISTING_APK_PULL_FAILED'
    }
    $old = ReadApkIdentity $oldApk
    $new = ReadApkIdentity $apk
    if ($old.name -cne $pkg -or $new.name -cne $pkg -or
        $new.version -lt $old.version) {
        throw 'FLAT_INSTALL_PACKAGE_OR_VERSION_MISMATCH'
    }
    $oldCert = ReadSigner $oldApk
    $newCert = ReadSigner $apk
    if ($oldCert -cne $newCert -or $newCert -cne $expectedCert) {
        throw 'FLAT_INSTALL_SIGNER_MISMATCH_NO_INSTALL'
    }
    Write-Output 'FLAT_INSTALL_PREFLIGHT=PACKAGE_VERSION_AND_SIGNER_PASS'

    # Retain the original APK code for a future, separately authorized
    # recovery. This is NOT an app-data backup and never touches TV data.
    $backupRoot = Join-Path $env:RUNNER_WORKSPACE '_omp-fast-cache\p4-installed-apk-backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $oldHash = (Get-FileHash -LiteralPath $oldApk -Algorithm SHA256).Hash.ToLowerInvariant()
    $backup = Join-Path $backupRoot ($oldHash + '.apk')
    if (Test-Path -LiteralPath $backup -PathType Leaf) {
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $oldHash) {
            throw 'FLAT_INSTALL_BACKUP_HASH_DRIFT'
        }
    } else {
        Copy-Item -LiteralPath $oldApk -Destination $backup -ErrorAction Stop
        if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash.ToLowerInvariant() -cne $oldHash) {
            throw 'FLAT_INSTALL_BACKUP_VERIFY_FAILED'
        }
    }
    Write-Output 'FLAT_INSTALL_PREVIOUS_APK=PRIVATE_BACKUP_VERIFIED'

    # Recheck a fresh Owner-produced receipt immediately before replacing TV code.
    $snapshotFile = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
    $snapshotItem = Get-Item -LiteralPath $snapshotFile -Force -ErrorAction Stop
    if ($snapshotItem.Length -gt 4096 -or ($snapshotItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'G1_OWNER_SNAPSHOT_INVALID' }
    $snapshot = Get-Content -LiteralPath $snapshotFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$snapshot.snapshot_utc_epoch
    if ($age -lt 0 -or $age -gt 30 -or $snapshot.status -cne 'READY_FRESH' -or
        $snapshot.p2.status -cne 'CLEAR' -or $snapshot.p2.inflight_count -ne 0 -or
        $snapshot.p2.pending_events -ne 0) { throw 'G1_OWNER_NOT_IDLE_NO_INSTALL' }
    if ($oldHash -ceq $expectedApkHash) {
        Write-Output 'FLAT_INSTALL_REDMi_APK=ALREADY_EXACT_SHA256_NO_REPLACE'
        return
    }
    # Sole TV mutation; -r preserves the existing package data and pairing.
    $applied = InvokeQuietAdb @('install', '-r', $apk)
    if ($applied.code -ne 0 -or
        @($applied.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
        throw 'FLAT_INSTALL_ADB_REPLACE_FAILED_NO_BLIND_RETRY'
    }
    Write-Output 'FLAT_INSTALL_ADB_REPLACE=SUCCESS_DATA_PRESERVED'

    $after = @(& $adb -s $serial shell pm path $pkg 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'FLAT_INSTALL_POST_PACKAGE_UNAVAILABLE' }
    $afterBase = @($after | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($afterBase.Count -ne 1) { throw 'FLAT_INSTALL_POST_BASE_APK_MISSING' }
    $pulledAfter = Join-Path $tmp 'installed-after.apk'
    $pulled = InvokeQuietAdb @('pull', ([string]$afterBase[0]).Trim().Substring(8), $pulledAfter)
    if ($pulled.code -ne 0 -or -not (Test-Path -LiteralPath $pulledAfter -PathType Leaf) -or
        (Get-FileHash -LiteralPath $pulledAfter -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkHash) {
        throw 'FLAT_INSTALL_POST_HASH_NOT_VERIFIED_NO_REPEAT'
    }
    Write-Output 'FLAT_INSTALL_REDMi_APK=EXACT_SHA256_READBACK_VERIFIED'
    Write-Output ('FLAT_INSTALL_APK_SHA256=' + $expectedApkHash)
    Write-Output 'FLAT_INSTALL_DONE=DEBUG_APP_UPDATED_NO_TV_RENDER_CLAIM'
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
