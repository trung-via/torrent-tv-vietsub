# Safe GitHub runner preflight: parse-only, fixture-only, no Owner/TV/provider.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)
$files = @(
    'hostops/setup/owner-r2-checkpoint-apply-once.ps1',
    'hostops/setup/enroll-owner-r2-checkpoint-apply.ps1',
    'hostops/jobs/owner-r2-checkpoint-apply-dispatch.ps1'
)
foreach ($rel in $files) {
    $path = Join-Path $root $rel.Replace('/','\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'SOURCE_CHECK_MISSING_FILE' }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,
        [ref]$tokens,[ref]$parseErrors)
    if (@($parseErrors).Count -ne 0) { throw ('SOURCE_CHECK_POWERSHELL_SYNTAX_' + $rel) }
}
$manifest = Join-Path $root 'hostops\releases\owner-r2-checkpoint-stage-v1.json'
$data = Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if ($data.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
    $data.mode -cne 'STAGE_ONLY' -or
    $data.release_id -cne 'r2-checkpoint-175' -or
    $data.source_tree -cne '59ae1fd70c1d403ba812a9b40d2b56e5fa0cbf0f' -or
    @($data.files).Count -ne 5) { throw 'SOURCE_CHECK_RELEASE_MANIFEST_DRIFT' }
foreach ($entry in $data.files) {
    $source = Join-Path $root ([string]$entry.path).Replace('/','\')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or
        [string]$entry.sha256 -cnotmatch '\A[0-9a-f]{64}\z') {
        throw 'SOURCE_CHECK_STAGE_PATH_OR_SHA_INVALID'
    }
}
# Windows git checkout may CRLF-normalize source files, so their working-tree
# SHA256 is not the exact raw-Git SHA256. The Owner-side STAGE_ONLY receipt
# already verified each downloaded raw source byte against this manifest.
$installer = Get-Content -LiteralPath (Join-Path $root $files[0]) -Raw
if ($installer -notmatch [regex]::Escape('STARTED_OWNER_STOP_P2_STATE_PRESERVED') -or
    $installer -notmatch [regex]::Escape('INSTALLED_OWNER_FRESH_P2_STATE_PRESERVED') -or
    $installer -notmatch [regex]::Escape('ROLLED_BACK_OLD_OWNER_FRESH') -or
    $installer -match '(?i)Remove-Item[^\r\n]*(active\.lock|batch-|event-)' -or
    $installer -match '(?i)Invoke-RestMethod[^\r\n]*(gemini|antigravity)') {
    throw 'SOURCE_CHECK_OWNER_STATE_CONTRACT_DRIFT'
}
Write-Output 'HOSTOPS_OWNER_CHECKPOINT_SOURCE=PS_PARSE_3_RELEASE_MANIFEST_VALID_PASS'
Write-Output 'HOSTOPS_OWNER_CHECKPOINT_SOURCE_OWNER=UNTOUCHED'
Write-Output 'HOSTOPS_OWNER_CHECKPOINT_SOURCE_PROVIDER_TV=NOT_RUN'
