# A bounded HostOps job alias for the PR #178 signed native media-key Owner
# source. The reusable Owner-session task performs STAGE_ONLY: never applies
# code, restarts the Owner agent, resets P2 or touches the TV.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'owner-release-stage-dispatch.ps1')
if ($LASTEXITCODE -ne 0 -or -not $?) {
    throw 'OWNER_P4_V4_STAGE_DISPATCH_FAILED'
}
