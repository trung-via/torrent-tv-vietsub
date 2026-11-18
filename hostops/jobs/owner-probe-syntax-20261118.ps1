# HostOps syntax/early-owner-boundary check; never accesses Owner files.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_OWNER_PROBE_WRONG_HOSTOPS_RUNNER'
}
$probe = Join-Path $env:GITHUB_WORKSPACE 'hostops\setup\owner-startup-offline-rootcause-probe.ps1'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw 'TTV_OWNER_PROBE_SOURCE_MISSING'
}
$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $probe, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -ne 0) {
    Write-Host ('TTV_OWNER_PROBE_PARSE_ERRORS=' + @($parseErrors).Count)
    throw 'TTV_OWNER_PROBE_SYNTAX_FAIL'
}
Write-Host 'TTV_OWNER_PROBE_PWSH51_PARSE=PASS'
# A service runner must stop BEFORE any private file, DPAPI, LAN or provider read.
$out = @(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe 2>&1)
$exitCode = $LASTEXITCODE
if ($exitCode -ne 2 -or
    @($out | Where-Object {
        [string]$_ -eq 'TTV_STARTUP_PROBE_RESULT=HOLD_INTERACTIVE_OWNER_REQUIRED'
    }).Count -ne 1) {
    throw 'TTV_OWNER_PROBE_SERVICE_BOUNDARY_FAIL'
}
Write-Host 'TTV_OWNER_PROBE_SERVICE_BOUNDARY=PASS'
Write-Host 'TTV_OWNER_PROBE_LIVE_OWNER_SESSION=NOT_RUN'
Write-Host 'TTV_OWNER_PROBE_PROVIDER_OR_LAN_CALL=NONE'
