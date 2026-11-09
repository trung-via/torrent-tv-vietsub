# G4-B1 static-only readiness: parse candidate builder/audit/workflow, no signing.
# HostOps Issue #82 owner-only; dedicated Windows pinned branch and SHA.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:GITHUB_EVENT_NAME -cne 'issue_comment' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'G4B1_STATIC_STOP_WRONG_RUNNER_OR_EVENT'
}
$source = (Resolve-Path -LiteralPath $env:GITHUB_WORKSPACE).Path
$commit = (& git -C $source rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') {
    throw 'G4B1_STATIC_STOP_UNPINNED'
}
$dirty = @(& git -C $source status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) { throw 'G4B1_STATIC_STOP_DIRTY_CHECKOUT' }
$psPaths = @('poc\g4\release-v3-builder.ps1','poc\g4\audit-v3-apk.ps1','hostops\jobs\g4b1-static.ps1')
foreach ($relative in $psPaths) {
    $path = Join-Path $source $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'G4B1_STATIC_STOP_MISSING_PS_FILE' }
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$errors) | Out-Null
    if ($errors.Count -ne 0) { throw 'G4B1_STATIC_STOP_POWERSHELL_SYNTAX_ERROR' }
}
Write-Host 'G4B1_STATIC_POWERSHELL_SYNTAX_PASS'
$builder = Get-Content -LiteralPath (Join-Path $source 'poc\g4\release-v3-builder.ps1') -Raw
$binary = Get-Content -LiteralPath (Join-Path $source 'poc\g4\audit-v3-apk.ps1') -Raw
$yaml = Get-Content -LiteralPath (Join-Path $source '.github\workflows\g4-v3-signed-release-manual.yml') -Raw
foreach ($term in @(
    'G4B1_STOP_UNAPPROVED_RUNNER_WORKFLOW_OR_SOURCE',
    'G4B1_STOP_V3_TESTED_BLOB_DRIFT',
    'G4B1_BLOCKED_SIGNING_NOT_PROVISIONED',
    'G4B1_BLOCKED_RELEASE_SIGNER_NOT_APPROVED',
    'G4B1_STOP_UPSTREAM_OR_SIGNING_GUARD_DRIFT',
    'G4B1_COMPOSED_G1_P2_FONT_V3_SOURCE_PASS',
    'npm.cmd ci', 'testDebugUnitTest', 'assembleRelease',
    'G4B2_SIGNED_RELEASE_BINARY_VERIFIED_NOT_TV_PASS',
    'G4B1_PRIVATE_APK_AND_TEMP_SOURCE_CLEANUP_ATTEMPTED'
)) {
    if (-not $builder.Contains($term)) { throw 'G4B1_STATIC_STOP_BUILDER_REQUIRED_GUARD_MISSING' }
}
foreach ($term in @(
    'G4B2_STOP_APPROVED_SIGNER_NOT_ESTABLISHED',
    'G4B2_STOP_BAD_PACKAGE_OR_DEBUGGABLE',
    'G4B2_STOP_APKSIGNER_FAILED',
    'G4B2_STOP_DEBUG_FIXTURE_IN_RELEASE',
    'G4B2_STOP_G1_HELPER_NOT_IN_RELEASE_DEX',
    'G4B2_STOP_ARM32_ABI_ABSENT',
    'G4B2_RELEASE_BINARY_VERIFIED_NOT_TV_PASS'
)) {
    if (-not $binary.Contains($term)) { throw 'G4B1_STATIC_STOP_BINARY_REQUIRED_GUARD_MISSING' }
}
foreach ($term in @(
    'workflow_dispatch:',
    "github.actor == 'trung-via'",
    "github.ref == 'refs/heads/main'",
    'SIGN_G4_V3_RELEASE_ONCE',
    'persist-credentials: false',
    'TORRENTTV_RELEASE_KEYSTORE_FILE',
    'TORRENTTV_RELEASE_KEYSTORE_PASSWORD',
    'TORRENTTV_RELEASE_KEY_ALIAS',
    'TORRENTTV_RELEASE_KEY_PASSWORD',
    'TORRENTTV_RELEASE_CERT_SHA256'
)) {
    if (-not $yaml.Contains($term)) { throw 'G4B1_STATIC_STOP_WORKFLOW_GUARD_MISSING' }
}
if ($yaml.Contains('pull_request:') -or $yaml.Contains('pull_request_target:') -or
    $yaml.Contains('schedule:') -or $yaml.Contains('push:') -or
    $yaml.Contains('uses: actions/upload-artifact') -or
    $yaml.Contains('uses: softprops/action-gh-release')) {
    throw 'G4B1_STATIC_STOP_AUTOMATIC_OR_PUBLIC_RELEASE_ROUTE'
}
Write-Host 'G4B1_STATIC_OWNER_ONLY_MANUAL_SIGNING_GATES_PASS'
Write-Host 'G4B1_STATIC_BINARY_AUDIT_PRESENT_PASS'
Write-Host 'G4B1_STATIC_RELEASE_SIGNING_NOT_EXECUTED'
Write-Host 'G4B1_STATIC_NO_APK_BUILD_SIGN_UPLOAD_OR_TV_ACTION_PASS'
