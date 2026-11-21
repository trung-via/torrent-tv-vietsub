# Only after Owner V4 is running, P3 signs FRESH_OFF and P2 has no work.
# The helper preserves TV app data and verifies exact ADB APK readback.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'owner-p4-pr178-install.ps1')
if ($LASTEXITCODE -ne 0 -or -not $?) {
    throw 'P4_V2_INSTALL_FAILED'
}
