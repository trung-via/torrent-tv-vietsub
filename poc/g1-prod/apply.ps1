# G1 Production source-only patch. Requires clean disposable OMP at exact upstream pin.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OmpRoot,
      [string]$AppRepoRoot = (Join-Path $PSScriptRoot '..\..'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$OmpRoot = (Resolve-Path -LiteralPath $OmpRoot).Path
$AppRepoRoot = (Resolve-Path -LiteralPath $AppRepoRoot).Path
if ((Split-Path -Path $OmpRoot -Leaf) -notlike 'p1-g1-prod-*') {
    throw 'STOP: apply only to a dedicated disposable p1-g1-prod-* checkout'
}
if (-not [IO.Path]::GetFullPath($AppRepoRoot).TrimEnd('\').Equals(
        [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: script repository root does not match reviewed source tree'
}
if ($env:GITHUB_ACTIONS -eq 'true') {
    if ($env:GITHUB_REPOSITORY -cne 'trung-via/torrent-tv-vietsub' -or
        $env:RUNNER_NAME -cne 'torrent-tv-vietsub-win' -or
        $env:RUNNER_OS -cne 'Windows' -or -not $env:RUNNER_TEMP) {
        throw 'STOP: wrong dedicated runner'
    }
    $tempRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    $actualRoot = [IO.Path]::GetFullPath($OmpRoot).TrimEnd('\') + '\'
    if (-not $actualRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'STOP: expected disposable runner-temp source'
    }
}
# Git for Windows may print C:/... while Resolve-Path emits C:\...
# Normalize only separators and trailing separators; keep all pinned/clean checks fail-closed.
$root = (& git -C $OmpRoot rev-parse --show-toplevel | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
    throw 'STOP: failed to resolve upstream Git root'
}
$normalizedRoot = [IO.Path]::GetFullPath($root.Replace('/', '\')).TrimEnd([char[]]@(92,47))
$normalizedExpectedRoot = [IO.Path]::GetFullPath($OmpRoot).TrimEnd([char[]]@(92,47))
if (-not $normalizedRoot.Equals($normalizedExpectedRoot,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'STOP: Git root does not match disposable upstream checkout'
}
$omp = (& git -C $OmpRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $omp -cne '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f') {
    throw 'STOP: pinned OMP commit mismatch'
}
$sub = (& git -C (Join-Path $OmpRoot 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $sub -cne '6ba6edd39f5d986ddfae29b5425b8ac0b319844e') {
    throw 'STOP: pinned 2160player submodule commit mismatch'
}
$dirty = @(& git -C $OmpRoot status --porcelain --untracked-files=all)
if ($LASTEXITCODE -ne 0) { throw 'STOP: upstream Git status failed' }
if ($dirty.Count -ne 0) { throw 'STOP: disposable OMP worktree not clean' }
if (-not (Test-Path -LiteralPath (Join-Path $OmpRoot 'LICENSE') -PathType Leaf)) {
    throw 'STOP: pinned OMP license absent'
}
Write-Host 'G1PROD_NORMALIZED_UPSTREAM_ROOT_AND_CLEAN_PINS_PASS'
$paths = @(
 'src/api/torrserver.ts',
 'src/player/nativePlayer.ts',
 'android/app/src/main/java/com/spacesarmat/omp/player/NativePlayer.kt',
 'android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt',
 'android/app/src/main/java/com/spacesarmat/omp/player/EngineSwitcher.kt',
 'android/app/src/main/java/com/spacesarmat/omp/player/PlayerSession.kt'
)
$blobs = @(
 'a5019bcd5d801643194217289b705dabed280aeb',
 '3e5a69c47e68298135d88d902d2121292dee4bbd',
 '2b3a6ddb3a573849e860a734e4ec9c6505a20740',
 '8cb9598156b396ef49723275a7a847e75b7a36dd',
 'f23785f5b140a4c3a086f107c86bdb3d233e9814',
 '58a42a629c28643f608db1141397bbe40c62cf8f'
)
$src = @()
for ($i=0; $i -lt $paths.Count; $i++) {
    $full = Join-Path $OmpRoot $paths[$i]
    $sha = (& git -C $OmpRoot hash-object -- $paths[$i] | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -cne $blobs[$i]) {
        throw 'STOP: upstream source blob drift'
    }
    $src += [IO.File]::ReadAllText($full)
}
$helper = Join-Path $PSScriptRoot 'P1ProductionSubtitles.kt'
$dest = Join-Path $OmpRoot 'android/app/src/main/java/com/spacesarmat/omp/player/P1ProductionSubtitles.kt'
$test = Join-Path $PSScriptRoot 'P1ProductionSubtitlesTest.kt'
$testDest = Join-Path $OmpRoot 'android/app/src/test/java/com/spacesarmat/omp/player/P1ProductionSubtitlesTest.kt'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf) -or (Test-Path -LiteralPath $dest) -or
    -not (Test-Path -LiteralPath $test -PathType Leaf) -or (Test-Path -LiteralPath $testDest)) {
    throw 'STOP: production source helper absent or duplicate'
}
$helperHash = (& git -C $AppRepoRoot hash-object -- $helper | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $helperHash -cne 'cdcfecced9325ef7cc5ac60f0168c625050b27ec') {
    throw 'STOP: source helper blob pin incorrect'
}
$testHash = (& git -C $AppRepoRoot hash-object -- $test | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $testHash -cne '1316e3d71034c7b43f57f93a25f3d894773b878b') {
    throw 'STOP: G1 Production unit test blob pin incorrect'
}
function Once([string]$s,[string]$old,[string]$replacement) {
    if (-not $s.Contains($old) -or $s.IndexOf($old) -ne $s.LastIndexOf($old)) {
        throw 'STOP: missing/ambiguous upstream source anchor'
    }
    return $s.Replace($old,$replacement)
}
$nl = [Environment]::NewLine
$a = $src[0]
$a = Once $a 'export interface ServerConfig {' ('export interface ServerConfig {'+$nl+'  id?: string;')
$a = Once $a '  readonly baseUrl: string;' ('  readonly baseUrl: string;'+$nl+'  readonly profileId?: string;')
$a = Once $a '    this.cfg = cfg;' ('    this.cfg = cfg;'+$nl+"    this.profileId = typeof cfg.id === 'string' && /^[A-Za-z0-9_-]{1,80}$/.test(cfg.id) ? cfg.id : undefined;")
$b = Once $src[1] '        return this.plugin.playNative({' (
    '        return this.plugin.playNative({'+$nl+'          ...(this.client?.profileId ? { serverProfileId: this.client.profileId } : {}),')
$c = Once $src[2] '    val testPx: Int = 0,' ('    val testPx: Int = 0,'+$nl+'    val serverProfileId: String? = null,')
$c = Once $c '                testPx = o.optInt("testPx", 0),' (
    '                testPx = o.optInt("testPx", 0),'+$nl+'                serverProfileId = o.optString("serverProfileId").ifEmpty { null },')
$d = Once $src[3] 'import android.content.Intent' ('import android.content.Intent'+$nl+'import android.net.Uri')
$d = Once $d 'import androidx.activity.OnBackPressedCallback' (
    'import androidx.activity.OnBackPressedCallback'+$nl+'import androidx.activity.result.contract.ActivityResultContracts')
$picker = @'
    private var pendingSidecarKey: String? = null
    private val sidecarPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        val key = pendingSidecarKey
        pendingSidecarKey = null
        if (uri == null || key == null || closedSent || !::session.isInitialized) return@registerForActivityResult
        val r = session.request ?: return@registerForActivityResult
        val idx = index()
        if (P1ProductionSubtitles.mediaKey(r, idx) != key) {
            showMessage("\u0110\u00e3 \u0111\u1ed5i phim: kh\u00f4ng nh\u1eadp ph\u1ee5 \u0111\u1ec1.", true)
            return@registerForActivityResult
        }
        Thread {
            val saved = try {
                P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)
            } catch (_: Exception) { false }
            runOnUiThread {
                if (!isFinishing && !isDestroyed) showMessage(
                    if (saved) "\u0110\u00e3 l\u01b0u Vietsub. M\u1edf l\u1ea1i phim \u0111\u1ec3 s\u1eed d\u1ee5ng."
                    else "Kh\u00f4ng th\u1ec3 \u0111\u1ecdc file SRT/VTT UTF-8.", !saved
                )
            }
        }.start()
    }
'@
$d = Once $d '    private lateinit var req: PlayRequest' (
    '    private lateinit var req: PlayRequest'+$nl+$picker.TrimEnd([char[]]@(13,10)))
$d = Once $d '        session.load(r, next)' (
    '        val production = P1ProductionSubtitles.prepare(this, r)'+$nl+'        session.load(production.request, next)')
$d = Once $d '        setDonate(r.donate)' (
    '        setDonate(r.donate)'+$nl+'        production.warning?.let { showMessage(it, true) }')
$d = Once $d '    override fun trackChosen(choice: TrackChoice) {' (
    '    override fun trackChosen(choice: TrackChoice) {'+$nl+
    '        if (!closedSent && ::session.isInitialized) P1ProductionSubtitles.noteTrackChoice(this, session.request, index(), choice)')
$menu = @'
        val prodKey = P1ProductionSubtitles.mediaKey(session.request, i)
        if (prodKey != null) {
            add("Ch\u1ecdn SRT/VTT r\u1eddi...", "P1.1") { pickSidecar() }
            if (P1ProductionSubtitles.hasSaved(this, session.request, i)) {
                add("X\u00f3a SRT/VTT \u0111\u00e3 l\u01b0u", "P1.2") {
                    if (i == index() && P1ProductionSubtitles.mediaKey(session.request, i) == prodKey &&
                        P1ProductionSubtitles.removeSaved(this, session.request, i)) {
                        showMessage("\u0110\u00e3 x\u00f3a. M\u1edf l\u1ea1i phim \u0111\u1ec3 \u00e1p d\u1ee5ng.", false)
                    }
                }
            }
        }
'@
$d = Once $d '        add(I18n.s("player.subsRow", "v" to sSel.label), "AD01.3") { openSubsList() }' (
    '        add(I18n.s("player.subsRow", "v" to sSel.label), "AD01.3") { openSubsList() }'+$nl+
    $menu.TrimEnd([char[]]@(13,10)))
$pickerMethod = @'
    /** Launches the user-facing Android file picker; never auto-imports torrent files. */
    private fun pickSidecar() {
        pendingSidecarKey = P1ProductionSubtitles.mediaKey(session.request, index())
        if (pendingSidecarKey == null) {
            showMessage("Ch\u1ecdn VLC v\u00e0 phim TorrServer c\u00f3 m\u00e3 nh\u1eadn d\u1ea1ng.", true)
            return
        }
        try {
            sidecarPicker.launch(arrayOf("text/plain", "text/vtt", "application/x-subrip", "*/*"))
        } catch (_: Exception) {
            pendingSidecarKey = null
            showMessage("Thi\u1ebft b\u1ecb kh\u00f4ng m\u1edf \u0111\u01b0\u1ee3c tr\u00ecnh ch\u1ecdn file.", true)
        }
    }

'@
$d = Once $d '    private fun openChapters(item: Int, now: Long) {' (
    $pickerMethod+'    private fun openChapters(item: Int, now: Long) {')
$d = Once $d '        if (!switcher.goTo(i)) return' (
    '        val itemTransition = if (P1ProductionSubtitles.hasAnySaved(this, req))'+$nl+
    '            P1ProductionSubtitles.forItem(this, session.request, i, req.subPick) else null'+$nl+
    '        if (!switcher.goTo(i, itemTransition?.picks)) return')
$d = Once $d '        if (undoStart != null) hideMessage()' (
    '        if (undoStart != null) hideMessage()'+$nl+
    '        itemTransition?.warning?.let { showMessage(it, true) }')
$e = Once $src[4] '    fun goTo(i: Int): Boolean {' (
    '    fun goTo(i: Int, subtitlePicksForItem: List<TrackPick>? = null): Boolean {')
$e = Once $e '        session.goTo(i, next)' '        session.goTo(i, next, subtitlePicksForItem)'
$f = Once $src[5] '    fun goTo(i: Int, next: PlayerEngine? = null): Boolean {' (
    '    fun goTo(i: Int, next: PlayerEngine? = null, subtitlePicksForItem: List<TrackPick>? = null): Boolean {')
$f = Once $f '        pendingSub = carried?.second?.takeIf { it.external == null }' (
    '        pendingSub = if (subtitlePicksForItem != null) null else carried?.second?.takeIf { it.external == null }'+$nl+
    '        if (subtitlePicksForItem != null) subPicks = subtitlePicksForItem')
if ($d.Contains('P1G1CSubtitleRegistry') -or $d.Contains('P1G0SubtitleProbe')) {
    throw 'STOP: cannot stack production source over debug PoC'
}
# All patch anchors checked before writing: disposable OMP checkout only.
$utf8 = [Text.UTF8Encoding]::new($false)
$patched = @($a,$b,$c,$d,$e,$f)
for ($i=0; $i -lt $paths.Count; $i++) {
    [IO.File]::WriteAllText((Join-Path $OmpRoot $paths[$i]),$patched[$i],$utf8)
}
Copy-Item -LiteralPath $helper -Destination $dest
Copy-Item -LiteralPath $test -Destination $testDest
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: patch diff failed' }
Write-Host 'G1PROD_SOURCE_PATCH_APPLIED_NOT_BUILT_OR_TV_PASS'
