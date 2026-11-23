# Exact source-only Windows verification for Brain EN staged release.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$files = @('hostops/jobs/owner-brain-stage-r3.ps1',
           'hostops/jobs/owner-brain-stage-r3-check.ps1')
foreach ($name in $files) {
    $file = Join-Path $root $name
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -ne 0) {
        throw 'OWNER_BRAIN_STAGE_POWERSHELL_PARSE_FAILED'
    }
}
$manifestFile = Join-Path $root 'hostops/releases/owner-brain-en-stage-r3.json'
$manifest = Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 |
    ConvertFrom-Json
if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
    $manifest.release_id -cne 'brain-en-182-r3-20261123' -or
    $manifest.source_tree -cne '76b890227324fc650d84f93b658c8873f9955297' -or
    $manifest.mode -cne 'STAGE_ONLY' -or
    @($manifest.files).Count -ne 16) {
    throw 'OWNER_BRAIN_STAGE_MANIFEST_INVALID'
}
$seen = @{}
foreach ($row in $manifest.files) {
    if ($row.path -cnotmatch '^poc/p2-sub-discovery/[a-z0-9_]+[.]py$' -or
        $row.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $seen.ContainsKey([string]$row.path)) {
        throw 'OWNER_BRAIN_STAGE_MANIFEST_ENTRY_INVALID'
    }
    $seen[[string]$row.path] = $true
    $f = Join-Path $root $row.path
    $body = [IO.File]::ReadAllText($f,[Text.UTF8Encoding]::new($false,$true))
    $normalized = $body -replace '\r\n', [string][char]10
    $raw = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
    $hash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData($raw)).ToLowerInvariant()
    if ($hash -cne $row.sha256) {
        throw 'OWNER_BRAIN_STAGE_SOURCE_HASH_MISMATCH'
    }
}
Write-Output 'OWNER_BRAIN_STAGE_SOURCE=PASS_PARSE_14_HASHES'
Write-Output 'OWNER_BRAIN_STAGE_OWNER=NOT_ACCESSED'
Write-Output 'OWNER_BRAIN_STAGE_PROVIDER_TV=NOT_RUN'
