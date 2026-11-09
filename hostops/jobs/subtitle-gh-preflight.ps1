# Read-only Windows owner GitHub CLI capability inventory for subtitle artifact handoff.
# No credential output, no repository mutation, no ADB, no media bytes.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Write-Host 'TTV_HANDOFF_PREFLIGHT_BEGIN'
if ($env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or $env:RUNNER_OS -cne 'Windows') {
    Write-Host 'TTV_HANDOFF_STATUS=WRONG_RUNNER'
    exit 0
}
$ghcmd = Get-Command gh.exe -ErrorAction SilentlyContinue
$gh = if ($null -ne $ghcmd) { [string]$ghcmd.Source } else { 'C:\Program Files\GitHub CLI\gh.exe' }
if (-not (Test-Path -LiteralPath $gh -PathType Leaf -ErrorAction SilentlyContinue)) {
    Write-Host 'TTV_HANDOFF_GH_CLI=NOT_INSTALLED_OR_NOT_ACCESSIBLE'
    Write-Host 'TTV_HANDOFF_STATUS=PRIVATE_REPO_CREATION_NOT_AVAILABLE'
    exit 0
}
Write-Host 'TTV_HANDOFF_GH_CLI=FOUND'
# Exclude ephemeral Actions repository token from "personal GitHub authentication" assessment.
$env:GH_TOKEN = ''
$env:GITHUB_TOKEN = ''
$env:GH_ENTERPRISE_TOKEN = ''
try {
    $status = @(& $gh auth status --hostname github.com 2>$null)
    $exit = $LASTEXITCODE
    if ($exit -eq 0) {
        Write-Host 'TTV_HANDOFF_PERSONAL_GH_AUTH=AVAILABLE'
        Write-Host 'TTV_HANDOFF_STATUS=CAN_INSPECT_PRIVATE_REPO_CREATION'
    } else {
        Write-Host 'TTV_HANDOFF_PERSONAL_GH_AUTH=UNAVAILABLE'
        Write-Host 'TTV_HANDOFF_STATUS=NEEDS_ONE_TIME_PRIVATE_REPO_SETUP'
    }
} catch {
    Write-Host 'TTV_HANDOFF_PERSONAL_GH_AUTH=UNAVAILABLE'
    Write-Host 'TTV_HANDOFF_STATUS=NEEDS_ONE_TIME_PRIVATE_REPO_SETUP'
}
Write-Host 'TTV_HANDOFF_NO_SECRET_OR_MEDIA_OUTPUT=TRUE'
Write-Host 'TTV_HANDOFF_PREFLIGHT_END'
exit 0
