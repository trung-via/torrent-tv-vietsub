# Signer-only repair of immutable G1+P2 Debug artifact already retained in private vault.
# No Gradle, APK download, APK upload, ADB, install, ACL mutation or release.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceCommit)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-Verify([string]$Reason) { throw ('G1P2_SIGNER_REVERIFY_HOLD: ' + $Reason) }
function BuildTool([string]$File) {
    $parent = 'C:\TOOL\Android-SDK\build-tools'
    $tools = @(Get-ChildItem -LiteralPath $parent -Directory -ErrorAction Stop |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName $File } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($tools.Count -ne 0) { return $tools[0] }
    Stop-Verify ('BUILD_TOOL_MISSING_' + $File)
}
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'push' -or
    $env:GITHUB_REF -cne 'refs/heads/main' -or
    $env:GITHUB_WORKFLOW_REF -cne 'trung-via/torrent-tv-vietsub/.github/workflows/tv-g1p2-auto-debug.yml@refs/heads/main' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:G1P2_AUTO_BRAIN_APPROVED -cne 'true' -or
    $env:G1P2_AUTO_SOURCE_SHA -cne $SourceCommit -or
    $env:GITHUB_SHA -cne $SourceCommit) {
    Stop-Verify 'TRUSTED_BRAIN_PASS_MAIN_JOB_REQUIRED'
}
if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { Stop-Verify 'INVALID_SOURCE_SHA' }
$runId = '42337102997'
$attempt = '1'
$originalCommit = 'c08d6e140cc6c8746444cc59169311b208cb2b23'
$expectedApkSha = 'c2f71cb8c8accc11821396d20a96490b0a129344cb329e1c5e6d9c3bf2f7b75f'
$expectedSigner = '8bf6937801524fd7c264b55855bb35a2133c242114fb66b5fa9f1907e334fd84'
$dir = 'C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2\run-42337102997-1'
if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Stop-Verify 'ORIGINAL_PRIVATE_APK_ABSENT' }
foreach ($item in @($dir, (Join-Path $dir 'app-armeabi-v7a-debug.apk'))) {
    if ((Get-Item -LiteralPath $item -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Stop-Verify 'REPARSE_POINT_DENIED'
    }
}
$apk = Join-Path $dir 'app-armeabi-v7a-debug.apk'
$shaFile = Join-Path $dir 'SHA256SUMS-G1P2.txt'
$evidenceFile = Join-Path $dir 'G1P2-BUILD-EVIDENCE.txt'
$statusFile = Join-Path $dir 'SIGNATURE-STATUS.txt'
foreach ($path in @($apk, $shaFile, $evidenceFile, $statusFile)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Verify 'ORIGINAL_EVIDENCE_INCOMPLETE' }
}
$actual = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -cne $expectedApkSha) { Stop-Verify 'ORIGINAL_APK_SHA_MISMATCH' }
$expectedManifestLine = "$expectedApkSha  app-armeabi-v7a-debug.apk"
if (@(Get-Content -LiteralPath $shaFile | Where-Object {
    $_ -ceq $expectedManifestLine
}).Count -ne 1) { Stop-Verify 'ORIGINAL_MANIFEST_MISMATCH' }
$evidence = @(Get-Content -LiteralPath $evidenceFile)
if (@($evidence | Where-Object { $_ -ceq "app_commit=$originalCommit" }).Count -ne 1 -or
    @($evidence | Where-Object { $_ -ceq "run_id=$runId" }).Count -ne 1) {
    Stop-Verify 'ORIGINAL_BUILD_PROVENANCE_MISMATCH'
}
$status = (Get-Content -LiteralPath $statusFile -Raw).Trim()
if ($status -cnotin @('SIGNATURE_HOLD_PENDING_VERIFY','SIGNATURE_VERIFIED')) {
    Stop-Verify 'UNKNOWN_QUARANTINE_STATUS'
}
$aapt = BuildTool 'aapt.exe'
$badging = @(& $aapt dump badging $apk 2>&1)
if ($LASTEXITCODE -ne 0 -or
    @($badging | Where-Object {
        "$_" -match "^package:\s+name='com\.spacesarmat\.omp\.test'"
    }).Count -ne 1) { Stop-Verify 'APK_PACKAGE_MISMATCH' }
$apksigner = BuildTool 'apksigner.bat'
$lines = @(& $apksigner verify --print-certs $apk 2>&1)
$exitCode = $LASTEXITCODE
. (Join-Path $PSScriptRoot 'apk-signer-digests.ps1')
$digests = @(Get-ApkSignerSha256Digests -OutputLines $lines)
Write-Host ('G1P2_REVERIFY_DIAGNOSTIC exit={0} cert_count={1} run={2}' -f
    $exitCode, $digests.Count, $runId)
if ($exitCode -ne 0 -or $digests.Count -ne 1 -or $digests[0] -cne $expectedSigner) {
    Stop-Verify 'SIGNATURE_INVALID_OR_UNEXPECTED_CERT_DO_NOT_INSTALL'
}
Set-Content -LiteralPath $statusFile -Value 'SIGNATURE_VERIFIED' -Encoding ascii
$readBack = (Get-Content -LiteralPath $statusFile -Raw).Trim()
if ($readBack -cne 'SIGNATURE_VERIFIED') { Stop-Verify 'STATUS_READBACK_FAILED' }
Write-Host ('G1P2_RETAINED_APK_CERT_VERIFIED_NO_REBUILD run={0} sha256={1} cert_sha256={2}' -f
    $runId, $actual, $digests[0])
Write-Host 'NO_ADB_INSTALL_OR_TV_MODIFICATION'
