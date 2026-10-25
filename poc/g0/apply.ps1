# P1 G0: apply a small, reversible, debug-only probe to a clean, pinned OMP worktree.
# No services, SMB, credentials, firewall rules or Android device access.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$OmpRoot,
  [string]$AppRepoRoot = (Join-Path $PSScriptRoot '..\..')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$pinOmp = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$pinPlayer = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$OmpRoot = (Resolve-Path -LiteralPath $OmpRoot).Path
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
if ($env:GITHUB_ACTIONS -eq 'true') {
  if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
      $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
      $env:RUNNER_OS -cne 'Windows') {
    throw 'STOP: not the dedicated Torrent TV GitHub Actions runner'
  }
  $workspace = [IO.Path]::GetFullPath($env:RUNNER_WORKSPACE).TrimEnd('\') + '\'
  $root = [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\') + '\'
  if (-not $root.StartsWith($workspace, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: OMP source is outside the dedicated runner workspace'
  }
}
$repoRoot = (& git -C $OmpRoot rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($repoRoot).TrimEnd('\') -ne
    [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\')) {
  throw 'STOP: OmpRoot must be exactly the pinned OMP git root'
}
$upstream = (& git -C $OmpRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $upstream.Trim() -cne $pinOmp) {
  throw 'STOP: OMP commit mismatch'
}
$vendor = Join-Path $OmpRoot 'android\vendor\2160player'
$vendorSha = (& git -C $vendor rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $vendorSha.Trim() -cne $pinPlayer) {
  throw 'STOP: 2160player submodule commit mismatch'
}
$dirty = @(& git -C $OmpRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
  throw 'STOP: OMP worktree must be clean; never overwrite a prior patch'
}
if (-not (Test-Path -LiteralPath (Join-Path $OmpRoot 'LICENSE'))) {
  throw 'STOP: upstream LICENSE is missing'
}
$main = Join-Path $OmpRoot 'android\app\src\main\java\com\spacesarmat\omp\player\PlayerActivity.kt'
$debug = Join-Path $OmpRoot 'android\app\src\debug\java\com\spacesarmat\omp\player\P1G0SubtitleProbe.kt'
$release = Join-Path $OmpRoot 'android\app\src\release\java\com\spacesarmat\omp\player\P1G0SubtitleProbe.kt'
$asset = Join-Path $OmpRoot 'android\app\src\debug\assets\p1-vietsub-utf8.srt'
$fixture = Join-Path $AppRepoRoot 'fixtures\p1-vietsub-utf8.srt'
$fromDebug = Join-Path $PSScriptRoot 'P1G0SubtitleProbe.debug.kt'
$fromRelease = Join-Path $PSScriptRoot 'P1G0SubtitleProbe.release.kt'
foreach ($file in @($fixture, $fromDebug, $fromRelease, $main)) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "STOP: missing prerequisite $file" }
}
foreach ($file in @($debug, $release, $asset)) {
  if (Test-Path -LiteralPath $file) { throw "STOP: would overwrite a file: $file" }
}
$old = '        session.load(r, next)'
$new = '        session.load(P1G0SubtitleProbe.prepare(this, r), next)'
$original = [IO.File]::ReadAllText($main)
if (-not $original.Contains($old) -or $original.IndexOf($old) -ne $original.LastIndexOf($old) -or
    $original.Contains($new)) {
  throw 'STOP: expected unique pinned PlayerActivity.load() seam was not found'
}
# All preflight above must pass before any OMP file is mutated.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($main, $original.Replace($old, $new), $utf8)
foreach ($pair in @(@($fromDebug, $debug), @($fromRelease, $release), @($fixture, $asset))) {
  $dst = $pair[1]
  New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
  Copy-Item -LiteralPath $pair[0] -Destination $dst -ErrorAction Stop
}
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: git diff --check failed' }
Write-Host 'P1 G0 patch prepared on the pinned isolated OMP worktree.'
Write-Host 'No build, real-TV test or external-file import PASS is implied.'
Write-Host 'Rollback: git restore -- android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt'
Write-Host 'Rollback: delete only the three new G0 debug/release files copied by this script.'
