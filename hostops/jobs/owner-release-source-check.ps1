# Safe Windows-only source parsing and active Owner hotfix stage validation.
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
function GitBlobSHA([string]$path) {
    # Read Git's exact binary blob, not Windows checkout bytes (CRLF/BOM filters).
    if ($path -cnotmatch '\A(?:poc/|hostops/)[a-z0-9_./-]+\z') {
        throw 'OWNER_RELEASE_SOURCE_CHECK_UNSAFE_GIT_PATH'
    }
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git.exe'
    $psi.Arguments = 'show HEAD:' + $path
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($psi)
    $stream = [IO.MemoryStream]::new()
    try {
        $process.StandardOutput.BaseStream.CopyTo($stream)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0 -or $stream.Length -le 0 -or
            $stream.Length -gt 1048576) {
            throw 'OWNER_RELEASE_SOURCE_CHECK_GIT_BLOB_UNAVAILABLE'
        }
        $bytes = $stream.ToArray()
    } finally { $stream.Dispose(); $process.Dispose() }
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
$scripts = @(
    'hostops/setup/owner-release-stage-helper.ps1',
    'hostops/setup/enroll-owner-release-stage.ps1',
    'hostops/setup/owner-r2-release-offline-apply.ps1',
    'hostops/setup/owner-r2-maintenance-once.ps1',
    'hostops/setup/owner-r2-deblock-offline-apply.ps1',
    'hostops/setup/owner-r2-deblock-maintenance-once.ps1',
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

$manifest = Get-Content -LiteralPath (Join-Path $root 'hostops\releases\owner-r2-deblock-stage-v1.json') `
    -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.schema -cne 'TTV-OWNER-RELEASE-STAGE-V1' -or
    $manifest.release_id -cne 'r2-deblock-175' -or
    $manifest.mode -cne 'STAGE_ONLY' -or @($manifest.files).Count -ne 3) {
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
        (GitBlobSHA $row.path) -cne $row.sha256) {
        throw 'OWNER_RELEASE_SOURCE_CHECK_FILE_HASH_INVALID'
    }
}
Write-Output 'OWNER_RELEASE_SOURCE_PINNED_MANIFEST=PASS'
Write-Output 'OWNER_RELEASE_SOURCE_INSTALLED_OWNER=NOT_READ'
Write-Output 'OWNER_RELEASE_SOURCE_PROVIDER_TV=NOT_RUN'
