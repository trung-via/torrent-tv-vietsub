# Identical pinned source/TV/Owner checks, without any ADB installation.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
& (Join-Path $PSScriptRoot 'owner-p4-pr178-install.ps1') -PreflightOnly
if (-not $?) { throw 'P4_PR178_PREFLIGHT_HELPER_FAILED' }
