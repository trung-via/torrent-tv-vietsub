# Structural guard only, not a compiler or a real-device test.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path -LiteralPath $OmpRoot).Path
$src = Join-Path $root 'android\app\src'
$activity = Get-Content -LiteralPath (Join-Path $src 'main\java\com\spacesarmat\omp\player\PlayerActivity.kt') -Raw -Encoding UTF8
$native = Get-Content -LiteralPath (Join-Path $src 'main\java\com\spacesarmat\omp\player\NativePlayer.kt') -Raw -Encoding UTF8
$debug = Get-Content -LiteralPath (Join-Path $src 'debug\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt') -Raw -Encoding UTF8
$release = Get-Content -LiteralPath (Join-Path $src 'release\java\com\spacesarmat\omp\player\P1G1CSubtitleRegistry.kt') -Raw -Encoding UTF8
$client = Get-Content -LiteralPath (Join-Path $root 'src\api\torrserver.ts') -Raw -Encoding UTF8
$page = Get-Content -LiteralPath (Join-Path $root 'src\player\nativePlayer.ts') -Raw -Encoding UTF8

foreach ($entry in @(
    @($activity, 'val g1cPrepared = P1G1CSubtitleRegistry.prepare(this, r)'),
    @($activity, 'session.load(g1cPrepared.request, next)'),
    @($activity, 'g1cPrepared.warning?.let { showMessage(it, true) }'),
    @($native, 'val serverProfileId: String? = null'),
    @($native, 'serverProfileId = o.optString("serverProfileId").ifEmpty { null }'),
    @($client, 'readonly profileId?: string;'),
    @($client, 'this.profileId = typeof cfg.id'),
    @($page, 'this.client?.profileId ? { serverProfileId: this.client.profileId }'),
    @($debug, 'p1-g1c.register'),
    @($debug, 'p1-g1-external.vi.srt'),
    @($debug, 'private fun key(server: String?, hash: String?, fileIndex: Int?)'),
    @($debug, 'val registrationKey = key(r.serverProfileId, current.hash, current.fileIndex)'),
    @($debug, 'prefs.edit().putString(registrationKey, checksum).commit()'),
    @($debug, 'if (prefs.getString(mediaKey, null) != currentChecksum) continue'),
    @($debug, 'if (!marker.delete()) return Prepared(r)'),
    @($debug, 'CodingErrorAction.REPORT'),
    @($activity, 'P1G1CSubtitleRegistry.noteTrackChoice(this, session.request, index(), choice)'),
    @($debug, 'fun noteTrackChoice(context: Context, r: PlayRequest?, index: Int, choice: TrackChoice)'),
    @($debug, 'if (prefs.getString(mediaKey, null) != checksum) return'),
    @($debug, 'choice.off -> "off"'),
    @($debug, 'choice.label == LABEL -> "on"'),
    @($debug, 'putString("selection.$mediaKey", value)'),
    @($debug, 'prefs.getString("selection.$selectedKey", null)'),
    @($debug, 'TrackPick(label = LABEL)'),
    @($debug, 'TrackPick(off = true)'),
    @($debug, 'selected.subtitles.none { it.label == LABEL && it.url == uri }'),
    @($debug, 'if (!found) return Prepared(r, warning)'),
    @($debug, 'val registrationKey = key(r.serverProfileId, current.hash, current.fileIndex)'),
    @($debug, 'val registering = marker.isFile'),
    @($debug, 'val warnEligible = !registering && savedChecksum != null &&'),
    @($debug, 'prefs.getString("selection.$registrationKey", null) == "on"'),
    @($debug, 'val warning = if (warnEligible && savedChecksum != currentChecksum) SRT_UNAVAILABLE else null'),
    @($debug, 'if (currentChecksum == null) return Prepared(r, warning)'),
    @($debug, 'private const val SRT_UNAVAILABLE = "')
)) {
    if (-not $entry[0].Contains($entry[1])) {
        throw "STOP: missing G1c safety guard: $($entry[1])"
    }
}
if (-not $release.Contains('fun noteTrackChoice(') -or
    -not $release.Contains('Prepared(r)') -or
    $release.Contains('getSharedPreferences') -or $release.Contains('Uri.fromFile') -or
    $release.Contains('SRT_UNAVAILABLE') -or $release.Contains('FILE_NAME') -or
    $release.Contains('filesDir')) {
    throw 'STOP: G1c release is not no-op'
}
# Native player must display the warning after load() hides the prior toast.
$loadAt = $activity.IndexOf('private fun load(r: PlayRequest')
if ($loadAt -lt 0) { throw 'STOP: native player load entry missing' }
$sessionAt = $activity.IndexOf('session.load(g1cPrepared.request, next)', $loadAt)
if ($sessionAt -lt 0) { throw 'STOP: prepared request not passed to session' }
$hideAt = $activity.IndexOf('hideMessage()', $sessionAt)
if ($hideAt -lt 0) { throw 'STOP: native toast reset missing' }
$showAt = $activity.IndexOf('g1cPrepared.warning?.let { showMessage(it, true) }', $hideAt)
if ($showAt -lt 0 -or $showAt -le $hideAt) {
    throw 'STOP: subtitle UX warning not ordered after session load and toast reset'
}
# A warning cannot be returned merely because any SRT file was invalid:
# the helper must have checked the specific key and explicit ON state.
if (-not $debug.Contains('val savedChecksum = registrationKey?.let { prefs.getString(it, null) }') -or
    -not $debug.Contains('if (r.engine != EngineMode.VLC || r.index !in r.queue.indices) return Prepared(r)') -or
    -not $debug.Contains('val warning = if (warnEligible && savedChecksum != currentChecksum) SRT_UNAVAILABLE else null')) {
    throw 'STOP: subtitle UX notice gate missing'
}
foreach ($asset in @('p1-g1-external.vi.srt', 'p1-vietsub-utf8.srt')) {
    foreach ($set in @('main','debug','release')) {
        if (Test-Path -LiteralPath (Join-Path $src "$set\assets\$asset")) {
            throw "STOP: unexpected SRT in APK assets"
        }
    }
}
& git -C $root diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: git diff --check' }
Write-Host 'G1C_UX_STATIC_GUARDS_PASS; KOTLIN_TYPESCRIPT_BUILD_UNVERIFIED'
Write-Host 'G1D_UX_REAL_TV_UNVERIFIED; G1C_TRACK_SELECTION_REGRESSION_UNVERIFIED; G4_RELEASE_ARTIFACT_UNVERIFIED'
