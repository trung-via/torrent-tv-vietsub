# Read-only baseline for the two P2 files needed by a pinned Owner installer.
# Only SHA256 digests and Owner task state leave this Windows computer.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$spool = Join-Path $env:ProgramData 'TorrentTVVietsub\LaptopHostOps'
$requestPath = Join-Path $spool 'Requests\request.json'
$request = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
if ($request.schema -cne 'TTV-LAPTOP-HOSTOPS-REQUEST-V1' -or
    [string]$request.nonce -cnotmatch '^[0-9a-f]{32}$') {
    throw 'P2_BASELINE_REQUEST_INVALID'
}
$installed = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge\app\poc\p2-sub-discovery'
function InstalledHash([string]$filename) {
    $path = Join-Path $installed $filename
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return 'NOT_OBSERVED'
    }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        $item.Length -le 0 -or $item.Length -gt 1048576) {
        return 'NOT_OBSERVED'
    }
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$a = InstalledHash 'opensubtitles.py'
$b = InstalledHash 'owner_session_bridge.py'
$p4 = InstalledHash 'owner_r2_progressive_registry.py'
$task = Get-ScheduledTask -TaskName 'TorrentTV-Vietsub-OwnerAgent' -TaskPath '\' -ErrorAction SilentlyContinue
$ownerState = if ($null -eq $task) { 'NOT_OBSERVED' } elseif ($task.State -eq 'Running') {
    'RUNNING'
} elseif ($task.State -eq 'Ready') { 'READY' } else { 'OTHER' }
$current = Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
if ($current.nonce -cne $request.nonce) { throw 'P2_BASELINE_REQUEST_CHANGED' }
$data = [ordered]@{
    schema='TTV-P2-BASELINE-HASH-V1'; nonce=$request.nonce
    opensubtitles=$a; owner_bridge=$b; p4_registry=$p4; owner=$ownerState
}
$payload = $data | ConvertTo-Json -Compress
if ([Text.Encoding]::UTF8.GetByteCount($payload) -gt 512) {
    throw 'P2_BASELINE_SUMMARY_TOO_LONG'
}
$target = Join-Path $spool 'Receipts\p2-baseline.json'
$temp = $target + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
[IO.File]::WriteAllText($temp, $payload, [Text.UTF8Encoding]::new($false))
[IO.File]::Move($temp, $target, $true)
Write-Output 'P2_BASELINE=HASHES_CAPTURED_NO_INSTALL'
