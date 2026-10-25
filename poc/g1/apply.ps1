# P1a G1b: reversible debug-only external-SRT probe on clean pinned OMP.
# NO runner dispatch, build, ADB, Windows service, network or AIOS changes.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$OmpRoot,
  [string]$AppRepoRoot = (Join-Path $PSScriptRoot '..\..')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ompPin = '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f'
$playerPin = '6ba6edd39f5d986ddfae29b5425b8ac0b319844e'
$OmpRoot = (Resolve-Path -LiteralPath $OmpRoot).Path
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path

if ($env:GITHUB_ACTIONS -eq 'true') {
  if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
      $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
      $env:RUNNER_OS -cne 'Windows') {
    throw 'STOP: not the dedicated Torrent TV runner'
  }
  if (-not $env:RUNNER_TEMP -or -not $env:GITHUB_RUN_ID -or -not $env:GITHUB_RUN_ATTEMPT) {
    throw 'STOP: missing runner identity'
  }
  $root = [IO.Path]::GetFullPath('C:\TOOL\TorrentTV-Runner\_work').TrimEnd('\') + '\'
  foreach ($candidate in @($env:RUNNER_WORKSPACE, $env:RUNNER_TEMP)) {
    if (-not $candidate) { throw 'STOP: missing runner workspace/temp' }
    $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\') + '\'
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'STOP: runner escapes dedicated Torrent TV root'
    }
  }
  $expected = [IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP "p1-g1-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT")).TrimEnd('\')
  if (-not [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\').Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: only the exact disposable G1 worktree may be patched'
  }
}

$gitRoot = (& git -C $OmpRoot rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or
    -not ([IO.Path]::GetFullPath($gitRoot).TrimEnd('\').Equals(
      [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase))) {
  throw 'STOP: OmpRoot must be the exact Git root'
}
$sha = (& git -C $OmpRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $sha.Trim() -cne $ompPin) { throw 'STOP: OMP pin mismatch' }
$vendorRoot = Join-Path $OmpRoot 'android\vendor\2160player'
$vendorSha = (& git -C $vendorRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $vendorSha.Trim() -cne $playerPin) {
  throw 'STOP: 2160player submodule pin mismatch'
}
$dirty = @(& git -C $OmpRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0 -or $dirty.Count -ne 0) {
  throw 'STOP: worktree must be clean; never overwrite G0 or prior work'
}
if (-not (Test-Path -LiteralPath (Join-Path $OmpRoot 'LICENSE') -PathType Leaf)) {
  throw 'STOP: source license missing'
}

$main = Join-Path $OmpRoot 'android\app\src\main\java\com\spacesarmat\omp\player\PlayerActivity.kt'
$debug = Join-Path $OmpRoot 'android\app\src\debug\java\com\spacesarmat\omp\player\P1G1SubtitleProbe.kt'
$release = Join-Path $OmpRoot 'android\app\src\release\java\com\spacesarmat\omp\player\P1G1SubtitleProbe.kt'
$fromDebug = Join-Path $PSScriptRoot 'P1G1SubtitleProbe.debug.kt'
$fromRelease = Join-Path $PSScriptRoot 'P1G1SubtitleProbe.release.kt'
foreach ($f in @($main, $fromDebug, $fromRelease)) {
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "STOP: missing input $f" }
}
foreach ($f in @($debug, $release)) {
  if (Test-Path -LiteralPath $f) { throw 'STOP: destination exists; refusing overwrite' }
}
$original = [IO.File]::ReadAllText($main)
$old = '        session.load(r, next)'
$new = '        session.load(P1G1SubtitleProbe.prepare(this, r), next)'
if (-not $original.Contains($old) -or
    $original.IndexOf($old) -ne $original.LastIndexOf($old) -or
    $original.Contains('P1G0SubtitleProbe') -or $original.Contains($new)) {
  throw 'STOP: unique pinned player seam missing or G0 already patched'
}

# Mutation begins only after all preflight gates.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($main, $original.Replace($old, $new), $utf8)
foreach ($pair in @(@($fromDebug, $debug), @($fromRelease, $release))) {
  $dest = $pair[1]
  New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
  Copy-Item -LiteralPath $pair[0] -Destination $dest -ErrorAction Stop
}
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: git diff --check failed' }
Write-Host 'G1B_PATCH_APPLIED_STATIC_ONLY'
Write-Host 'NO_BUILD_OR_REAL_TV_PASS; NO_G1_PERSISTENCE_OR_E2E_PASS'
Write-Host 'Rollback: discard this disposable OMP worktree.'
