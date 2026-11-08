# Non-destructive capability inventory for the dedicated Torrent TV runner.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win') {
  throw 'BLOCKED: unexpected runner/repository'
}
$root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
$workspace = [IO.Path]::GetFullPath($env:GITHUB_WORKSPACE).TrimEnd('\') + '\'
if (-not $workspace.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'BLOCKED: wrong workspace'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$admin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ('HOSTOPS_ADMIN_TOKEN=' + $admin.ToString().ToUpperInvariant())
foreach ($cmd in @('git.exe', 'node.exe', 'npm.cmd', 'java.exe', 'javac.exe', 'adb.exe', 'gradle.bat')) {
  $found = [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
  Write-Host ('HOSTOPS_TOOL_' + $cmd.Replace('.', '_').ToUpperInvariant() + '=' + $found.ToString().ToUpperInvariant())
}
$probe = Join-Path $env:GITHUB_WORKSPACE 'hostops-permission-probe.tmp'
try {
  [IO.File]::WriteAllText($probe, 'TORRENT_TV_WORKSPACE_WRITE_PASS')
  if ([IO.File]::ReadAllText($probe) -cne 'TORRENT_TV_WORKSPACE_WRITE_PASS') {
    throw 'BLOCKED: repo workspace write/read failed'
  }
  Write-Host 'HOSTOPS_REPO_WORKSPACE_WRITE_PASS'
}
finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
Write-Host 'HOSTOPS_ACCESS_INVENTORY_PASS'
