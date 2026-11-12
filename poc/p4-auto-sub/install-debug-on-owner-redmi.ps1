# Owner-approved one-shot P4 Debug upgrade for installed OMP Debug.
# Never uninstall, clear data, downgrade, restart TV or start a LAN service.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$AppRepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceCommit
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo='trung-via/torrent-tv-vietsub'
$branch='feature/p4-native-auto-sub-g2-20261111'
$workflow='.github/workflows/tv-p4-owner-redmi-debug-install.yml'
$runnerRoot='C:\TOOL\TorrentTV-Runner\_work'
$pkg='com.spacesarmat.omp.test'
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$sdkBuildTools='C:\TOOL\Android-SDK\build-tools'
$expectedDebugCert='8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_HEAD_REF -cne $branch -or
    $env:GITHUB_BASE_REF -cne 'feature/g2-refresh-vietsub-inplace-20261111' -or
    $env:GITHUB_REF -cne 'refs/pull/120/merge' -or
    -not $env:GITHUB_WORKFLOW_REF.StartsWith(($repo+'/'+$workflow+'@'),[StringComparison]::Ordinal)) {
    throw 'P4_INSTALL_STOP_OWNER_RUNNER_WORKFLOW_IDENTITY'
}
if ($SourceCommit -notmatch '^[a-f0-9]{40}$' -or
    -not $env:GITHUB_EVENT_PATH -or
    -not (Test-Path -LiteralPath $env:GITHUB_EVENT_PATH -PathType Leaf)) {
    throw 'P4_INSTALL_STOP_SOURCE_OR_EVENT_INVALID'
}
$eventData=Get-Content -LiteralPath $env:GITHUB_EVENT_PATH -Raw | ConvertFrom-Json
if ($eventData.repository.full_name -cne $repo -or
    [int]$eventData.number -ne 120 -or
    $eventData.pull_request.user.login -cne 'trung-via' -or
    $eventData.pull_request.head.repo.full_name -cne $repo -or
    $eventData.pull_request.head.ref -cne $branch -or
    $eventData.pull_request.head.sha -cne $SourceCommit -or
    $eventData.pull_request.base.ref -cne 'feature/g2-refresh-vietsub-inplace-20261111' -or
    $eventData.action -notin @('opened','synchronize','reopened')) {
    throw 'P4_INSTALL_STOP_PR_IDENTITY_DRIFT'
}
foreach ($k in @('RUNNER_TEMP','RUNNER_WORKSPACE','GITHUB_WORKSPACE','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT')) {
    if (-not [Environment]::GetEnvironmentVariable($k)) {throw 'P4_INSTALL_STOP_RUNNER_ENV_INVALID'}
}
$allowed=[IO.Path]::GetFullPath($runnerRoot).TrimEnd('\')+'\'
foreach ($p in @($env:RUNNER_TEMP,$env:RUNNER_WORKSPACE,$env:GITHUB_WORKSPACE)) {
    if (-not ([IO.Path]::GetFullPath($p).TrimEnd('\')+'\').StartsWith(
        $allowed,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'P4_INSTALL_STOP_OUTSIDE_DEDICATED_RUNNER'
    }
}
$AppRepoRoot=(Resolve-Path -LiteralPath $AppRepoRoot).Path
$head=(& git -C $AppRepoRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $head -cne $SourceCommit) {throw 'P4_INSTALL_STOP_CHECKOUT_DRIFT'}
# The composed builder runs Python unit tests from the source workspace and
# generates harmless, untracked .pyc files. Reject ALL tracked modifications and
# every untracked path except the exact ephemeral Python cache shape.
$modified=@(& git -C $AppRepoRoot diff --name-only HEAD --)
if ($LASTEXITCODE -ne 0 -or $modified.Count -ne 0) {
    throw 'P4_INSTALL_STOP_TRACKED_SOURCE_MODIFIED'
}
$untracked=@(& git -C $AppRepoRoot ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_WORKTREE_INSPECTION_FAILED'}
foreach ($file in $untracked) {
    $normalized=([string]$file).Replace('\','/')
    if ($normalized -notmatch '^poc/(g2-refresh|p4-auto-sub)/__pycache__/[A-Za-z0-9_.-]+\.pyc\z') {
        throw 'P4_INSTALL_STOP_UNEXPECTED_UNTRACKED_WORKTREE_CONTENT'
    }
}
Write-Host 'P4_INSTALL_TRACKED_SOURCE_CLEAN_EPHEMERAL_PYC_ONLY'
$apk=Join-Path $env:RUNNER_TEMP (
    'p1-g1-prod-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT+
    '\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk')
if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) {
    throw 'P4_INSTALL_STOP_NO_SAME_RUN_ARM32_APK'
}
$apkInfo=Get-Item -LiteralPath $apk
if ($apkInfo.Length -lt 5000000 -or $apkInfo.Length -gt 600000000) {
    throw 'P4_INSTALL_STOP_UNEXPECTED_APK_SIZE'
}
if (-not (Test-Path -LiteralPath $adb -PathType Leaf) -or
    -not (Test-Path -LiteralPath $sdkBuildTools -PathType Container)) {
    throw 'P4_INSTALL_STOP_ANDROID_TOOLS_MISSING'
}
$buildTools=@(Get-ChildItem -LiteralPath $sdkBuildTools -Directory |
    Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') -PathType Leaf)
    } | Sort-Object Name -Descending)
if ($buildTools.Count -lt 1) {throw 'P4_INSTALL_STOP_APK_VERIFY_TOOLS_MISSING'}
$aapt=Join-Path $buildTools[0].FullName 'aapt.exe'
$apksigner=Join-Path $buildTools[0].FullName 'apksigner.bat'

if (@(Get-Process -Name adb -ErrorAction SilentlyContinue).Count -eq 0) {
    throw 'P4_INSTALL_STOP_ADB_SERVER_NOT_RUNNING'
}
$all=@(& $adb devices 2>$null)
if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_ADB_DEVICES_FAILED'}
$authorized=@($all | Where-Object { $_ -match '^[^\s]+\s+device(\s|$)' })
$unexpected=@($all | Where-Object { $_ -match '^[^\s]+\s+(unauthorized|offline)(\s|$)' })
if ($authorized.Count -ne 1 -or $unexpected.Count -ne 0) {
    throw 'P4_INSTALL_STOP_REQUIRE_SINGLE_AUTHORIZED_TV'
}
$serial=($authorized[0].Trim() -split '\s+')[0]
function Get-TvProp([string]$key) {
    $values=@(& $adb -s $serial shell getprop $key 2>$null)
    if ($LASTEXITCODE -ne 0 -or $values.Count -ne 1) {
        throw 'P4_INSTALL_STOP_DEVICE_PROPERTIES_UNAVAILABLE'
    }
    return ([string]$values[0]).Trim()
}
if ((Get-TvProp 'ro.product.model') -cne 'MiTV-ASTR0' -or
    (Get-TvProp 'ro.product.cpu.abi') -cne 'armeabi-v7a' -or
    (Get-TvProp 'ro.build.version.sdk') -cne '30') {
    throw 'P4_INSTALL_STOP_TV_MODEL_API_OR_ABI_CHANGED'
}
Write-Host 'P4_INSTALL_TV_MODEL_ABI_API_MATCH=true'

# Pull only the APK code package, NEVER TV application data.
$paths=@(& $adb -s $serial shell pm path $pkg 2>$null)
if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_EXISTING_DEBUG_PACKAGE_MISSING'}
$basePaths=@($paths | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
if ($basePaths.Count -ne 1) {throw 'P4_INSTALL_STOP_EXPECTED_EXISTING_DEBUG_BASE_APK'}
$remoteBase=([string]$basePaths[0]).Trim().Substring(8)
$verifyTemp=Join-Path $env:RUNNER_TEMP (
    'p4-owner-apk-verify-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT)
if (Test-Path -LiteralPath $verifyTemp) {throw 'P4_INSTALL_STOP_VERIFY_TEMP_ALREADY_EXISTS'}
New-Item -ItemType Directory -Path $verifyTemp -ErrorAction Stop | Out-Null
try {
    $oldApk=Join-Path $verifyTemp 'installed-before.apk'
    $pullOutput=@(& $adb -s $serial pull $remoteBase $oldApk 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $oldApk -PathType Leaf)) {
        throw 'P4_INSTALL_STOP_CANNOT_READ_INSTALLED_DEBUG_APK'
    }
    function Get-PackageAndVersion([string]$apkFile) {
        $badge=@(& $aapt dump badging $apkFile 2>$null)
        if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_AAPT_BADGING_FAILED'}
        $pLine=@($badge | Where-Object { $_ -match '^package: name=' })
        if ($pLine.Count -ne 1 -or $pLine[0] -notmatch "name='([^']+)' versionCode='([0-9]+)'") {
            throw 'P4_INSTALL_STOP_APK_IDENTITY_UNREADABLE'
        }
        return @{ package=$Matches[1]; version=[long]::Parse($Matches[2]) }
    }
    function Get-VerifiedCert([string]$apkFile) {
        $out=@(& $apksigner verify --verbose --print-certs $apkFile 2>$null)
        if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_APK_SIGNATURE_VERIFY_FAILED'}
        $certDigests=@($out | ForEach-Object {
            if ($_ -match 'Signer #1 certificate SHA-256 digest:\s*([a-fA-F0-9]{64})') {
                $Matches[1].ToLowerInvariant()
            }
        })
        if ($certDigests.Count -ne 1) {throw 'P4_INSTALL_STOP_APK_SIGNER_COUNT_INVALID'}
        return [string]$certDigests[0]
    }
    $current=Get-PackageAndVersion $oldApk
    $new=Get-PackageAndVersion $apk
    if ($current.package -cne $pkg -or $new.package -cne $pkg) {
        throw 'P4_INSTALL_STOP_DEBUG_PACKAGE_MISMATCH'
    }
    if ($new.version -lt $current.version) {throw 'P4_INSTALL_STOP_DOWNGRADE_BLOCKED'}
    Write-Host 'P4_INSTALL_PACKAGE_AND_VERSION_GUARD_PASS'
    $oldCert=Get-VerifiedCert $oldApk
    $newCert=Get-VerifiedCert $apk
    if ($oldCert -cne $newCert -or $newCert -cne $expectedDebugCert) {
        throw 'P4_INSTALL_STOP_SIGNATURE_MISMATCH_KEEP_EXISTING_APP'
    }
    Write-Host 'P4_INSTALL_SIGNATURE_MATCH_PASS_NO_UNINSTALL'
    $expectedApkHash=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host ('P4_INSTALL_EXPECTED_ARM32_SHA256='+$expectedApkHash)

    # Sole TV write: install -r preserves data. No -d, uninstall, clear, reboot.
    $installResult=@(& $adb -s $serial install -r $apk 2>&1)
    if ($LASTEXITCODE -ne 0 -or
        @($installResult | Where-Object { ([string]$_).Trim() -eq 'Success' }).Count -ne 1) {
        throw 'P4_INSTALL_STOP_ADB_REPLACE_FAILED_NO_RECOVERY_MUTATION'
    }
    Write-Host 'P4_INSTALL_ADB_REPLACE_SUCCESS_DATA_PRESERVED_BY_REPLACE_FLAG'

    $afterPaths=@(& $adb -s $serial shell pm path $pkg 2>$null)
    if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_POST_PACKAGE_READ_FAILED'}
    $afterBases=@($afterPaths | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($afterBases.Count -ne 1) {throw 'P4_INSTALL_STOP_POST_BASE_APK_UNKNOWN'}
    $remoteAfter=([string]$afterBases[0]).Trim().Substring(8)
    $afterLocal=Join-Path $verifyTemp 'installed-after.apk'
    $ignored=@(& $adb -s $serial pull $remoteAfter $afterLocal 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $afterLocal -PathType Leaf)) {
        throw 'P4_INSTALL_STOP_POST_APK_READ_FAILED'
    }
    $observedHash=(Get-FileHash -LiteralPath $afterLocal -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($observedHash -cne $expectedApkHash) {
        throw 'P4_INSTALL_STOP_POST_APK_HASH_MISMATCH_NO_EXTRA_INSTALL'
    }
    Write-Host 'P4_INSTALL_VERIFIED_EXACT_APK_HASH=true'
    Write-Host 'P4_INSTALL_DEBUG_ARM32_PASS_NOT_LAN_OR_SUBTITLE_E2E'
} finally {
    if (Test-Path -LiteralPath $verifyTemp) {
        Remove-Item -LiteralPath $verifyTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$global:LASTEXITCODE=0
