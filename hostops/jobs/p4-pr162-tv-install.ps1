# Exact PR #162 one-shot OMP Debug upgrade. Derived from repo's prior
# one-shot signer/version/data-preserving installer; never install release.
# Owner HostOps issue comment is an explicit request, not PR push/retry.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo='trung-via/torrent-tv-vietsub'
$SourceCommit='d07cf6b6216a7e71eb9f57f2c167bcb9a48eda04'
$AppRepoRoot=$env:GITHUB_WORKSPACE
$CertDiagnosticOnly=$false
$runnerRoot='C:\TOOL\TorrentTV-Runner\_work'
$pkg='com.spacesarmat.omp.test'
$adb='C:\TOOL\Android-SDK\platform-tools\adb.exe'
$sdkBuildTools='C:\TOOL\Android-SDK\build-tools'
$expectedDebugCert='8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:GITHUB_REPOSITORY -cne $repo -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    [string]::IsNullOrWhiteSpace($env:HOSTOPS_GITHUB_TOKEN) -or
    -not $env:GITHUB_WORKFLOW_REF.StartsWith(
        ($repo+'/.github/workflows/torrent-tv-hostops.yml@'),
        [StringComparison]::Ordinal) -or
    $env:HOSTOPS_REQUEST -notmatch '^/tv-hostops run ([0-9a-f]{40}) p4-pr162-tv-install$') {
    throw 'P4_PR162_INSTALL_UNTRUSTED_OWNER_DISPATCH'
}
$approvedJobSha=$Matches[1]
$headers=@{
    Authorization="Bearer $env:HOSTOPS_GITHUB_TOKEN"
    Accept='application/vnd.github+json'
    'User-Agent'='torrent-tv-p4-one-shot'
    'X-GitHub-Api-Version'='2022-11-28'
}
$pr=Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repo/pulls/162" -Headers $headers
if ($pr.state -cne 'open' -or -not $pr.draft -or
    $pr.head.repo.full_name -cne $repo -or
    $pr.head.ref -cne 'feature/p3-p4-cross-lane-tv-owner-compose-20261114' -or
    $pr.head.sha -cne $SourceCommit -or $pr.base.ref -cne 'main') {
    throw 'P4_PR162_INSTALL_CANDIDATE_PR_DRIFT'
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
if ($LASTEXITCODE -ne 0 -or $head -cne $approvedJobSha) {throw 'P4_INSTALL_STOP_APPROVED_HOSTOPS_CHECKOUT_DRIFT'}
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
$stage=Join-Path $env:RUNNER_WORKSPACE ('_omp-fast-cache\p4-pr162-staged\'+$SourceCommit)
$apk=Join-Path $stage 'app-armeabi-v7a-debug.apk'
$stageReceipt=Join-Path $stage 'stage-receipt.txt'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf) -or
    -not (Test-Path -LiteralPath $stageReceipt -PathType Leaf)) {
    throw 'P4_INSTALL_STOP_NO_EXACT_PR162_STAGED_APK'
}
$receipt=@(Get-Content -LiteralPath $stageReceipt -ErrorAction Stop)
if ('schema=TTV-P4-PR162-APK-STAGE-V1' -cnotin $receipt -or
    ('app_commit='+$SourceCommit) -cnotin $receipt -or
    'variant=app-armeabi-v7a-debug.apk' -cnotin $receipt) {
    throw 'P4_INSTALL_STOP_STAGED_APK_PROVENANCE_INVALID'
}
$stageSha=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if (('sha256='+$stageSha) -cnotin $receipt) {
    throw 'P4_INSTALL_STOP_STAGED_APK_SHA_INVALID'
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
    # Windows PowerShell 5.1 turns native stderr (including SUCCESSFUL adb
    # progress output) into NativeCommandError when ErrorActionPreference=Stop.
    # Capture both streams privately and decide success by native exit code.
    function Invoke-QuietAdb([string[]]$subArgs) {
        $outFile=Join-Path $verifyTemp 'adb-private-stdout.txt'
        $errFile=Join-Path $verifyTemp 'adb-private-stderr.txt'
        try {
            $proc=Start-Process -FilePath $adb -ArgumentList (@('-s',$serial)+$subArgs) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile -ErrorAction Stop
            $lines=if (Test-Path -LiteralPath $outFile -PathType Leaf) {
                @(Get-Content -LiteralPath $outFile -ErrorAction Stop)
            } else { @() }
            return @{ code=[int]$proc.ExitCode; lines=@($lines) }
        } finally {
            foreach ($file in @($outFile,$errFile)) {
                if (Test-Path -LiteralPath $file) {
                    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    $oldApk=Join-Path $verifyTemp 'installed-before.apk'
    $pullResult=Invoke-QuietAdb @('pull',$remoteBase,$oldApk)
    if ($pullResult.code -ne 0 -or -not (Test-Path -LiteralPath $oldApk -PathType Leaf)) {
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
    # Parser is pure, source-pinned and unit-tested before the Android build.
    $parserPath=Join-Path $AppRepoRoot 'poc\p4-auto-sub\cert-parser.ps1'
    if (-not (Test-Path -LiteralPath $parserPath -PathType Leaf)) {
        throw 'P4_INSTALL_STOP_SIGNER_PARSER_MISSING'
    }
    . $parserPath
    function Get-VerifiedCert([string]$apkFile, [string]$label) {
        $out=@(& $apksigner verify --verbose --print-certs $apkFile 2>$null)
        if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_APK_SIGNATURE_VERIFY_FAILED'}
        $result=Get-P4SingleSignerDigest -Lines $out
        # Do NOT log certificate fingerprints or signer raw text.
        Write-Host ('P4_SIGNER_'+$label+'_SINGLE_CERT_PARSED=true')
        return [string]$result
    }
    $current=Get-PackageAndVersion $oldApk
    $new=Get-PackageAndVersion $apk
    if ($current.package -cne $pkg -or $new.package -cne $pkg) {
        throw 'P4_INSTALL_STOP_DEBUG_PACKAGE_MISMATCH'
    }
    if ($new.version -lt $current.version) {throw 'P4_INSTALL_STOP_DOWNGRADE_BLOCKED'}
    Write-Host 'P4_INSTALL_PACKAGE_AND_VERSION_GUARD_PASS'
    $oldCert=Get-VerifiedCert $oldApk 'INSTALLED'
    $newCert=Get-VerifiedCert $apk 'CANDIDATE'
    if ($CertDiagnosticOnly) {
        Write-Host ('P4_SIGNER_DIAG_BOTH_PARSED=' + [bool]($oldCert -and $newCert))
        Write-Host ('P4_SIGNER_DIAG_INSTALLED_EQUALS_CANDIDATE=' + [bool]($oldCert -and $newCert -and ($oldCert -ceq $newCert)))
        Write-Host ('P4_SIGNER_DIAG_CANDIDATE_EQUALS_PIN=' + [bool]($newCert -and ($newCert -ceq $expectedDebugCert)))
        Write-Host 'P4_SIGNER_DIAGNOSTIC_READONLY_COMPLETE_NO_INSTALL'
        return
    }
    if ($oldCert -cne $newCert -or $newCert -cne $expectedDebugCert) {
        throw 'P4_INSTALL_STOP_SIGNATURE_MISMATCH_KEEP_EXISTING_APP'
    }
    Write-Host 'P4_INSTALL_SIGNATURE_MATCH_PASS_NO_UNINSTALL'
    $expectedApkHash=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-Host ('P4_INSTALL_EXPECTED_ARM32_SHA256='+$expectedApkHash)

    # Sole TV write: install -r preserves data. No -d, uninstall, clear, reboot.
    $installResult=Invoke-QuietAdb @('install','-r',$apk)
    if ($installResult.code -ne 0 -or
        @($installResult.lines | Where-Object { ([string]$_).Trim() -eq 'Success' }).Count -ne 1) {
        throw 'P4_INSTALL_STOP_ADB_REPLACE_FAILED_NO_RECOVERY_MUTATION'
    }
    Write-Host 'P4_INSTALL_ADB_REPLACE_SUCCESS_DATA_PRESERVED_BY_REPLACE_FLAG'

    $afterPaths=@(& $adb -s $serial shell pm path $pkg 2>$null)
    if ($LASTEXITCODE -ne 0) {throw 'P4_INSTALL_STOP_POST_PACKAGE_READ_FAILED'}
    $afterBases=@($afterPaths | Where-Object { $_.Trim() -match '^package:/[^ \t\r\n]+/base\.apk$' })
    if ($afterBases.Count -ne 1) {throw 'P4_INSTALL_STOP_POST_BASE_APK_UNKNOWN'}
    $remoteAfter=([string]$afterBases[0]).Trim().Substring(8)
    $afterLocal=Join-Path $verifyTemp 'installed-after.apk'
    $postPullResult=Invoke-QuietAdb @('pull',$remoteAfter,$afterLocal)
    if ($postPullResult.code -ne 0 -or -not (Test-Path -LiteralPath $afterLocal -PathType Leaf)) {
        throw 'P4_INSTALL_STOP_POST_APK_READ_FAILED'
    }
    $observedHash=(Get-FileHash -LiteralPath $afterLocal -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($observedHash -cne $expectedApkHash) {
        throw 'P4_INSTALL_STOP_POST_APK_HASH_MISMATCH_NO_EXTRA_INSTALL'
    }
    Write-Host 'P4_INSTALL_VERIFIED_EXACT_APK_HASH=true'
    Write-Host 'P4_PR162_TV_DEBUG_REPLACEMENT_EXACT_SHA_PASS_NO_DATA_CLEAR_NOT_LAN_E2E'
} finally {
    if (Test-Path -LiteralPath $verifyTemp) {
        Remove-Item -LiteralPath $verifyTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$global:LASTEXITCODE=0
