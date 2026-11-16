# PR #168 composed Android debug APK read-only preflight.
# Runs only through the source-pinned owner HostOps command on Torrent TV runner.
# Never installs, uninstalls, pairs, connects ADB, opens ports or changes TV state.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedSource = 'd93504bcd6941c078f230ae14fd4ba3d7988ec65'
$expectedApk = 'e548329835ed9a938e30f0c44270e718a623eaacb472c697fbd5665178e6536a'
$expectedSigner = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$sdk = 'C:\TOOL\Android-SDK'

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') {
    throw 'TTV_PREFLIGHT_UNTRUSTED_RUN_CONTEXT'
}

$allowed = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
$workspace = [IO.Path]::GetFullPath($env:RUNNER_WORKSPACE).TrimEnd('\') + '\'
if (-not $workspace.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'TTV_PREFLIGHT_UNEXPECTED_RUNNER_WORKSPACE'
}

$stage = Join-Path $env:RUNNER_WORKSPACE ("_omp-fast-cache\p4-pr168-staged\$expectedSource")
$apk = Join-Path $stage 'app-armeabi-v7a-debug.apk'
$receipt = Join-Path $stage 'stage-receipt.txt'
$apkProvenance = 'NOT_FOUND'

if ((Test-Path -LiteralPath $apk -PathType Leaf) -and
    (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    $actualHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $fields = Get-Content -LiteralPath $receipt -Raw | ConvertFrom-StringData
    $correct = ($actualHash -ceq $expectedApk -and
        $fields['schema'] -ceq 'TTV-P4-PR168-APK-STAGE-V1' -and
        $fields['app_commit'] -ceq $expectedSource -and
        $fields['sha256'] -ceq $actualHash -and
        $fields['variant'] -ceq 'app-armeabi-v7a-debug.apk' -and
        $fields['device_installed'] -ceq 'no')
    $apkProvenance = if ($correct) { 'PASS' } else { 'MISMATCH_HOLD' }
} elseif ((Test-Path -LiteralPath $apk) -or (Test-Path -LiteralPath $receipt)) {
    $apkProvenance = 'INCOMPLETE_HOLD'
}
Write-Host "TTV_APK_PROVENANCE=$apkProvenance"

$signature = 'NOT_RUN'
$package = 'NOT_RUN'
$nativeAbi = 'NOT_RUN'
if ($apkProvenance -ceq 'PASS') {
    $buildTools = @(Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)
    $signer = @($buildTools | ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    $aapt = @($buildTools | ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($signer.Count -gt 0) {
        try {
            $certOutput = @(& $signer[0] verify --print-certs $apk 2>&1 | ForEach-Object { $_.ToString() })
            $exit = $LASTEXITCODE
            $certMatch = [regex]::Match(($certOutput -join [Environment]::NewLine),
                'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)')
            $actualSigner = $certMatch.Groups[1].Value.Replace(':','').ToLowerInvariant()
            $signature = if ($exit -eq 0 -and $certMatch.Success -and
                $actualSigner -ceq $expectedSigner) { 'EXPECTED' } else { 'MISMATCH_HOLD' }
        } catch {
            $signature = 'UNAVAILABLE_HOLD'
        }
    } else {
        $signature = 'TOOL_NOT_FOUND'
    }
    if ($aapt.Count -gt 0) {
        try {
            $badging = @(& $aapt[0] dump badging $apk 2>&1 | ForEach-Object { $_.ToString() })
            $exit = $LASTEXITCODE
            $badgingText = $badging -join [Environment]::NewLine
            $package = if ($exit -eq 0 -and
                $badgingText -match "package:\s+name='com\.spacesarmat\.omp\.test'") {
                    'EXPECTED_TEST_PACKAGE'
                } else { 'UNVERIFIED_HOLD' }
            $nativeAbi = if ($badgingText -match "native-code:\s+'armeabi-v7a'") {
                'ARM32'
            } else { 'UNVERIFIED_HOLD' }
        } catch {
            $package = 'UNAVAILABLE_HOLD'
            $nativeAbi = 'UNAVAILABLE_HOLD'
        }
    } else {
        $package = 'TOOL_NOT_FOUND'
        $nativeAbi = 'TOOL_NOT_FOUND'
    }
}
Write-Host "TTV_APK_SIGNER=$signature"
Write-Host "TTV_APK_PACKAGE=$package"
Write-Host "TTV_APK_NATIVE_ABI=$nativeAbi"

# Do not auto-start ADB or acquire a new TV session. Inspect only an existing
# local server, and never print a serial, LAN address, package path or movie ID.
$adb = Join-Path $sdk 'platform-tools\adb.exe'
$adbState = 'NO_EXISTING_LOCAL_SERVER'
$arm32 = 'NOT_MEASURED'
$normal = 'NOT_MEASURED'
$test = 'NOT_MEASURED'
$authorizedCount = 'NOT_MEASURED'
if (Test-Path -LiteralPath $adb -PathType Leaf) {
    $listener = @(Get-NetTCPConnection -LocalPort 5037 -State Listen -ErrorAction SilentlyContinue)
    if ($listener.Count -gt 0) {
        try {
            $lines = @(& $adb devices 2>&1 | ForEach-Object { $_.ToString() })
            $devices = @($lines | Where-Object { $_ -match '^\S+\s+device\s*$' })
            $authorizedCount = [string]$devices.Count
            $adbState = 'EXISTING_SERVER_QUERIED'
            if ($devices.Count -eq 1) {
                $deviceId = ($devices[0] -split '\s+')[0]
                $abis = @(& $adb -s $deviceId shell getprop ro.product.cpu.abilist)
                $abiText = ($abis -join '').Trim()
                $arm32 = if ($abiText -match '(^|,)armeabi-v7a(,|$)') { 'YES' } else { 'NO' }
                $normalPath = @(& $adb -s $deviceId shell pm path com.spacesarmat.omp 2>&1)
                $testPath = @(& $adb -s $deviceId shell pm path com.spacesarmat.omp.test 2>&1)
                $normal = if ($normalPath -match '^package:') { 'YES' } else { 'NO' }
                $test = if ($testPath -match '^package:') { 'YES' } else { 'NO' }
            }
        } catch {
            $adbState = 'QUERY_FAILED_NO_CHANGE'
        }
    }
} else {
    $adbState = 'ADB_TOOL_NOT_FOUND'
}
Write-Host "TTV_ADB_STATE=$adbState"
Write-Host "TTV_ADB_AUTHORIZED_COUNT=$authorizedCount"
Write-Host "TTV_DEVICE_ARM32_COMPATIBLE=$arm32"
Write-Host "TTV_OMP_NORMAL_INSTALLED=$normal"
Write-Host "TTV_OMP_TEST_INSTALLED=$test"

# Read the existing test app's base APK for an exact signing and version
# comparison. No TV write, installation, pairing or APK content publication.
$signerMatch = 'NOT_MEASURED'
$versionGate = 'NOT_MEASURED'
$compareFailureStage = 'NONE'
$candidateVerify = 'NOT_RUN'
$installedVerify = 'NOT_RUN'
$candidateDigestState = 'NOT_RUN'
$installedDigestState = 'NOT_RUN'
$candidateCertLabels = 'NOT_RUN'
$installedCertLabels = 'NOT_RUN'

function Get-SafeCertLabels($output) {
    $labels = @($output | ForEach-Object {
        $line = ([string]$_).Trim()
        if ($line -match '(?i)(signer|certificate|sha-?256)' -and $line.Contains(':')) {
            $label = ($line -split ':', 2)[0].Trim()
            if ($label.Length -le 90 -and $label -cmatch '^[A-Za-z0-9# _\-]+$') {
                $label
            }
        }
    } | Select-Object -First 5)
    if ($labels.Count -eq 0) { return 'NONE' }
    return ($labels -join '|')
}
if ($apkProvenance -ceq 'PASS' -and
    $adbState -ceq 'EXISTING_SERVER_QUERIED' -and
    $authorizedCount -ceq '1' -and
    $test -ceq 'YES' -and
    $signer.Count -gt 0) {
    $baseEntries = @($testPath | Where-Object {
        [string]$_ -match '^package:/data/app/.+/base\.apk\s*$'
    })
    if ($baseEntries.Count -eq 1) {
        $remoteBase = ([string]$baseEntries[0]).Substring(8).Trim()
        $tempBase = Join-Path $env:RUNNER_TEMP ("ttv-pr168-existing-base-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT.apk")
        if (Test-Path -LiteralPath $tempBase) {
            throw 'TTV_COMPARE_TEMP_PATH_ALREADY_EXISTS'
        }
        $compareStage = 'ADB_PULL'
        try {
            # Windows PowerShell 5.1 can treat native stderr progress text as
            # terminating NativeCommandError when ErrorActionPreference=Stop.
            # ADB pull reports progress on stderr even when the copy succeeds.
            $savedPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                $pullOutput = @(& $adb -s $deviceId pull $remoteBase $tempBase 2>&1)
            } finally {
                $ErrorActionPreference = $savedPreference
            }
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $tempBase -PathType Leaf)) {
                $compareStage = 'VERIFY_CANDIDATE_CERT'
                $candidateOutput = @(& $signer[0] verify --print-certs $apk 2>&1)
                $candidateExit = $LASTEXITCODE
                $compareStage = 'VERIFY_INSTALLED_CERT'
                $installedOutput = @(& $signer[0] verify --print-certs $tempBase 2>&1)
                $installedExit = $LASTEXITCODE
                $pattern = 'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F:]+)'
                $candidateCert = [regex]::Match(($candidateOutput -join [Environment]::NewLine), $pattern)
                $installedCert = [regex]::Match(($installedOutput -join [Environment]::NewLine), $pattern)
                $candidateCertLabels = Get-SafeCertLabels $candidateOutput
                $installedCertLabels = Get-SafeCertLabels $installedOutput
                $candidateVerify = if ($candidateExit -eq 0) { 'PASS' } else { 'NONZERO_HOLD' }
                $installedVerify = if ($installedExit -eq 0) { 'PASS' } else { 'NONZERO_HOLD' }
                $candidateDigestState = if ($candidateCert.Success) { 'FOUND' } else { 'NOT_FOUND_HOLD' }
                $installedDigestState = if ($installedCert.Success) { 'FOUND' } else { 'NOT_FOUND_HOLD' }
                if ($candidateExit -eq 0 -and $installedExit -eq 0 -and
                    $candidateCert.Success -and $installedCert.Success) {
                    $candidateDigest = $candidateCert.Groups[1].Value.Replace(':','').ToLowerInvariant()
                    $installedDigest = $installedCert.Groups[1].Value.Replace(':','').ToLowerInvariant()
                    $signerMatch = if ($candidateDigest -ceq $installedDigest) { 'MATCH' } else { 'MISMATCH_HOLD' }
                } else {
                    $signerMatch = 'CERT_UNVERIFIED_HOLD'
                }
                if ($aapt.Count -gt 0) {
                    $compareStage = 'READ_CANDIDATE_VERSION'
                    $newBadge = @(& $aapt[0] dump badging $apk 2>&1)
                    $newExit = $LASTEXITCODE
                    $compareStage = 'READ_INSTALLED_VERSION'
                    $oldBadge = @(& $aapt[0] dump badging $tempBase 2>&1)
                    $oldExit = $LASTEXITCODE
                    $newText = $newBadge -join [Environment]::NewLine
                    $oldText = $oldBadge -join [Environment]::NewLine
                    $newCode = [regex]::Match($newText, "versionCode='([0-9]+)'")
                    $oldCode = [regex]::Match($oldText, "versionCode='([0-9]+)'")
                    $newPkg = $newText -match "package:\s+name='com\.spacesarmat\.omp\.test'"
                    $oldPkg = $oldText -match "package:\s+name='com\.spacesarmat\.omp\.test'"
                    if ($newExit -eq 0 -and $oldExit -eq 0 -and
                        $newCode.Success -and $oldCode.Success -and $newPkg -and $oldPkg) {
                        $versionGate = if ([long]$newCode.Groups[1].Value -ge [long]$oldCode.Groups[1].Value) {
                            'NO_DOWNGRADE'
                        } else { 'DOWNGRADE_HOLD' }
                    } else {
                        $versionGate = 'VERSION_OR_PACKAGE_UNVERIFIED_HOLD'
                    }
                }
            } else {
                $signerMatch = 'ADB_READ_FAILED_HOLD'
            }
        } catch {
            $signerMatch = 'READ_OR_VERIFY_FAILED_HOLD'
            $compareFailureStage = $compareStage
        } finally {
            # Also remove any partially copied APK after native-command failure.
            if (Test-Path -LiteralPath $tempBase -PathType Leaf) {
                Remove-Item -LiteralPath $tempBase -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        $signerMatch = 'BASE_APK_PATH_UNAVAILABLE_HOLD'
    }
}
Write-Host "TTV_EXISTING_TEST_SIGNER_MATCH=$signerMatch"
Write-Host "TTV_EXISTING_TEST_VERSION_GATE=$versionGate"
Write-Host "TTV_APK_COMPARE_FAILURE_STAGE=$compareFailureStage"
Write-Host "TTV_CANDIDATE_CERT_VERIFY=$candidateVerify"
Write-Host "TTV_INSTALLED_CERT_VERIFY=$installedVerify"
Write-Host "TTV_CANDIDATE_CERT_DIGEST=$candidateDigestState"
Write-Host "TTV_INSTALLED_CERT_DIGEST=$installedDigestState"
Write-Host "TTV_CANDIDATE_CERT_LABELS=$candidateCertLabels"
Write-Host "TTV_INSTALLED_CERT_LABELS=$installedCertLabels"
Write-Host 'TTV_PREFLIGHT=READ_ONLY_COMPLETE_NO_INSTALL'
