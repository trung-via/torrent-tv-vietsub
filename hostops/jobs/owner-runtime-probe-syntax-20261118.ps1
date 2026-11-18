# Windows HostOps: syntax and service-account fail-closed only.
# Does not use the owner's DPAPI, start owner tasks, bind LAN or call P2.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'TTV_RUNTIME_PROBE_WRONG_HOSTOPS_RUNNER'
}
$probe = Join-Path $env:GITHUB_WORKSPACE 'hostops\setup\owner-runtime-offline-stage-probe.ps1'
if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) {
    throw 'TTV_RUNTIME_PROBE_SOURCE_MISSING'
}
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $probe, [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) {
    Write-Host ('TTV_RUNTIME_PROBE_PARSE_ERROR_COUNT=' + @($errors).Count)
    throw 'TTV_RUNTIME_PROBE_PARSE_FAILED'
}
Write-Host 'TTV_RUNTIME_PROBE_PWSH51_PARSE=PASS'
$output = @(powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probe 2>&1)
if ($LASTEXITCODE -ne 2 -or
    @($output | Where-Object {
        [string]$_ -eq 'TTV_RUNTIME_PROBE_RESULT=HOLD_INTERACTIVE_OWNER_REQUIRED'
    }).Count -ne 1) {
    throw 'TTV_RUNTIME_PROBE_SERVICE_BOUNDARY_FAILED'
}
Write-Host 'TTV_RUNTIME_PROBE_SERVICE_BOUNDARY=PASS'
Write-Host 'TTV_RUNTIME_PROBE_OWNER_DPAPI=NOT_ACCESSED'
Write-Host 'TTV_RUNTIME_PROBE_OWNER_TASK=NOT_STARTED'
Write-Host 'TTV_RUNTIME_PROBE_EXTERNAL_CALLS=NONE'
