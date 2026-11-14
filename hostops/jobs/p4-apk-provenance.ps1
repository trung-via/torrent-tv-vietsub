# Torrent TV read-only installed APK provenance. No app state or device writes.
# Candidate public CI APK hashes are from PR #162 exact-head Android run 43596040589.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'P4_APK_PROVENANCE_WRONG_RUNNER'
}
$expected = @(
    '5ab10f5c583671bd05b1bc5fc2b560667039c1b036ff86e1fc3b77964647c54e',
    '58abd59e97c10fb0586a67d1e049abe1adff5880b4ae8607572f1ac0c27c3657',
    '1578b6e1e52936025880a67cbc79a8230a16635ab9a9087c214fd0a9f0df3444'
)
Write-Host 'P4_APK_PROVENANCE_SOURCE=PR162_F484818_ANDROID_CI_43596040589'
Write-Host 'P4_APK_PROVENANCE_SCOPE=READ_ONLY_ADB_SHELL_SHA256_NO_APK_BYTES'
$adbCandidates = @('C:\TOOL\Android-SDK\platform-tools\adb.exe',
                  'C:\TOOL\Android\Sdk\platform-tools\adb.exe')
$cmd = Get-Command adb.exe -ErrorAction SilentlyContinue
if ($null -ne $cmd) { $adbCandidates = @($cmd.Source) + $adbCandidates }
$adbPath = $null
foreach ($candidate in $adbCandidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $adbPath = $candidate
        break
    }
}
if ($null -eq $adbPath) {
    Write-Host 'P4_APK_PROVENANCE=BLOCKED_NO_ADB'
    exit 0
}
$rows = @(& $adbPath devices 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'P4_APK_PROVENANCE_ADB_DEVICES_FAILED' }
$connected = @($rows | Where-Object { $_ -match '^([^\s]+)\s+(device|unauthorized|offline)(\s|$)' })
$ready = @($connected | Where-Object { $_ -match '^([^\s]+)\s+device(\s|$)' })
if ($connected.Count -ne 1 -or $ready.Count -ne 1) {
    Write-Host 'P4_APK_PROVENANCE=BLOCKED_NO_UNIQUE_AUTHORIZED_ADB'
    exit 0
}
$serial = ([regex]::Match($ready[0], '^([^\s]+)\s+device(\s|$)')).Groups[1].Value
if ($serial -notmatch '^[A-Za-z0-9.:-]{1,128}$') {
    Write-Host 'P4_APK_PROVENANCE=BLOCKED_DEVICE_IDENTIFIER'
    exit 0
}
$package = 'com.spacesarmat.omp.test'
$paths = @(& $adbPath -s $serial shell pm path $package 2>$null)
if ($LASTEXITCODE -ne 0 -or $paths.Count -eq 0) {
    Write-Host 'P4_APK_PROVENANCE=BLOCKED_DEBUG_PACKAGE_NOT_FOUND'
    exit 0
}
$seen = 0
$matched = 0
$unreadable = 0
foreach ($row in $paths) {
    if ($row -notmatch '^package:(/data/app/[A-Za-z0-9./_+~=-]+\.apk)\s*$') {
        $unreadable++
        continue
    }
    $remotePath = $Matches[1]
    $seen++
    # ADB shell reads installed APK bytes but never writes, pulls or uploads them.
    $out = @(& $adbPath -s $serial shell sha256sum $remotePath 2>$null)
    $ok = $LASTEXITCODE -eq 0
    if (-not $ok -or $out.Count -lt 1) {
        $out = @(& $adbPath -s $serial shell toybox sha256sum $remotePath 2>$null)
        $ok = $LASTEXITCODE -eq 0
    }
    if (-not $ok -or $out.Count -lt 1) {
        $unreadable++
        continue
    }
    $match = [regex]::Match(($out -join ' '), '^([0-9a-fA-F]{64})\s+')
    if (-not $match.Success) {
        $unreadable++
        continue
    }
    if ($expected -contains $match.Groups[1].Value.ToLowerInvariant()) {
        $matched++
    }
}
Write-Host ('P4_APK_PARTS_FOUND=' + $paths.Count)
Write-Host ('P4_APK_PARTS_HASHED=' + ($seen - $unreadable))
Write-Host ('P4_APK_PARTS_MATCH_PR162_DEBUG_HASH=' + $matched)
if ($matched -ge 1) {
    Write-Host 'P4_APK_PROVENANCE=INSTALLED_BYTES_MATCH_PR162_DEBUG_ARTIFACT'
} elseif ($unreadable -gt 0) {
    Write-Host 'P4_APK_PROVENANCE=INCONCLUSIVE_HASH_UNAVAILABLE'
} else {
    Write-Host 'P4_APK_PROVENANCE=NO_PR162_DEBUG_ARTIFACT_HASH_MATCH'
}
Write-Host 'P4_APK_PROVENANCE_DONE_NO_TV_SUBTITLE_RENDER_PASS'
