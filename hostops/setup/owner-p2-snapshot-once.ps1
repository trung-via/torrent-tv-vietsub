# One-time interactive Owner -> already enrolled HostOps read-only receipt.
# This script does not touch the Owner Task, media queue, P2 marker or provider.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not [Environment]::UserInteractive -or
    [Diagnostics.Process]::GetCurrentProcess().SessionId -le 0 -or
    $env:GITHUB_ACTIONS -ceq 'true') {
    throw 'OWNER_P2_SNAPSHOT_INTERACTIVE_OWNER_REQUIRED'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$logged = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
if ([string]::IsNullOrWhiteSpace($logged) -or
    -not $identity.Name.Equals($logged, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OWNER_P2_SNAPSHOT_WRONG_WINDOWS_OWNER'
}

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\OwnerBridge\Diagnostics'
if (-not (Test-Path -LiteralPath $spool -PathType Container)) {
    throw 'OWNER_P2_SNAPSHOT_HOSTOPS_SPOOL_NOT_ENROLLED'
}
$spoolItem = Get-Item -LiteralPath $spool -Force
if ($spoolItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
    throw 'OWNER_P2_SNAPSHOT_SPOOL_REPARSE_REFUSED'
}

# Immutable GitHub blob, not a mutable branch or an Owner-installed Python tree.
# Source pins were reviewed in PR #175 at 4bfa0b376b41a0b6c80c3921ace0f4558aafc137.
$base = 'https://raw.githubusercontent.com/trung-via/torrent-tv-vietsub/4bfa0b376b41a0b6c80c3921ace0f4558aafc137/poc/p2-sub-discovery'
$pins = [ordered]@{
    'owner_hostops_snapshot.py' = '91e1c3400cfdca347c0cd15c5da9ee942d2a189a095e4ab7cb583a1d7664eb4f'
    'owner_p3_p4_diagnostics.py' = 'eca75e1f29f98cf8df356f5bf9e29e1f30ffa0ea4205a4be93ffabe55e36f524'
    'p3_ingress_telemetry.py' = 'd09c8503ab13577b3102f943e402cf98e2e78b4192f61597e9eb0a6d9c63b67d'
}
$stage = Join-Path $env:TEMP ('TorrentTV-P2-Readonly-' + [Guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stage -ErrorAction Stop)
foreach ($name in $pins.Keys) {
    $target = Join-Path $stage $name
    Invoke-WebRequest -Uri "$base/$name" -OutFile $target -ErrorAction Stop
    $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    if (-not $actual.Equals($pins[$name], [StringComparison]::OrdinalIgnoreCase)) {
        throw 'OWNER_P2_SNAPSHOT_SOURCE_HASH_MISMATCH'
    }
}

# Only the existing fixed-schema sanitized exporter may read private P2 metadata.
# It writes atomically to pre-enrolled ProgramData; not to Owner P2 state.
$pythonCode = @'
import os
from pathlib import Path
from owner_hostops_snapshot import publish_owner_snapshot
root = Path(os.environ["LOCALAPPDATA"]) / "TorrentTVVietsub" / "OwnerBridge"
if not publish_owner_snapshot(owner_root=root):
    raise SystemExit("OWNER_P2_SNAPSHOT_EXPORT_FAILED")
print("OWNER_P2_SNAPSHOT_EXPORT=SUCCESS")
'@
$oldPythonPath = $env:PYTHONPATH
try {
    $env:PYTHONPATH = $stage
    & py -3.14 -c $pythonCode
    if ($LASTEXITCODE -ne 0) { throw 'OWNER_P2_SNAPSHOT_PYTHON_FAILED' }
} finally {
    $env:PYTHONPATH = $oldPythonPath
}

$receipt = Join-Path $spool 'owner-snapshot.json'
if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) {
    throw 'OWNER_P2_SNAPSHOT_RECEIPT_MISSING'
}
$doc = Get-Content -LiteralPath $receipt -Raw -Encoding UTF8 | ConvertFrom-Json
if ($doc.schema -cne 'TTV-HOSTOPS-OWNER-SNAPSHOT-V2') {
    throw 'OWNER_P2_SNAPSHOT_RECEIPT_SCHEMA_INVALID'
}
Write-Output "OWNER_P2_SNAPSHOT_STATUS=$($doc.p2.status)"
Write-Output "OWNER_P2_SNAPSHOT_PENDING_EVENTS=$($doc.p2.pending_events)"
Write-Output "OWNER_P2_SNAPSHOT_INFLIGHT_COUNT=$($doc.p2.inflight_count)"
Write-Output 'OWNER_P2_SNAPSHOT_TASK_OR_PROVIDER=NOT_CHANGED'
