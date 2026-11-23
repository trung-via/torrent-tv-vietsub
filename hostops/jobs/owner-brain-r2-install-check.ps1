# Windows source-only preflight for Owner Brain R2 transaction; no task or provider.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$files = @(
    'hostops/jobs/owner-laptop-ops-dispatch.ps1',
    'hostops/laptop-ops/operations/owner-brain-r2-install.ps1',
    'hostops/jobs/owner-brain-r2-install-check.ps1'
)
foreach ($rel in $files) {
    $path = Join-Path $env:GITHUB_WORKSPACE $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'OWNER_BRAIN_R2_SOURCE_MISSING'
    }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        foreach ($problem in $parseErrors) {
            Write-Output ('OWNER_BRAIN_R2_PARSE_ERROR_ID=' + $problem.ErrorId)
        }
        throw 'OWNER_BRAIN_R2_SOURCE_POWERSHELL_PARSE_FAILED'
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'hostops/laptop-ops/manifests/current.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.operation -cne 'owner-brain-r2-install' -or
    $manifest.risk -cne 'ROUTINE' -or
    $manifest.category -cne 'owner-maintenance' -or
    $manifest.script_path -cne 'hostops/laptop-ops/operations/owner-brain-r2-install.ps1') {
    throw 'OWNER_BRAIN_R2_SOURCE_MANIFEST_WRONG'
}
$operation = Join-Path $env:GITHUB_WORKSPACE $manifest.script_path
$text = [IO.File]::ReadAllText($operation,[Text.UTF8Encoding]::new($false,$true))
$lf = $text.Replace([string]([char]13)+[string]([char]10),[string][char]10)
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($lf)
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
if ($hash -cne $manifest.script_sha256) {
    throw 'OWNER_BRAIN_R2_SOURCE_HASH_MISMATCH'
}
if (($lf -split '\n' | Where-Object { $_ -match "^    '[a-z0-9_]+\.py' = '[0-9a-f]{64}'$" }).Count -ne 14 -or
    -not $text.Contains("OWNER_BRAIN_R2_RECOVERY=ORIGINAL_OWNER_RESTORED") -or
    -not $text.Contains("P2_INFLIGHT_OR_ACTIVE_LOCK") -or
    -not $text.Contains("STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED")) {
    throw 'OWNER_BRAIN_R2_SOURCE_CONTRACT_INCOMPLETE'
}
Write-Output 'OWNER_BRAIN_R2_SOURCE=PASS_PARSE_PIN_14_BACKUP_ROLLBACK'
Write-Output 'OWNER_BRAIN_R2_SOURCE_OWNER=NOT_ACCESSED'
Write-Output 'OWNER_BRAIN_R2_SOURCE_P2_PROVIDER_TV=NOT_RUN'
