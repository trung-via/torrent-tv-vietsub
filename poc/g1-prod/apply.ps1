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
$root = (& git -C $OmpRoot rev-parse --show-toplevel | Out-String).Trim()
$omp = (& git -C $OmpRoot rev-parse HEAD | Out-String).Trim()
$sub = (& git -C (Join-Path $OmpRoot 'android\vendor\2160player') rev-parse HEAD | Out-String).Trim()
$dirty = @(& git -C $OmpRoot status --porcelain --untracked-files=all)
if (-not $root.Equals($OmpRoot,[StringComparison]::OrdinalIgnoreCase) -or
    $omp -cne '52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f' -or
    $sub -cne '6ba6edd39f5d986ddfae29b5425b8ac0b319844e' -or
    $dirty.Count -ne 0 -or
    -not (Test-Path -LiteralPath (Join-Path $OmpRoot 'LICENSE') -PathType Leaf)) {
    throw 'STOP: source pins, Git root, license or clean worktree incorrect'
}
$paths = @(
 'src/api/torrserver.ts',
 'src/player/nativePlayer.ts',
 'android/app/src/main/java/com/spacesarmat/omp/player/NativePlayer.kt',
 'android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt'
)
$blobs = @(
 'a5019bcd5d801643194217289b705dabed280aeb',
 '3e5a69c47e68298135d88d902d2121292dee4bbd',
 '2b3a6ddb3a573849e860a734e4ec9c6505a20740',
 '8cb9598156b396ef49723275a7a847e75b7a36dd'
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
if (-not (Test-Path -LiteralPath $helper -PathType Leaf) -or (Test-Path -LiteralPath $dest)) {
    throw 'STOP: production source helper absent or duplicate'
}
$helperHash = (& git -C $AppRepoRoot hash-object -- $helper | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $helperHash -cne '2752a172812db8bf01f8c27e47a66eeeb07e9725') {
    throw 'STOP: source helper blob pin incorrect'
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
            showMessage("Đã đổi phim: không nhập phụ đề.", true)
            return@registerForActivityResult
        }
        Thread {
            val saved = try {
                P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)
            } catch (_: Exception) { false }
            runOnUiThread {
                if (!isFinishing && !isDestroyed) showMessage(
                    if (saved) "Đã lưu Vietsub. Mở lại phim để sử dụng."
                    else "Không thể đọc file SRT/VTT UTF-8.", !saved
                )
            }
        }.start()
    }
'@
$d = Once $d '    private lateinit var req: PlayRequest' (
    '    private lateinit var req: PlayRequest'+$nl+$picker.TrimEnd([char]13,[char]10))
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
            add("Chọn SRT/VTT rời...", "P1.1") { pickSidecar() }
            if (P1ProductionSubtitles.hasSaved(this, session.request, i)) {
                add("Xóa SRT/VTT đã lưu", "P1.2") {
                    if (i == index() && P1ProductionSubtitles.mediaKey(session.request, i) == prodKey &&
                        P1ProductionSubtitles.removeSaved(this, session.request, i)) {
                        showMessage("Đã xóa. Mở lại phim để áp dụng.", false)
                    }
                }
            }
        }
'@
$d = Once $d '        add(I18n.s("player.subsRow", "v" to sSel.label), "AD01.3") { openSubsList() }' (
    '        add(I18n.s("player.subsRow", "v" to sSel.label), "AD01.3") { openSubsList() }'+$nl+
    $menu.TrimEnd([char]13,[char]10))
$pickerMethod = @'
    /** Launches the user-facing Android file picker; never auto-imports torrent files. */
    private fun pickSidecar() {
        pendingSidecarKey = P1ProductionSubtitles.mediaKey(session.request, index())
        if (pendingSidecarKey == null) {
            showMessage("Chọn VLC và phim TorrServer có mã nhận dạng.", true)
            return
        }
        try {
            sidecarPicker.launch(arrayOf("text/plain", "text/vtt", "application/x-subrip", "*/*"))
        } catch (_: Exception) {
            pendingSidecarKey = null
            showMessage("Thiết bị không mở được trình chọn file.", true)
        }
    }

'@
$d = Once $d '    /** «Главы»: «время · название», the current one checked; a choice seeks to its start. */' (
    $pickerMethod+'    /** «Главы»: «время · название», the current one checked; a choice seeks to its start. */')
if ($d.Contains('P1G1CSubtitleRegistry') -or $d.Contains('P1G0SubtitleProbe')) {
    throw 'STOP: cannot stack production source over debug PoC'
}
# All patch anchors checked before writing: disposable OMP checkout only.
$utf8 = [Text.UTF8Encoding]::new($false)
$patched = @($a,$b,$c,$d)
for ($i=0; $i -lt $paths.Count; $i++) {
    [IO.File]::WriteAllText((Join-Path $OmpRoot $paths[$i]),$patched[$i],$utf8)
}
Copy-Item -LiteralPath $helper -Destination $dest
& git -C $OmpRoot diff --check
if ($LASTEXITCODE -ne 0) { throw 'STOP: patch diff failed' }
Write-Host 'G1PROD_SOURCE_PATCH_APPLIED_NOT_BUILT_OR_TV_PASS'
