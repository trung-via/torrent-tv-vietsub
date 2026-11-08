# Harmless, reversible HostOps read/write execution proof.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
    $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') {
  throw 'BLOCKED: not the dedicated Torrent TV runner'
}
$root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
$workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\'
if (-not $workspace.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'BLOCKED: wrong workspace'
}

$dir = Join-Path $env:RUNNER_TEMP 'torrent-tv-hostops-smoke'
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$file = Join-Path $dir 'write-smoke.txt'
try {
  [IO.File]::WriteAllText($file, 'TORRENT_TV_HOSTOPS_V1')
  if ([IO.File]::ReadAllText($file) -cne 'TORRENT_TV_HOSTOPS_V1') {
    throw 'BLOCKED: write verification mismatch'
  }
  Write-Host 'HOSTOPS_SMOKE_WRITE_READ_PASS'
  $node = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($null -ne $node) {
    & $node.Source --version
    if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: node invocation failed' }
  }
  else { Write-Host 'HOSTOPS_NODE_NOT_ON_PATH' }
  & git --version
  if ($LASTEXITCODE -ne 0) { throw 'BLOCKED: git invocation failed' }
  Write-Host 'HOSTOPS_SMOKE_PASS'
}
finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
