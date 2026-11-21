# Read-only Stage/APK/ADB/signer/ABI check before Owner V4 installation.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'owner-p4-pr178-install.ps1') -PreflightOnly
if ($LASTEXITCODE -ne 0 -or -not $?) {
    throw 'P4_V2_PREFLIGHT_FAILED'
}
