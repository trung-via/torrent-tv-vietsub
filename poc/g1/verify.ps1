# P1 G1b static checks only; neither Kotlin/Gradle nor a real-TV verification.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$src = Join-Path ((Resolve-Path -LiteralPath $OmpRoot).Path) 'android\app\src'
$main = Get-Content -LiteralPath (Join-Path $src 'main\java\com\spacesarmat\omp\player\PlayerActivity.kt') -Raw -Encoding UTF8
$debug = Get-Content -LiteralPath (Join-Path $src 'debug\java\com\spacesarmat\omp\player\P1G1SubtitleProbe.kt') -Raw -Encoding UTF8
$release = Get-Content -LiteralPath (Join-Path $src 'release\java\com\spacesarmat\omp\player\P1G1SubtitleProbe.kt') -Raw -Encoding UTF8
if (-not $main.Contains('session.load(P1G1SubtitleProbe.prepare(this, r), next)') -or
    $main.Contains('P1G0SubtitleProbe')) { throw 'main seam collision' }
foreach ($needle in @(
  'r.engine != EngineMode.VLC',
  'File(context.filesDir, FLAG)',
  'File(context.filesDir, EXTERNAL_NAME)',
  'CodingErrorAction.REPORT',
  'if (!marker.delete()) return r',
  'updated[r.index] = current.copy',
  'r.copy(queue = updated)'
)) {
  if (-not $debug.Contains($needle)) { throw "debug guard missing: $needle" }
}
if (-not $release.Contains('PlayRequest = r') -or
    $release.Contains('Uri.fromFile') -or
    $release.Contains('File(context.filesDir')) { throw 'release must be no-op' }
# No G1 SRT bytes are shipped with any build variant.
foreach ($candidate in @(
  'debug\assets\p1-g1-external.vi.srt',
  'main\assets\p1-g1-external.vi.srt',
  'release\assets\p1-g1-external.vi.srt'
)) {
  if (Test-Path -LiteralPath (Join-Path $src $candidate)) { throw 'G1 SRT unexpectedly bundled into APK' }
}
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }
Write-Host 'G1B_STATIC_CHECK_PASS: debug/release split, external file only, one-shot marker.'
Write-Host 'ANDROID_BUILD_UNVERIFIED REAL_TV_UNVERIFIED G1C_PERSISTENCE_UNVERIFIED EXTERNAL_SRT_E2E_UNVERIFIED'
