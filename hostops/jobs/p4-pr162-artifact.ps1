# One-shot exact PR162 Debug artifact recovery into private runner cache.
# Source provenance and expected SHA from successful Android run 43612772368.
# No ADB, device install, network listener, API/provider or secret access.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows') {
    throw 'P4_PR162_ARTIFACT_WRONG_RUNNER'
}
$sourceSha='09c957da143b0255a1375d20d110badde6c68373'
$expectedSha='58abd59e97c10fb0586a67d1e049abe1adff5880b4ae8607572f1ac0c27c3657'
$trustedRoot='C:\TOOL\TorrentTV-Runner\_work'
$apk=Join-Path $trustedRoot '_temp\p1-g1-prod-43612772368-1\android\app\build\outputs\apk\debug\app-armeabi-v7a-debug.apk'
$evidence=Join-Path (Split-Path -Parent $apk) 'P4-COMPOSED-BUILD-EVIDENCE.txt'
Write-Host 'P4_PR162_ARTIFACT_RECOVERY=START'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf) -or
    -not (Test-Path -LiteralPath $evidence -PathType Leaf)) {
    Write-Host 'P4_PR162_ARTIFACT_RECOVERY=BUILD_TEMP_NOT_RETAINED'
    Write-Host 'P4_PR162_ARTIFACT_INSTALL=NOT_ATTEMPTED'
    exit 0
}
$receipt=Get-Content -LiteralPath $evidence -Raw -ErrorAction Stop
if (-not $receipt.Contains('app_commit='+$sourceSha) -or
    -not $receipt.Contains('runner=torrent-tv-vietsub-win') -or
    -not $receipt.Contains('signing=debug_variant_only') -or
    -not $receipt.Contains('source_set=feature/p3-p4-cross-lane-tv-owner-compose-20261114')) {
    throw 'P4_PR162_ARTIFACT_PROVENANCE_MISMATCH'
}
$actual=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -cne $expectedSha) {
    throw 'P4_PR162_ARTIFACT_SHA256_MISMATCH'
}
$cache=Join-Path $trustedRoot '_omp-fast-cache\p4-pr162-staged'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$target=Join-Path $cache 'app-armeabi-v7a-debug.apk'
if ((Test-Path -LiteralPath $target -PathType Leaf) -and
    ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedSha)) {
    throw 'P4_PR162_ARTIFACT_STAGED_CONFLICT'
}
Copy-Item -LiteralPath $apk -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedSha) {
    throw 'P4_PR162_ARTIFACT_COPY_VERIFY_FAILED'
}
Write-Host 'P4_PR162_ARTIFACT_RECOVERY=EXACT_SHA_STAGED_ON_OWNER_RUNNER'
Write-Host 'P4_PR162_ARTIFACT_SOURCE_SHA=09c957da143b0255a1375d20d110badde6c68373'
Write-Host 'P4_PR162_ARTIFACT_INSTALL=NOT_ATTEMPTED'
$global:LASTEXITCODE=0
