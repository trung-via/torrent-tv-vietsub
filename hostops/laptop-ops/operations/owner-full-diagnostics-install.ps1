# Routine Owner operation. All remote bytes are pinned to a source commit and
# checked before the existing guarded installer gets -Apply. No provider/TV call.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commit = '5bb0dfc114e0f8702ce86cb768a387a521e94fee'
$expected = '430317baf5574d9dda186684cad4ebd95cfcf3d5e839cc6799af1c3ac50e3361'
$temp = Join-Path $env:TEMP ('ttv-owner-full-diag-ops-' + [Guid]::NewGuid().ToString('N') + '.ps1')
try {
    $uri = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/' +
        $commit + '/hostops/setup/owner-full-diagnostics-maintenance-once.ps1'
    Invoke-WebRequest -Uri $uri -OutFile $temp -ErrorAction Stop
    if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
        throw 'OWNER_OPS_FULL_DIAGNOSTICS_INSTALLER_HASH_MISMATCH'
    }
    & pwsh -NoLogo -NoProfile -NonInteractive -File $temp -Apply
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_OPS_FULL_DIAGNOSTICS_INSTALL_FAILED' }
    Write-Output 'OWNER_OPS_FULL_DIAGNOSTICS=INSTALLED_FRESH_OWNER_RUNNING'
} finally {
    if (Test-Path -LiteralPath $temp -PathType Leaf) {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }
}
