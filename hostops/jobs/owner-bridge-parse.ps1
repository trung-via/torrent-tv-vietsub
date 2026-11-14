# HostOps read-only Windows PowerShell syntax validation for owner bridge.
# No script execution, no UAC, no ACL/task/profile changes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_OS -cne 'Windows') {
    throw 'OWNER_BRIDGE_PARSER_UNTRUSTED_RUNNER'
}
$base = Join-Path $env:GITHUB_WORKSPACE 'poc\p2-sub-discovery'
$paths = @(
    (Join-Path $base 'install-owner-session-bridge.ps1'),
    (Join-Path $base 'start-owner-session-agent.ps1'),
    (Join-Path $base 'configure-runner-wake-acl.ps1'),
    (Join-Path $env:GITHUB_WORKSPACE 'hostops\jobs\owner-session-wake.ps1')
)
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw 'OWNER_BRIDGE_SYNTAX_SOURCE_MISSING'
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        Write-Host 'OWNER_BRIDGE_POWERSHELL_PARSE=FAIL'
        throw 'OWNER_BRIDGE_POWERSHELL_PARSE_FAILED'
    }
}
Write-Host 'OWNER_BRIDGE_POWERSHELL_PARSE=PASS'
Write-Host 'OWNER_BRIDGE_POWERSHELL_FILES=4'
Write-Host 'OWNER_BRIDGE_WINDOWS_PERMISSION_CHANGED=NO'
Write-Host 'OWNER_BRIDGE_SECRETS_READ=NO'
