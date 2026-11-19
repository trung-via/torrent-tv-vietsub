# Safe Windows-only source parsing and R2 manifest hash validation.
# Does not access Owner/ProgramData, create tasks, stage files or run provider.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'HOSTOPS_OWNER_RELEASE_SOURCE_CHECK_RUNNER_REQUIRED'
}
$root = $env:GITHUB_WORKSPACE
function CanonicalGitSHA([string]$path) {
    # Windows Git may materialize a reviewed LF blob as CRLF. The manifest
    # pins raw Git/download bytes, not checkout-dependent disk bytes.
    $utf8 = [Text.UTF8Encoding]::new($false,$true)
    $source = $utf8.GetString([IO.File]::ReadAllBytes($path))
    if ($source.StartsWith([char]0xFEFF) -or
        $source.Replace("`r`n", "`n").Contains("`r")) {
        throw 'OWNER_RELEASE_SOURCE_CHECK_NONCANONICAL_LINE_ENDING'
    }
    $normal = $utf8.GetBytes($source.Replace("`r`n", "`n"))
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hash.ComputeHash($normal)).Replace('-','').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
$scripts = @(
    'hostops/setup/owner-release-stage-helper.ps1',
    'hostops/setup/enroll-owner-release-stage.ps1',
    'hostops/jobs/owner-release-stage-dispatch.ps1',
    'hostops/jobs/owner-release-source-check.ps1'
)
foreach ($path in $scripts) {
    $source = Join-Path $root ($path.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw 'OWNER_RELEASE_SOURCE_CHECK_SCRIPT_MISSING'
    }
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $source, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) {
        $errors | ForEach-Object { Write-Output ('PARSE_ERROR=' + $_.ErrorId) }
        throw 'OWNER_RELEASE_SOURCE_CHECK_POWERSHELL_PARSE_FAILED'
    }
}
Write-Output 'OWNER_RELEASE_SOURCE_POWERSHELL_PARSE=PASS'

$manifest = Get-Content -LiteralPath (Join-Path $root 'hostops\releases\owner-r2-stage-v1.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
    $manifest.release_id -cne 'r2-rolling-175' -or
    $manifest.mode -cne 'STAGE_ONLY' -or @($manifest.files).Count -ne 14) {
    throw 'OWNER_RELEASE_SOURCE_CHECK_MANIFEST_INVALID'
}
$seen = @{}
foreach ($row in $manifest.files) {
    if ($row.path -cnotmatch '\Apoc/(p2-aisub|p2-sub-discovery)/(?!test_)[a-z0-9_]+\.py\z' -or
        $row.sha256 -cnotmatch '\A[0-9a-f]{64}\z' -or
        $seen.ContainsKey($row.path)) {
        throw 'OWNER_RELEASE_SOURCE_CHECK_PATH_INVALID'
    }
    $seen[$row.path] = $true
    $file = Join-Path $root ($row.path.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or
        (CanonicalGitSHA $file) -cne $row.sha256) {
        throw 'OWNER_RELEASE_SOURCE_CHECK_FILE_HASH_INVALID'
    }
}
Write-Output 'OWNER_RELEASE_SOURCE_PINNED_MANIFEST=PASS'
Write-Output 'OWNER_RELEASE_SOURCE_INSTALLED_OWNER=NOT_READ'
Write-Output 'OWNER_RELEASE_SOURCE_PROVIDER_TV=NOT_RUN'
