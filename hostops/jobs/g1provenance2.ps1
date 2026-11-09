# Read-only SHA256 attestation of the installed OMP test APK on authorized Redmi.
# No APK pull/transfer, install, sideload, shell write, media access, pairing or playback.
# No serial/IP/package path printed to public GitHub Actions logs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'G1_APKSHA_PREFLIGHT_BEGIN'
Write-Host 'G1_APKSHA_MEDIA_RENDER=NOT_RUN'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') { throw 'BLOCKED_RUNNER_IDENTITY' }
$adb = 'C:\TOOL\Android-SDK\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { Write-Host 'G1_APKSHA_STATUS=ADB_NOT_FOUND'; exit 0 }
try {
    $lines = @(& $adb devices -l 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB_LIST_FAILED' }
    $ids = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*(\S+)\s+device(?:\s|$)') { $ids += [string]$Matches[1] }
    }
    Write-Host ('G1_APKSHA_DEVICE_COUNT=' + $ids.Count)
    if ($ids.Count -ne 1) { Write-Host 'G1_APKSHA_STATUS=NO_UNAMBIGUOUS_DEVICE'; exit 0 }
    $serial = $ids[0]
    $m = @(& $adb -s $serial shell getprop ro.product.model 2>$null)
    if ($LASTEXITCODE -ne 0 -or @($m).Count -ne 1 -or ([string]$m[0]).Trim() -cne 'MiTV-ASTR0') {
        Write-Host 'G1_APKSHA_STATUS=UNEXPECTED_TV_MODEL'
        exit 0
    }
    $packages = @(& $adb -s $serial shell pm path com.spacesarmat.omp.test 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'PM_PATH_FAILED' }
    $paths = @()
    foreach ($line in $packages) {
        $q = ([string]$line).Trim()
        if ($q.StartsWith('package:')) { $paths += $q.Substring(8) }
    }
    Write-Host ('G1_APKSHA_PACKAGE_PATH_COUNT=' + $paths.Count)
    $bases = @($paths | Where-Object { $_ -match '^/[A-Za-z0-9_./+=~-]+/base\.apk$' })
    if ($bases.Count -ne 1) { Write-Host 'G1_APKSHA_STATUS=BASE_APK_PATH_UNVERIFIED'; exit 0 }
    $remotePath = [string]$bases[0]
    # Only a strictly sanitized package-manager-provided path is passed to adb shell.
    $output = @(& $adb -s $serial shell sha256sum $remotePath 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) {
        $output = @(& $adb -s $serial shell toybox sha256sum $remotePath 2>$null)
    }
    if ($LASTEXITCODE -ne 0 -or $output.Count -eq 0) { throw 'HASH_READ_FAILED' }
    $line = ([string]$output[0]).Trim()
    if ($line -notmatch '^([a-fA-F0-9]{64})\s+') { throw 'HASH_FORMAT_UNEXPECTED' }
    $actual = $Matches[1].ToLowerInvariant()
    $historical = 'c5a5bbd265e1353012165111d114b692b66ad783775eebdbc1408e1a668e82b6'
    Write-Host ('G1_APKSHA_MATCH_HISTORICAL_G1=' + ($actual -ceq $historical).ToString().ToUpperInvariant())
    $source4 = 'cd55d195741697509b294d8cc4176473c01ccfdba654b1a40408a001e85c7320'
    Write-Host ('G1_APKSHA_MATCH_REPORTED_G1P2_SOURCE4=' + ($actual -ceq $source4).ToString().ToUpperInvariant())

    # Compare on-device digest only with bounded, locally retained G1P2 APKs.
    # Neither digest, APK bytes, device identifiers nor local paths are printed.
    $vault = 'C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2'
    Write-Host 'G1_VAULT_PROBE=READ_ONLY'
    try {
        if (-not (Test-Path -LiteralPath $vault -PathType Container)) {
            Write-Host 'G1_VAULT_STATUS=VAULT_NOT_FOUND'
        } elseif ((Get-Item -LiteralPath $vault -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host 'G1_VAULT_STATUS=REPARSE_DENIED'
        } else {
            $dirs = @(Get-ChildItem -LiteralPath $vault -Directory -ErrorAction Stop |
                Where-Object { $_.Name -match '^run-[0-9]{6,15}-[0-9]{1,3}$' })
            Write-Host ('G1_VAULT_DIR_COUNT=' + $dirs.Count)
            if ($dirs.Count -gt 80) {
                Write-Host 'G1_VAULT_STATUS=BOUNDED_LIMIT_EXCEEDED'
            } else {
                $digestMatches = 0
                $verified = @()
                foreach ($dir in $dirs) {
                    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $apk = Join-Path $dir.FullName 'app-armeabi-v7a-debug.apk'
                    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { continue }
                    $item = Get-Item -LiteralPath $apk -ErrorAction Stop
                    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                        $item.Length -lt 1024 -or $item.Length -gt 524288000) { continue }
                    $candidateHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ($candidateHash -cne $actual) { continue }
                    $digestMatches++
                    $manifest = Join-Path $dir.FullName 'SHA256SUMS-G1P2.txt'
                    $evidencePath = Join-Path $dir.FullName 'G1P2-BUILD-EVIDENCE.txt'
                    $signerPath = Join-Path $dir.FullName 'SIGNATURE-STATUS.txt'
                    $metaFiles = @($manifest,$evidencePath,$signerPath)
                    $safe = $true
                    foreach ($p in $metaFiles) {
                        if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or
                            ((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                            $safe = $false
                            break
                        }
                    }
                    if (-not $safe) { continue }
                    $sumLines = @(Get-Content -LiteralPath $manifest)
                    $expectedLine = $actual + '  app-armeabi-v7a-debug.apk'
                    if (@($sumLines | Where-Object { $_ -ceq $expectedLine }).Count -ne 1) { continue }
                    if ($dir.Name -notmatch '^run-([0-9]{6,15})-([0-9]{1,3})$') { continue }
                    $runId = $Matches[1]
                    $attempt = $Matches[2]
                    $evidence = @(Get-Content -LiteralPath $evidencePath)
                    if (@($evidence | Where-Object { $_ -ceq ('run_id=' + $runId) }).Count -ne 1) { continue }
                    $commits = @($evidence | Where-Object { $_ -match '^app_commit=[0-9a-f]{40}$' })
                    if ($commits.Count -ne 1) { continue }
                    $sourceSha = ([string]$commits[0]).Substring(11)
                    $signer = (Get-Content -LiteralPath $signerPath -Raw).Trim()
                    if ($signer -notin @('SIGNATURE_VERIFIED','SIGNATURE_HOLD_PENDING_VERIFY')) { continue }
                    $verified += [PSCustomObject]@{ Run=$runId; Attempt=$attempt; Source=$sourceSha; Signer=$signer }
                }
                Write-Host ('G1_VAULT_DIGEST_MATCH_COUNT=' + $digestMatches)
                Write-Host ('G1_VAULT_VERIFIED_MATCH_COUNT=' + $verified.Count)
                if ($verified.Count -eq 1) {
                    $match = $verified[0]
                    Write-Host ('G1_VAULT_MATCH_RUN=' + $match.Run)
                    Write-Host ('G1_VAULT_MATCH_ATTEMPT=' + $match.Attempt)
                    Write-Host ('G1_VAULT_MATCH_COMMIT=' + $match.Source)
                    Write-Host ('G1_VAULT_MATCH_SIGNER_STATUS=' + $match.Signer)
                    Write-Host 'G1_VAULT_STATUS=EXACT_APK_BUILD_PROVENANCE_MATCH'
                } elseif ($verified.Count -gt 1) {
                    Write-Host 'G1_VAULT_STATUS=AMBIGUOUS_MULTIPLE_MATCHES'
                } elseif ($digestMatches -gt 0) {
                    Write-Host 'G1_VAULT_STATUS=HASH_MATCH_EVIDENCE_UNVERIFIED'
                } else {
                    Write-Host 'G1_VAULT_STATUS=NO_MATCH_IN_RETAINED_BUILDS'
                }
            }
        }
    } catch {
        Write-Host 'G1_VAULT_STATUS=READ_ERROR_REDACTED'
    }
    Write-Host 'G1_VAULT_NO_APK_TRANSFER_OR_UPLOAD=TRUE'
    Write-Host 'G1_APKSHA_HASH_OBSERVED=TRUE'
    Write-Host 'G1_APKSHA_STATUS=READ_ONLY_HASH_OK'
} catch {
    # Do not print raw ADB failure: it may contain private paths or identifiers.
    Write-Host 'G1_APKSHA_STATUS=READ_FAILED'
}
Write-Host 'G1_APKSHA_NO_APK_TRANSFER=TRUE'
Write-Host 'G1_APKSHA_NO_TV_ACTUATION=TRUE'
Write-Host 'G1_APKSHA_PREFLIGHT_END'
exit 0
