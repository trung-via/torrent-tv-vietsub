# Static sanity check only (not a compiler, Android device, or G0 PASS).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot)
$ErrorActionPreference = 'Stop'
$base = Join-Path ((Resolve-Path -LiteralPath $OmpRoot).Path) 'android\app\src'
$activity = Get-Content -LiteralPath (Join-Path $base 'main\java\com\spacesarmat\omp\player\PlayerActivity.kt') -Raw -Encoding UTF8
$debug = Get-Content -LiteralPath (Join-Path $base 'debug\java\com\spacesarmat\omp\player\P1G0SubtitleProbe.kt') -Raw -Encoding UTF8
$release = Get-Content -LiteralPath (Join-Path $base 'release\java\com\spacesarmat\omp\player\P1G0SubtitleProbe.kt') -Raw -Encoding UTF8
$asset = Join-Path $base 'debug\assets\p1-vietsub-utf8.srt'
$releaseAsset = Join-Path $base 'release\assets\p1-vietsub-utf8.srt'
if (-not $activity.Contains('session.load(P1G0SubtitleProbe.prepare(this, r), next)')) { throw 'main seam missing' }
if (-not $debug.Contains('r.engine != EngineMode.VLC') -or
    -not $debug.Contains('File(context.filesDir, FLAG).isFile') -or
    -not $debug.Contains('r.copy(queue = items)')) { throw 'debug-only gating missing' }
if (-not $release.Contains('PlayRequest = r') -or $release.Contains('Uri.fromFile')) { throw 'release variant not a no-op' }
if (-not (Test-Path -LiteralPath $asset -PathType Leaf) -or
    (Test-Path -LiteralPath $releaseAsset)) { throw 'debug asset isolation failed' }
$fixtureText = Get-Content -LiteralPath $asset -Raw -Encoding UTF8
if (-not $fixtureText.Contains('Đường, Trường, Nguyễn')) { throw 'UTF-8 test fixture invalid' }
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }
Write-Host 'STATIC_CHECK_PASS: expected pinned patch structure and debug/release source-set split.'
Write-Host 'COMPILE_UNVERIFIED REAL_TV_UNVERIFIED EXTERNAL_SRT_E2E_UNVERIFIED'
