#!/usr/bin/env python3
"""G2 Refresh Vietsub candidate overlay for a disposable, previously G1-patched OMP tree.

Default dry-run. --apply is opt-in. Does NOT deploy an APK or touch a real TV.
"""
from __future__ import annotations
import argparse
import hashlib
from pathlib import Path
import re
import sys

PKG = Path('android/app/src/main/java/com/spacesarmat/omp/player')
G1_CLASS = 'P1ProductionSubtitles'

# Insert only in the G1 importSelected callback; leave all other player callback code untouched.
G2_CALLBACK = '''            runOnUiThread {
                if (isFinishing || isDestroyed || closedSent || !::session.isInitialized) return@runOnUiThread
                val current = session.request
                val nowKey = current?.let { P1ProductionSubtitles.mediaKey(it, index()) }
                if (!saved || g2Before == null) {
                    showMessage("Không thể cập nhật SRT/VTT UTF-8 an toàn khi đang phát.", true)
                } else if (current !== r || !G2RefreshDecision.matchesCurrent(
                        key, nowKey, idx, index(), engine is VlcEngine, closedSent)) {
                    showMessage("Đã lưu Vietsub. Phim đã đổi: mở lại để dùng.", false)
                } else {
                    val fresh = G2RefreshInPlace.prepare(applicationContext, current, idx)
                    if (fresh == null) {
                        g2Before.restoreOldFile()
                        showMessage("Đã lưu Vietsub. Mở lại phim để dùng.", false)
                    } else {
                        try {
                            commitPendingSeek()
                            val ms = engine.positionMs.coerceAtLeast(0L)
                            val wasPaused = !engine.playWhenReady
                            val selectedAudio = engine.audioTracks().firstOrNull { it.selected }
                            val audioPicks = selectedAudio?.let {
                                TrackPick.of(it.label?.trim().orEmpty(), it.language?.trim().orEmpty())
                            } ?: fresh.audioPick
                            val keptQueue = fresh.queue.mapIndexed { i, item ->
                                item.copy(resumeMs = session.resumeOf(i))
                            }
                            val refreshed = fresh.copy(queue = keptQueue, startAtMs = ms, audioPick = audioPicks)
                            val previous = current.copy(queue = current.queue.mapIndexed { i, item ->
                                item.copy(resumeMs = session.resumeOf(i))
                            }, startAtMs = ms, audioPick = audioPicks)
                            g2Before.arm(refreshed, previous, wasPaused)
                            g2Recovery = g2Before
                            session.load(refreshed)
                            if (wasPaused) engine.pause()
                            if (!wasPaused) handler.postDelayed(g2RecoveryTimeout, 25_000L)
                            showMessage("Đang nạp Vietsub mới...", false)
                        } catch (_: Exception) {
                            if (!rollbackG2Refresh()) {
                                showMessage("Đã lưu Vietsub, không thể nạp lúc đang phát. Mở lại phim.", true)
                            }
                        }
                    }
                }
            }
'''


def patch_activity(original: str) -> str:
    marker = 'P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)'
    if original.count(marker) != 1 or original.count('private val sidecarPicker') != 1:
        raise ValueError('G1_PICKER_ANCHOR_NOT_UNIQUE')
    # G1's original callback is the first runOnUiThread inside the importSelected Thread.
    at = original.index(marker)
    start = original.find('            runOnUiThread {', at)
    if start < 0:
        raise ValueError('G1_UI_CALLBACK_NOT_FOUND')
    end = original.find('\n        }.start()', start)
    if end < 0:
        raise ValueError('G1_UI_THREAD_SCOPE_NOT_FOUND')
    old = original[start:end]
    if 'G2RefreshInPlace' in original or 'G2RefreshRecovery' in original:
        raise ValueError('G2_ALREADY_PRESENT')
    if 'if (saved)' not in old or 'showMessage(' not in old:
        raise ValueError('UNEXPECTED_G1_IMPORT_CALLBACK')
    original_before_ui = original[:start]
    original_after_ui = original[end:]
    # Snapshot an identity-scoped old file BEFORE G1 deletes it during importSelected().
    import_anchor = '''            val saved = try {
                P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)'''
    import_patch = '''            val g2Before = G2RefreshRecovery.capture(applicationContext, r, idx)
            val saved = try {
                g2Before != null && P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)'''
    if original_before_ui.count(import_anchor) != 1:
        raise ValueError('G1_IMPORT_SNAPSHOT_ANCHOR_NOT_UNIQUE')
    original_before_ui = original_before_ui.replace(import_anchor, import_patch, 1)

    result = original_before_ui + G2_CALLBACK.rstrip('\n') + original_after_ui
    anchors = {
        'private var closedSent = false': '''private var closedSent = false
    private var g2Recovery: G2RefreshRecovery? = null
    private val g2RecoveryTimeout = Runnable { rollbackG2Refresh() }

    private fun clearG2Recovery() {
        handler.removeCallbacks(g2RecoveryTimeout)
        g2Recovery = null
    }

    /** Same-item, one-shot recovery; leaves imported new subtitles saved for the next open. */
    private fun rollbackG2Refresh(): Boolean {
        val pending = g2Recovery ?: return false
        if (!pending.matchesCurrent(session.request, index())) {
            clearG2Recovery()
            return false
        }
        clearG2Recovery() // prevent recursive fallback on a subsequent VLC error
        val restored = pending.restoreOldFile()
        val previous = pending.rollbackRequest(restored) ?: return false
        return try {
            session.load(previous)
            if (pending.wasPaused) engine.pause()
            showMessage(
                if (restored) "Đã phục hồi phát phim và phụ đề trước đó."
                else "Đã phục hồi phát phim, phụ đề cũ không khả dụng.", !restored)
            true
        } catch (_: Exception) {
            showMessage("Không thể phục hồi phiên phát. Mở lại phim.", true)
            false
        }
    }''',
        'override fun onFirstFrameShown() {': '''override fun onFirstFrameShown() {
        if (g2Recovery?.matchesCurrent(session.request, index()) == true) {
            clearG2Recovery()
            showMessage("Đã cập nhật Vietsub tại vị trí đang xem.", false)
        }''',
        'override fun engineFailed(kind: ErrorKind, detail: String, beforeFirstFrame: Boolean): Boolean {':
            '''override fun engineFailed(kind: ErrorKind, detail: String, beforeFirstFrame: Boolean): Boolean {
        if (rollbackG2Refresh()) return true''',
        'private fun load(r: PlayRequest, choose: Boolean = true) {':
            '''private fun load(r: PlayRequest, choose: Boolean = true) {
        clearG2Recovery()''',
        '        if (q == null || i !in q.indices || i == session.index) return':
            '''        if (q == null || i !in q.indices || i == session.index) return
        clearG2Recovery()''',
    }
    for anchor, patch in anchors.items():
        if result.count(anchor) != 1:
            raise ValueError('G2_RECOVERY_EVENT_ANCHOR_NOT_UNIQUE_' + anchor[:25])
        result = result.replace(anchor, patch, 1)
    return result


def run(root: Path, apply: bool) -> None:
    root = root.resolve(strict=True)
    if not root.is_dir() or not root.name.startswith('p1-g1-prod-'):
        raise ValueError('DISPOSABLE_G1_CHECKOUT_REQUIRED')
    src = root / PKG
    g1 = src / 'P1ProductionSubtitles.kt'
    activity = src / 'PlayerActivity.kt'
    if not g1.is_file() or not activity.is_file():
        raise ValueError('G1_PATCH_NOT_PRESENT')
    g1_bytes = g1.read_bytes()
    if G1_CLASS.encode() not in g1_bytes or b'fun importSelected(' not in g1_bytes:
        raise ValueError('INVALID_G1_HELPER')
    raw = activity.read_bytes()
    original = raw.decode('utf-8-sig')
    newline = '\r\n' if b'\r\n' in raw else '\n'
    patched = patch_activity(original.replace('\r\n', '\n')).replace('\n', newline)
    to_copy = [Path(__file__).with_name(n) for n in ('G2RefreshDecision.kt', 'G2RefreshInPlace.kt', 'G2RefreshRecovery.kt')]
    dest = [src / p.name for p in to_copy]
    if any(d.exists() for d in dest):
        raise ValueError('G2_FILE_ALREADY_PRESENT')
    for p in to_copy:
        if not p.is_file():
            raise ValueError('MISSING_SOURCE_FILE_' + p.name)
    old_hash = hashlib.sha256(raw).hexdigest()
    print(f'G2 preflight PASS, G1 PlayerActivity SHA256={old_hash}, dry_run={not apply}')
    if not apply:
        return
    # Only modify two new source files and one validated exact G1 caller.
    for origin, target in zip(to_copy, dest):
        target.write_bytes(origin.read_bytes())
    activity.write_bytes(('\ufeff' if raw.startswith(b'\xef\xbb\xbf') else '').encode('utf-8') + patched.encode('utf-8'))
    print(f'G2 SOURCE CANDIDATE applied: {activity}, {dest[0]}, {dest[1]}, {dest[2]}')
    print('NOT VERIFIED on Android/Redmi; run Gradle/unit and human G2 TV matrix separately.')


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--omp-root', type=Path, required=True)
    ap.add_argument('--apply', action='store_true', help='Explicitly update disposable G1-patched OMP source')
    args = ap.parse_args()
    try:
        run(args.omp_root, args.apply)
    except (ValueError, FileNotFoundError, UnicodeError, OSError) as e:
        print('G2_STOP: ' + str(e), file=sys.stderr)
        return 2
    return 0

if __name__ == '__main__':
    raise SystemExit(main())