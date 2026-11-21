# One-film, one-APK install via the trusted Torrent TV HostOps runner.
# Exact source PR #178 APK is already built and staged in the runner-private
# cache. This operation never rebuilds, calls a provider, restarts Owner,
# clears app data, uninstalls, downgrades or touches unrelated ADB devices.
[CmdletBinding()]
param([switch]$PreflightOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedCommit = '2fe92888364ec212c341f756da92a7c47e6c06f1'
$expectedApkSha = '478bfaf344cd55540576d8c951bc08e9db400965e8e0030237d5c2ca8b7663ce'
$expectedSigner = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$pkg = 'com.spacesarmat.omp.test'
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
$runnerRoot = 'C:\TOOL\TorrentTV-Runner\_work'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if ($PSVersionTable.PSVersion.Major -lt 7 -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or $sid -cne 'S-1-5-20') {
    throw 'P4_PR178_INSTALL_TRUSTED_PWSH7_SERVICE_RUNNER_REQUIRED'
}
$workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\'
$allowed = [IO.Path]::GetFullPath($runnerRoot).TrimEnd('\') + '\'
foreach ($location in @($env:GITHUB_WORKSPACE, $env:RUNNER_WORKSPACE, $env:RUNNER_TEMP)) {
    if ([string]::IsNullOrWhiteSpace($location) -or
        -not ([IO.Path]::GetFullPath($location).TrimEnd('\') + '\').StartsWith(
            $allowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'P4_PR178_INSTALL_RUNNER_PATH_INVALID'
    }
}
if (-not $workspace.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'P4_PR178_INSTALL_WORKSPACE_INVALID'
}
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) {
    throw 'P4_PR178_INSTALL_ADB_MISSING'
}

function Assert-ViewerOffAndOwnerIdle {
    $task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction Stop
    if ([string]$task.State -cne 'Running') {
        throw 'P4_PR178_INSTALL_OWNER_NOT_RUNNING'
    }
    $spool = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics\owner-snapshot.json'
    if (-not (Test-Path -LiteralPath $spool -PathType Leaf)) {
        throw 'P4_PR178_INSTALL_OWNER_SNAPSHOT_MISSING'
    }
    $item = Get-Item -LiteralPath $spool -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $item.Length -le 0 -or $item.Length -gt 4096) {
        throw 'P4_PR178_INSTALL_OWNER_SNAPSHOT_INVALID'
    }
    $r = Get-Content -LiteralPath $spool -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
    $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$r.snapshot_utc_epoch
    if ($r.schema -cnotin @('TTV-HOSTOPS-OWNER-SNAPSHOT-V2',
                            'TTV-HOSTOPS-OWNER-SNAPSHOT-V3',
                            'TTV-HOSTOPS-OWNER-SNAPSHOT-V4') -or
        $r.status -cne 'READY_FRESH' -or
        $r.mode -cne 'INTEGRATED_P3_P4' -or
        $r.p3_state -cne 'FRESH_OFF' -or
        [string]$r.p2.status -cne 'CLEAR' -or
        [long]$r.p2.pending_events -ne 0 -or
        [long]$r.p2.inflight_count -ne 0 -or
        $age -lt 0 -or $age -gt 10) {
        throw 'P4_PR178_INSTALL_TV_OFF_OWNER_IDLE_NOT_PROVEN'
    }
}

$stage = Join-Path $env:RUNNER_WORKSPACE (
    '_omp-fast-cache\p4-flat-staged\' + $expectedCommit)
$stageInfo = Get-Item -LiteralPath $stage -Force -ErrorAction Stop
if (-not $stageInfo.PSIsContainer -or
    ($stageInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'P4_PR178_INSTALL_PRIVATE_STAGE_INVALID'
}
$apk = Join-Path $stage 'app-armeabi-v7a-debug.apk'
$receiptPath = Join-Path $stage 'stage-receipt.txt'
foreach ($path in @($apk, $receiptPath)) {
    $info = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if ($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'P4_PR178_INSTALL_STAGE_FILE_INVALID'
    }
}
$apkItem = Get-Item -LiteralPath $apk -Force -ErrorAction Stop
$receiptItem = Get-Item -LiteralPath $receiptPath -Force -ErrorAction Stop
if ($apkItem.Length -lt 5000000 -or $apkItem.Length -gt 600000000 -or
    $receiptItem.Length -le 0 -or $receiptItem.Length -gt 1024 -or
    (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkSha) {
    throw 'P4_PR178_INSTALL_APK_SHA_OR_SIZE_DRIFT'
}
$receipt = Get-Content -LiteralPath $receiptPath -Encoding ASCII
foreach ($required in @(
    'schema=TTV-P4-FLAT-APK-STAGE-V1',
    ('app_commit=' + $expectedCommit),
    'variant=app-armeabi-v7a-debug.apk',
    ('sha256=' + $expectedApkSha),
    'device_installed=no')) {
    if (@($receipt | Where-Object { $_ -ceq $required }).Count -ne 1) {
        throw 'P4_PR178_INSTALL_STAGE_RECEIPT_DRIFT'
    }
}
Assert-ViewerOffAndOwnerIdle

$buildTools = @(Get-ChildItem -LiteralPath 'C:\TOOL\Android-SDK\build-tools' -Directory |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
    } | Sort-Object Name -Descending)
if ($buildTools.Count -lt 1) { throw 'P4_PR178_INSTALL_BUILD_TOOLS_MISSING' }
$aapt = Join-Path $buildTools[0].FullName 'aapt.exe'
$apksigner = Join-Path $buildTools[0].FullName 'apksigner.bat'
if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    throw 'P4_PR178_INSTALL_ADB_NOT_RUNNING'
}
$devices = @(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'P4_PR178_INSTALL_ADB_DEVICES_FAILED' }
$authorized = @($devices | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$unexpected = @($devices | Where-Object { $_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)' })
if ($authorized.Count -ne 1 -or $unexpected.Count -gt 0) {
    throw 'P4_PR178_INSTALL_EXACT_ONE_AUTHORIZED_TV_REQUIRED'
}
$serial = ($authorized[0].Trim() -split '\s+')[0]
function Get-TvProp([string]$key) {
    $rows = @(& $adb -s $serial shell getprop $key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $rows.Count -ne 1) {
        throw 'P4_PR178_INSTALL_TV_PROP_UNAVAILABLE'
    }
    return [string]$rows[0].Trim()
}
if ((Get-TvProp 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (Get-TvProp 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (Get-TvProp 'ro.build.version.sdk') -cne '30') {
    throw 'P4_PR178_INSTALL_WRONG_TV_MODEL_ABI_API'
}
$paths = @(& $adb -s $serial shell pm path $pkg 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'P4_PR178_INSTALL_EXISTING_PACKAGE_UNAVAILABLE' }
$base = @($paths | Where-Object { $_ -match '^package:/[^\s]+/base\.apk$' })
if ($base.Count -ne 1) { throw 'P4_PR178_INSTALL_INSTALLED_BASE_NOT_UNIQUE' }
$remoteBase = $base[0].Trim().Substring(8)
$certParser = Join-Path $env:GITHUB_WORKSPACE 'poc\p4-auto-sub\cert-parser.ps1'
if (-not (Test-Path -LiteralPath $certParser -PathType Leaf)) {
    throw 'P4_PR178_INSTALL_CERT_PARSER_MISSING'
}
. $certParser

$verifyTemp = Join-Path $env:RUNNER_TEMP ('p4-pr178-install-' + $env:GITHUB_RUN_ID)
if (Test-Path -LiteralPath $verifyTemp) {
    throw 'P4_PR178_INSTALL_TEMP_ALREADY_EXISTS'
}
New-Item -ItemType Directory -Path $verifyTemp -ErrorAction Stop | Out-Null
try {
    function Invoke-QuietAdb([string[]]$subArgs) {
        $outFile = Join-Path $verifyTemp 'adb-out.txt'
        $errFile = Join-Path $verifyTemp 'adb-err.txt'
        try {
            $p = Start-Process -FilePath $adb -ArgumentList (@('-s', $serial) + $subArgs) `
                -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile `
                -RedirectStandardError $errFile -ErrorAction Stop
            $lines = if (Test-Path -LiteralPath $outFile -PathType Leaf) {
                @(Get-Content -LiteralPath $outFile)
            } else { @() }
            return @{ code = [int]$p.ExitCode; lines = @($lines) }
        } finally {
            foreach ($file in @($outFile, $errFile)) {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    $before = Join-Path $verifyTemp 'installed-before.apk'
    $pull = Invoke-QuietAdb @('pull', $remoteBase, $before)
    if ($pull.code -ne 0 -or -not (Test-Path -LiteralPath $before -PathType Leaf)) {
        throw 'P4_PR178_INSTALL_PREVIOUS_APK_READ_FAILED'
    }
    function PackageVersion([string]$file) {
        $badging = @(& $aapt dump badging $file 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'P4_PR178_INSTALL_BADGING_FAILED' }
        $packageLine = @($badging | Where-Object { $_ -match '^package: name=' })
        if ($packageLine.Count -ne 1 -or
            $packageLine[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
            throw 'P4_PR178_INSTALL_PACKAGE_VERSION_UNREADABLE'
        }
        return @{ package = $Matches[1]; version = [long]::Parse($Matches[2]) }
    }
    $old = PackageVersion $before
    $new = PackageVersion $apk
    if ($old.package -cne $pkg -or $new.package -cne $pkg -or
        $new.version -lt $old.version) {
        throw 'P4_PR178_INSTALL_PACKAGE_OR_DOWNGRADE_BLOCKED'
    }
    function Signer([string]$file) {
        $rows = @(& $apksigner verify --verbose --print-certs $file 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'P4_PR178_INSTALL_SIGNATURE_VERIFY_FAILED' }
        return [string](Get-P4SingleSignerDigest -Lines $rows)
    }
    $oldCert = Signer $before
    $newCert = Signer $apk
    if ($oldCert -cne $newCert -or $newCert -cne $expectedSigner) {
        throw 'P4_PR178_INSTALL_SIGNER_MISMATCH'
    }
    $oldSha = (Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($oldSha -ceq $expectedApkSha) {
        Write-Output 'P4_PR178_INSTALL=ALREADY_INSTALLED_VERIFIED_NO_CHANGE'
        return
    }
    if ($PreflightOnly) {
        Write-Output 'P4_PR178_PREFLIGHT=PASS_NO_TV_WRITE'
        Write-Output 'P4_PR178_PREFLIGHT_TARGET=REDMI_ARM32_DEBUG_VERIFIED'
        return
    }
    # Snapshot freshness and OFF can change during a slow ADB pull: recheck
    # immediately before the sole device write. This is NEVER a provider retry.
    Assert-ViewerOffAndOwnerIdle
    $install = Invoke-QuietAdb @('install', '-r', $apk)
    if ($install.code -ne 0 -or
        @($install.lines | Where-Object { ([string]$_).Trim() -ceq 'Success' }).Count -ne 1) {
        throw 'P4_PR178_INSTALL_ADB_REPLACE_FAILED_NO_RETRY'
    }
    $afterPaths = @(& $adb -s $serial shell pm path $pkg 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'P4_PR178_INSTALL_POST_PACKAGE_UNKNOWN' }
    $afterBase = @($afterPaths | Where-Object { $_ -match '^package:/[^\s]+/base\.apk$' })
    if ($afterBase.Count -ne 1) { throw 'P4_PR178_INSTALL_POST_BASE_UNKNOWN' }
    $after = Join-Path $verifyTemp 'installed-after.apk'
    $pulled = Invoke-QuietAdb @('pull', $afterBase[0].Trim().Substring(8), $after)
    if ($pulled.code -ne 0 -or -not (Test-Path -LiteralPath $after -PathType Leaf) -or
        (Get-FileHash -LiteralPath $after -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedApkSha) {
        throw 'P4_PR178_INSTALL_POST_READBACK_SHA_MISMATCH_NO_REINSTALL'
    }
    Write-Output 'P4_PR178_INSTALL=VERIFIED_EXACT_APK_DATA_PRESERVED'
    Write-Output ('P4_PR178_INSTALLED_SHA256=' + $expectedApkSha)
    Write-Output 'P4_PR178_REAL_SUBTITLE_RENDER=NOT_TESTED'
} finally {
    if (Test-Path -LiteralPath $verifyTemp -PathType Container) {
        Remove-Item -LiteralPath $verifyTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
