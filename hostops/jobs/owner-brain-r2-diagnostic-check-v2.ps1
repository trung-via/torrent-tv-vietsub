# Windows read-only checker for exact Owner diagnostic operation and dispatcher.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$rel = @('hostops/jobs/owner-laptop-ops-dispatch.ps1',
         'hostops/laptop-ops/operations/owner-brain-r2-diagnostic.ps1',
         'hostops/jobs/owner-brain-r2-diagnostic-check-v2.ps1')
foreach ($p in $rel) {
    $full = Join-Path $env:GITHUB_WORKSPACE $p
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $full,[ref]$tokens,[ref]$errors)
    if (@($errors).Count -ne 0) { throw 'BRAIN_DIAG_PARSE_FAILED' }
}
$manifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'hostops/laptop-ops/manifests/current.json') -Raw | ConvertFrom-Json
if ($manifest.operation -cne 'owner-brain-r2-diagnostic' -or
    $manifest.script_path -cne 'hostops/laptop-ops/operations/owner-brain-r2-diagnostic.ps1') {
    throw 'BRAIN_DIAG_MANIFEST_INVALID'
}
$file = Join-Path $env:GITHUB_WORKSPACE $manifest.script_path
$body = [IO.File]::ReadAllText($file, [Text.UTF8Encoding]::new($false,$true))
$normalized = $body.Replace([string]([char]13)+[string]([char]10),[string][char]10)
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($normalized)
$hash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
if ($hash -cne $manifest.script_sha256) { throw 'BRAIN_DIAG_HASH_PIN_MISMATCH' }
Write-Output 'OWNER_BRAIN_R2_DIAG_SOURCE=PASS_PWSH_PARSE_SHA'
Write-Output 'OWNER_BRAIN_R2_DIAG_SOURCE_OWNER=NOT_ACCESSED'
