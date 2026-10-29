# G1 Production static guards ONLY. Not a compile, Release or real-TV PASS.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$OmpRoot = (Resolve-Path -LiteralPath $OmpRoot).Path
$main = Join-Path $OmpRoot 'android\app\src\main\java\com\spacesarmat\omp\player'
$helperPath = Join-Path $main 'P1ProductionSubtitles.kt'
$activityPath = Join-Path $main 'PlayerActivity.kt'
$sessionPath = Join-Path $main 'PlayerSession.kt'
$switcherPath = Join-Path $main 'EngineSwitcher.kt'
$testPath = Join-Path $OmpRoot 'android\app\src\test\java\com\spacesarmat\omp\player\P1ProductionSubtitlesTest.kt'
$nativePath = Join-Path $main 'NativePlayer.kt'
$clientPath = Join-Path $OmpRoot 'src\api\torrserver.ts'
$pagePath = Join-Path $OmpRoot 'src\player\nativePlayer.ts'
foreach ($path in @($helperPath,$activityPath,$nativePath,$clientPath,$pagePath,$sessionPath,$switcherPath,$testPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'STOP: missing production source file' }
}
$helper = [IO.File]::ReadAllText($helperPath)
$activity = [IO.File]::ReadAllText($activityPath)
$sessionSource = [IO.File]::ReadAllText($sessionPath)
$switcherSource = [IO.File]::ReadAllText($switcherPath)
$unitSource = [IO.File]::ReadAllText($testPath)
$native = [IO.File]::ReadAllText($nativePath)
$client = [IO.File]::ReadAllText($clientPath)
$page = [IO.File]::ReadAllText($pagePath)
$assertions = @(
    @($helper, 'private const val MAX = 256 * 1024'),
    @($helper, 'CodingErrorAction.REPORT'),
    @($helper, 'fun mediaKey(r: PlayRequest?, index: Int): String?'),
    @($helper, 'val profile = r.serverProfileId ?: return null'),
    @($helper, 'val fileIndex = item.fileIndex ?: return null'),
    @($helper, 'fun importSelected(ctx: Context, uri: Uri, r: PlayRequest, i: Int): Boolean'),
    @($helper, 'ctx.contentResolver.openInputStream(uri)'),
    @($helper, 'fun noteTrackChoice(ctx: Context, r: PlayRequest?, i: Int, choice: TrackChoice)'),
    @($helper, 'choice.off -> "off"'),
    @($helper, 'choice.label == LABEL -> "on"'),
    @($helper, 'it.label == LABEL && it.url != expectedUri'),
    @($helper, 'if (!currentTrusted) return Prepared(base, warning)'),
    @($helper, 'fun prepare(ctx: Context, r: PlayRequest): Prepared'),
    @($helper, 'internal fun detectedExtension(bytes: ByteArray): String?'),
    @($helper, 'internal fun transitionPicks('),
    @($helper, 'internal fun savedSidecarTrackIndex('),
    @($helper, 'fun forItem(ctx: Context, r: PlayRequest?, i: Int, fallback: List<TrackPick>): ItemTransition'),
    @($activity, 'ActivityResultContracts.OpenDocument()'),
    @($activity, 'P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)'),
    @($activity, 'P1ProductionSubtitles.removeSaved(this, session.request, i)'),
    @($activity, 'val production = P1ProductionSubtitles.prepare(this, r)'),
    @($activity, 'session.load(production.request, next)'),
    @($activity, 'P1ProductionSubtitles.noteTrackChoice(this, session.request, index(), choice)'),
    @($activity, 'P1ProductionSubtitles.forItem(this, session.request, i, req.subPick)'),
    @($activity, 'switcher.goTo(i, itemTransition?.picks)'),
    @($sessionSource, 'if (subtitlePicksForItem != null) subPicks = subtitlePicksForItem'),
    @($sessionSource, 'P1ProductionSubtitles.savedSidecarTrackIndex(subPicks, files, list)'),
    @($sessionSource, 'if (saved != null && n < 0) return'),
    @($switcherSource, 'session.goTo(i, next, subtitlePicksForItem)'),
    @($unitSource, 'fun episodeTransitionsCannotInheritProductionOnOrOff()'),
    @($unitSource, 'fun sessionAppliesEachEpisodeChoiceWithoutDroppingResume()'),
    @($unitSource, 'fun savedSidecarWaitsForLateExternalTrackInsteadOfImpostorEmbeddedTrack()'),
    @($unitSource, 'fun offAndOtherChoicesAreNotReappliedWhenSavedSidecarArrivesLate()'),
    @($native, 'serverProfileId = o.optString("serverProfileId").ifEmpty { null }'),
    @($page, 'this.client?.profileId ? { serverProfileId: this.client.profileId }'),
    @($client, 'this.profileId = typeof cfg.id')
)
foreach ($entry in $assertions) {
    if (-not $entry[0].Contains($entry[1])) {
        throw ('STOP: G1 Production structural guard missing: ' + $entry[1])
    }
}
if ($helper.Contains('p1-g1c.register') -or
    $helper.Contains('p1-g1-external.vi.srt') -or
    $helper.Contains('P1G1CSubtitleRegistry') -or
    $activity.Contains('P1G1CSubtitleRegistry') -or
    $helper.Contains('putString("url') -or
    $helper.Contains('putString("uri') -or
    $helper.Contains('putString("hash')) {
    throw 'STOP: debug fixture or raw URL/URI/hash persistence in production patch'
}
$source = Join-Path $OmpRoot 'android\app\src'
foreach ($variant in @('debug','release')) {
    $path = Join-Path $source "$variant\java\com\spacesarmat\omp\player\P1ProductionSubtitles.kt"
    if (Test-Path -LiteralPath $path) {
        throw 'STOP: production registry must be in main Android source set only'
    }
}
foreach ($asset in @('p1-g1-external.vi.srt','p1-vietsub-utf8.srt')) {
    foreach ($set in @('main','debug','release')) {
        if (Test-Path -LiteralPath (Join-Path $source "$set\assets\$asset")) {
            throw 'STOP: debug-only SRT fixture found in APK assets'
        }
    }
}
$loadIndex = $activity.IndexOf('private fun load(r: PlayRequest')
$sessionIndex = $activity.IndexOf('session.load(production.request, next)', $loadIndex)
$hideIndex = $activity.IndexOf('hideMessage()', $sessionIndex)
$noticeIndex = $activity.IndexOf('production.warning?.let { showMessage(it, true) }', $hideIndex)
if ($loadIndex -lt 0 -or $sessionIndex -le $loadIndex -or
    $hideIndex -le $sessionIndex -or $noticeIndex -le $hideIndex) {
    throw 'STOP: warning must be shown after the player hides any previous message'
}
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: production source patch diff check failed' }
Write-Host 'G1PROD_STATIC_SOURCE_GUARDS_PASS_NOT_COMPILATION_OR_TV_PASS'
