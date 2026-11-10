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
                if (!saved) {
                    showMessage("Không thể đọc SRT/VTT UTF-8.", true)
                } else if (current !== r || !G2RefreshDecision.matchesCurrent(
                        key, nowKey, idx, index(), engine is VlcEngine, closedSent)) {
                    showMessage("Đã lưu Vietsub. Phim đã đổi: mở lại để dùng.", false)
                } else {
                    val fresh = G2RefreshInPlace.prepare(applicationContext, current!!, idx)
                    if (fresh == null) {
                        showMessage("Đã lưu Vietsub. Mở lại phim để dùng.", false)
                    } else {
                        try {
                            // Keep the same PlayerActivity, queue item and playback timestamp.
                            // VLC may buffer briefly because the current engine's media is reopened.
                            commitPendingSeek()
                            val ms = engine.positionMs.coerceAtLeast(0L)
                            val wasPaused = !engine.playWhenReady
                            val selectedAudio = engine.audioTracks().firstOrNull { it.selected }
                            val audioPicks = selectedAudio?.let {
                                TrackPick.of(it.label?.trim().orEmpty(), it.language?.trim().orEmpty())
                            } ?: fresh.audioPick
                            // Do not discard queue resume positions established since this playback began.
                            val keptQueue = fresh.queue.mapIndexed { i, item ->
                                item.copy(resumeMs = session.resumeOf(i))
                            }
                            session.load(fresh.copy(queue = keptQueue, startAtMs = ms, audioPick = audioPicks))
                            if (wasPaused) engine.pause()
                            showMessage("Đã cập nhật Vietsub tại vị trí đang xem.", false)
                        } catch (_: Exception) {
                            showMessage("Đã lưu Vietsub; không thể nạp lúc đang phát. Mở lại phim.", true)
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
    if 'G2RefreshInPlace' in original:
        raise ValueError('G2_ALREADY_PRESENT')
    if 'if (saved)' not in old or 'showMessage(' not in old:
        raise ValueError('UNEXPECTED_G1_IMPORT_CALLBACK')
    # Keep the final newline expected by the G1 Thread's .start() delimiter.
    return original[:start] + G2_CALLBACK.rstrip('\n') + original[end:]


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
    to_copy = [Path(__file__).with_name(n) for n in ('G2RefreshDecision.kt', 'G2RefreshInPlace.kt')]
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
    print(f'G2 SOURCE CANDIDATE applied: {activity}, {dest[0]}, {dest[1]}')
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