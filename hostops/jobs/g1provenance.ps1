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
    # Only compare in process; never log installed SHA, private paths, or APK bytes.
    Write-Host 'G1_VAULT_HASH_COMPARISON=READ_ONLY'
    $vault = 'C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2'
    if (-not (Test-Path -LiteralPath $vault -PathType Container)) {
        Write-Host 'G1_VAULT_STATUS=NOT_PRESENT'
    } elseif ((Get-Item -LiteralPath $vault -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Write-Host 'G1_VAULT_STATUS=REPARSE_DENIED'
    } else {
        try {
            $dirs = @(Get-ChildItem -LiteralPath $vault -Directory -ErrorAction Stop | Where-Object { $_.Name -cmatch '^run-[0-9]{6,15}-[0-9]{1,3}
    Write-Host 'G1_APKSHA_STATUS=READ_ONLY_HASH_OK'
} catch {
    # Do not print raw ADB failure: it may contain private paths or identifiers.
    Write-Host 'G1_APKSHA_STATUS=READ_FAILED'
}
Write-Host 'G1_APKSHA_NO_APK_TRANSFER=TRUE'
Write-Host 'G1_APKSHA_NO_TV_ACTUATION=TRUE'
Write-Host 'G1_APKSHA_PREFLIGHT_END'
exit 0
 })
            Write-Host ('G1_VAULT_CANDIDATE_DIRS=' + $dirs.Count)
            if ($dirs.Count -gt 80) {
                Write-Host 'G1_VAULT_STATUS=TOO_MANY_CANDIDATES'
            } else {
                $digestMatches = 0
                $verifiedMatches = @()
                foreach ($dir in $dirs) {
                    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                    $candidate = Join-Path $dir.FullName 'app-armeabi-v7a-debug.apk'
                    $item = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
                    if ($null -eq $item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                    if ($item.Length -lt 1024 -or $item.Length -gt 524288000) { continue }
                    $sha = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
                    if ($sha -cne $actual) { continue }
                    $digestMatches++
                    $manifest = Join-Path $dir.FullName 'SHA256SUMS-G1P2.txt'
                    $evidenceFile = Join-Path $dir.FullName 'G1P2-BUILD-EVIDENCE.txt'
                    $signerFile = Join-Path $dir.FullName 'SIGNATURE-STATUS.txt'
                    $boundFiles = @($manifest,$evidenceFile,$signerFile)
                    $validFiles = $true
                    foreach ($path in $boundFiles) {
                        $fi = Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
                        if ($null -eq $fi -or $fi.PSIsContainer -or ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $validFiles = $false; break }
                    }
                    if (-not $validFiles) { continue }
                    $manifestLines = @(Get-Content -LiteralPath $manifest -ErrorAction Stop)
                    if (@($manifestLines | Where-Object { $_ -ceq ($sha + '  app-armeabi-v7a-debug.apk') }).Count -ne 1) { continue }
                    if ($dir.Name -cnotmatch '^run-([0-9]{6,15})-([0-9]{1,3})
    Write-Host 'G1_APKSHA_STATUS=READ_ONLY_HASH_OK'
} catch {
    # Do not print raw ADB failure: it may contain private paths or identifiers.
    Write-Host 'G1_APKSHA_STATUS=READ_FAILED'
}
Write-Host 'G1_APKSHA_NO_APK_TRANSFER=TRUE'
Write-Host 'G1_APKSHA_NO_TV_ACTUATION=TRUE'
Write-Host 'G1_APKSHA_PREFLIGHT_END'
exit 0
) { continue }
                    $runId = $Matches[1]; $attempt = $Matches[2]
                    $evidence = @(Get-Content -LiteralPath $evidenceFile -ErrorAction Stop)
                    if (@($evidence | Where-Object { $_ -ceq ('run_id=' + $runId) }).Count -ne 1) { continue }
                    $commitLines = @($evidence | Where-Object { $_ -cmatch '^app_commit=[0-9a-f]{40}
    Write-Host 'G1_APKSHA_STATUS=READ_ONLY_HASH_OK'
} catch {
    # Do not print raw ADB failure: it may contain private paths or identifiers.
    Write-Host 'G1_APKSHA_STATUS=READ_FAILED'
}
Write-Host 'G1_APKSHA_NO_APK_TRANSFER=TRUE'
Write-Host 'G1_APKSHA_NO_TV_ACTUATION=TRUE'
Write-Host 'G1_APKSHA_PREFLIGHT_END'
exit 0
 })
                    if ($commitLines.Count -ne 1) { continue }
                    $commit = ([string]$commitLines[0]).Substring(11)
                    $status = (Get-Content -LiteralPath $signerFile -Raw -ErrorAction Stop).Trim()
                    if ($status -cnotin @('SIGNATURE_VERIFIED','SIGNATURE_HOLD_PENDING_VERIFY')) { continue }
                    $verifiedMatches += [PSCustomObject]@{Run=$runId;Attempt=$attempt;Commit=$commit;Signer=$status}
                }
                Write-Host ('G1_VAULT_DIGEST_MATCH_COUNT=' + $digestMatches)
                Write-Host ('G1_VAULT_PROVENANCE_MATCH_COUNT=' + $verifiedMatches.Count)
                if ($verifiedMatches.Count -eq 1) {
                    $v = $verifiedMatches[0]
                    Write-Host ('G1_VAULT_MATCH_RUN=' + $v.Run)
                    Write-Host ('G1_VAULT_MATCH_ATTEMPT=' + $v.Attempt)
                    Write-Host ('G1_VAULT_MATCH_SOURCE_COMMIT=' + $v.Commit)
                    Write-Host ('G1_VAULT_MATCH_SIGNER_STATUS=' + $v.Signer)
                    Write-Host 'G1_VAULT_STATUS=EXACT_SHA_AND_MANIFEST_PROVENANCE_MATCH'
                } elseif ($verifiedMatches.Count -gt 1) {
                    Write-Host 'G1_VAULT_STATUS=AMBIGUOUS_MULTIPLE_PROVENANCE_MATCHES'
                } elseif ($digestMatches -gt 0) {
                    Write-Host 'G1_VAULT_STATUS=HASH_MATCH_BUT_EVIDENCE_UNVERIFIED'
                } else {
                    Write-Host 'G1_VAULT_STATUS=NO_MATCH_IN_RETAINED_BUILDS'
                }
            }
        } catch {
            Write-Host 'G1_VAULT_STATUS=READ_FAILED_REDACTED'
        }
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
