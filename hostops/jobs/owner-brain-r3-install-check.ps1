# Windows source-only preflight for Owner Brain R2 transaction; no task or provider.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$files = @(
    'hostops/jobs/owner-laptop-ops-dispatch.ps1',
    'hostops/laptop-ops/operations/owner-brain-r3-install.ps1',
    'hostops/jobs/owner-brain-r3-install-check.ps1'
)
foreach ($rel in $files) {
    $path = Join-Path $env:GITHUB_WORKSPACE $rel
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'OWNER_BRAIN_R3_SOURCE_MISSING'
    }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $path,[ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) {
        foreach ($problem in $parseErrors) {
            Write-Output ('OWNER_BRAIN_R3_PARSE_ERROR_ID=' + $problem.ErrorId)
        }
        throw 'OWNER_BRAIN_R3_SOURCE_POWERSHELL_PARSE_FAILED'
    }
}
$manifest = Get-Content -LiteralPath (Join-Path $env:GITHUB_WORKSPACE 'hostops/laptop-ops/manifests/current.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.operation -cne 'owner-brain-r3-install' -or
    $manifest.risk -cne 'ROUTINE' -or
    $manifest.category -cne 'owner-maintenance' -or
    $manifest.script_path -cne 'hostops/laptop-ops/operations/owner-brain-r3-install.ps1') {
    throw 'OWNER_BRAIN_R3_SOURCE_MANIFEST_WRONG'
}
$operation = Join-Path $env:GITHUB_WORKSPACE $manifest.script_path
$text = [IO.File]::ReadAllText($operation,[Text.UTF8Encoding]::new($false,$true))
$lf = $text.Replace([string]([char]13)+[string]([char]10),[string][char]10)
$bytes = [Text.UTF8Encoding]::new($false).GetBytes($lf)
$hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
if ($hash -cne $manifest.script_sha256) {
    throw 'OWNER_BRAIN_R3_SOURCE_HASH_MISMATCH'
}
if (($lf -split '\n' | Where-Object { $_ -match "^    '[a-z0-9_]+\.py' = '[0-9a-f]{64}'$" }).Count -ne 16 -or
    -not $text.Contains("OWNER_BRAIN_R3_RECOVERY=ORIGINAL_OWNER_RESTORED") -or
    -not $text.Contains("P2_INFLIGHT_OR_ACTIVE_LOCK") -or
    -not $text.Contains("STAGED_OVERLAY_IMPORT_FAILED_OWNER_UNCHANGED")) {
    throw 'OWNER_BRAIN_R3_SOURCE_CONTRACT_INCOMPLETE'
}

if (-not $text.Contains("'automatic_lean120_worker.py' = '4eb92f5d8e8ef6191cab8ac8d68df99ff1d791ae800607d3c8f01bd02fc707dd'") -or
    -not $text.Contains("'progressive_handoff.py' = '782b4ac8b7d993405bbab37a6e1e2109ff2250c5efefb1d0da3a1b035c954cf3'") -or
    -not $text.Contains('flow.worker.first_window_cues == 50') -or
    -not $text.Contains('owner-brain-en-182-r3-20261123-7705971bfba9')) {
    throw 'OWNER_BRAIN_R3_DEPENDENCY_OR_STAGE_PIN_MISSING'
}
Write-Output 'OWNER_BRAIN_R3_SOURCE=PASS_PARSE_PIN_16_BACKUP_ROLLBACK'
Write-Output 'OWNER_BRAIN_R3_SOURCE_OWNER=NOT_ACCESSED'
Write-Output 'OWNER_BRAIN_R3_SOURCE_P2_PROVIDER_TV=NOT_RUN'
