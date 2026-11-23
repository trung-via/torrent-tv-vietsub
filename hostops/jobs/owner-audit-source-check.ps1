# Dedicated Windows source-only parse check. No Owner profile or task access.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = $env:GITHUB_WORKSPACE
$files = @(
    'hostops/jobs/owner-laptop-ops-dispatch.ps1',
    'hostops/laptop-ops/operations/owner-runtime-audit.ps1',
    'hostops/jobs/owner-audit-source-check.ps1'
)
foreach ($name in $files) {
    $file = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw 'OWNER_AUDIT_SOURCE_CHECK_MISSING_FILE'
    }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $file, [ref]$tokens, [ref]$parseErrors)
    if (@($parseErrors).Count -gt 0) {
        foreach ($problem in $parseErrors) {
            Write-Output ('OWNER_AUDIT_SOURCE_PARSE_ID=' + $problem.ErrorId)
        }
        throw 'OWNER_AUDIT_SOURCE_CHECK_POWERSHELL_PARSE_FAILED'
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $root 'hostops/laptop-ops/manifests/current.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.operation -cne 'owner-runtime-audit' -or
    $manifest.script_path -cne 'hostops/laptop-ops/operations/owner-runtime-audit.ps1' -or
    $manifest.script_sha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'OWNER_AUDIT_SOURCE_CHECK_MANIFEST_WRONG'
}
$source = Join-Path $root $manifest.script_path
$raw = [IO.File]::ReadAllText($source, [Text.UTF8Encoding]::new($false, $true))
$lf = $raw -replace '\r\n', [string][char]10
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($lf)
$hash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
if ($hash -cne $manifest.script_sha256) {
    throw 'OWNER_AUDIT_SOURCE_CHECK_MANIFEST_HASH_MISMATCH'
}
Write-Output 'OWNER_AUDIT_SOURCE_CHECK=PASS_PARSE_AND_PIN'
Write-Output 'OWNER_AUDIT_SOURCE_CHECK_OWNER=NOT_ACCESSED'
Write-Output 'OWNER_AUDIT_SOURCE_CHECK_TASK=NOT_TRIGGERED'
