# Dedicated Windows HostOps: parser/compatibility test only.
# Never access Owner DPAPI or installed private files from NETWORK SERVICE.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
    $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_ACTIONS -cne 'true') {
    throw 'P2_F6_WRONG_HOSTOPS_RUNNER'
}
$repair = Join-Path $env:GITHUB_WORKSPACE 'hostops\setup\p2-f6-owner-bootstrap-compat-upgrade.ps1'
if (-not (Test-Path -LiteralPath $repair -PathType Leaf)) {
    throw 'P2_F6_SOURCE_MISSING'
}
$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $repair, [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) {
    Write-Host ('P2_F6_PARSE_ERROR_COUNT=' + @($errors).Count)
    throw 'P2_F6_PWSH_PARSE_FAILED'
}
Write-Host 'P2_F6_PWSH51_PARSE=PASS'
# Expected owner-session rejection writes to stderr. Windows PowerShell 5.1
# may promote native stderr into a terminating NativeCommandError when Stop
# is in effect; capture the expected error without masking the exit code.
$priorErrorAction = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $output = @(& powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $repair 2>&1)
    $exitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $priorErrorAction
}
if ($exitCode -eq 0 -or -not (@($output | Where-Object {
    [string]$_ -match 'P2_F6_INTERACTIVE_OWNER_REQUIRED'
}).Count -ge 1)) {
    throw 'P2_F6_SERVICE_BOUNDARY_FAILED'
}
Write-Host 'P2_F6_SERVICE_BOUNDARY=PASS'
Write-Host 'P2_F6_PRIVATE_OWNER_DATA=NOT_ACCESSED'
Write-Host 'P2_F6_TASK_MUTATION=NONE'
Write-Host 'P2_F6_PROVIDER_AND_TV=NOT_RUN'
