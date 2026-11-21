# Read-only source parser for the exact HostOps maintenance handoff.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'P2_CLEAR_AST_UNTRUSTED_RUNNER'
}
foreach ($relative in @(
    'hostops/jobs/owner-laptop-ops-dispatch.ps1',
    'hostops/laptop-ops/operations/owner-p2-fresh-start.ps1',
    'hostops/laptop-ops/operations/owner-p2-fresh-inspect.ps1',
    'hostops/jobs/owner-p2-fresh-inspect-readonly.ps1',
    'hostops/laptop-ops/operations/owner-p2-fresh-inspect-v2.ps1',
    'hostops/jobs/owner-p2-fresh-inspect-v2-readonly.ps1',
    'hostops/laptop-ops/operations/owner-p2-block-rootcause-v1.ps1',
    'hostops/jobs/owner-p2-block-rootcause-readonly.ps1'
)) {
    $file = Join-Path $env:GITHUB_WORKSPACE $relative
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile(
        $file, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) {
        throw 'P2_CLEAR_AST_PARSE_ERROR'
    }
}
Write-Output 'P2_CLEAR_HOSTOPS_AST=PASS_NO_OWNER_MUTATION'
