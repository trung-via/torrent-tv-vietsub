# Routine Owner operation. All remote bytes are pinned to a source commit and
# checked before the existing guarded installer gets -Apply. No provider/TV call.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commit = 'b92926714199fa986c29b48202460d903a518025'
$expected = 'd1877e7a3f25c026252f9bcdfb9b308a27d4008e319d431145750b8207484e08'
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
