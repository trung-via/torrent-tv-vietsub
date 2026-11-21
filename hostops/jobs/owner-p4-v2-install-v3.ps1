# Pin exact OMP V2 package and verify ADB readback. P3 MISSING requires no OMP process.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'owner-p4-pr178-install.ps1')
if ($LASTEXITCODE -ne 0 -or -not $?) { throw 'P4_V2_V3_INSTALL_FAILURE' }
