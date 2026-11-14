"""Source-pinned P3 selected-media overlay on disposable P4 PlayerActivity.

Requires already composed G1+G2+P4 activity. All checks are source-only.
Never edits the running Android app, no Gradle/ADB, sockets or provider calls.
Default dry-run; --apply only on an EXPLICIT disposable source checkout.
"""
from __future__ import annotations

import argparse
from pathlib import Path

PKG = Path("android/app/src/main/java/com/spacesarmat/omp/player")
KOTLIN_FILE = "P3SelectedMediaPublisher.kt"
ACTIVITY_FILE = "PlayerActivity.kt"

LOAD = "        session.load(production.request, next)\n        flow.reset()"
ITEM = "        if (!switcher.goTo(i, itemTransition?.picks)) return\n        cancelCountdown()"
CLOSE = "        closedSent = true\n        commitPendingSeek()"
MENU = '        add("Hủy ghép đôi PC Vietsub AI", "AD01.12") {'
FIELD = "    private var g2Recovery: G2RefreshRecovery? = null"
CHOICE = ("        if (!closedSent && ::session.isInitialized) "
          "P1ProductionSubtitles.noteTrackChoice(this, session.request, index(), choice)")
TICK = """    /** Sample live PlayerSession + G1/P4 per-movie choice, not last Play packet. */
    private val p3StatusTick = object : Runnable {
        override fun run() {
            if (isFinishing || isDestroyed || closedSent ||
                !::session.isInitialized ||
                !P3SelectedMediaPublisher.enabled(applicationContext)) return
            P3SelectedMediaPublisher.sample(
                applicationContext, session.request, session.index,
                engine is VlcEngine)
            handler.postDelayed(this, 3_000L)
        }
    }

"""


P4_BUTTON = """        add(if (p4LanScope != null || p4ActivationInFlight)
                 "Tắt Vietsub AI" else "Bật Vietsub AI", "AD01.10") {
            if (p4LanScope != null) {
                stopP4LanSession()
                showMessage("Đã tắt Vietsub AI cho phim này.", false)
            } else if (p4ActivationInFlight) {
                p4ActivationGeneration++
                p4ActivationInFlight = false
                showMessage("Đã hủy yêu cầu Vietsub AI.", false)
            } else {
                beginP4Activation()
            }
        }
"""
P4_BUTTON_REQUEST = """        add(if (p4LanScope != null || p4ActivationInFlight ||
                (::session.isInitialized &&
                 P3SelectedMediaPublisher.viewerRequested(
                     applicationContext, session.request, index(),
                     engine is VlcEngine)))
                 "Tắt Vietsub AI" else "Bật Vietsub AI", "AD01.10") {
            val current = if (::session.isInitialized) session.request else null
            val waiting = current != null && P3SelectedMediaPublisher.viewerRequested(
                applicationContext, current, index(), engine is VlcEngine)
            if (p4LanScope != null || p4ActivationInFlight || waiting) {
                handler.removeCallbacks(p3ActivationTick)
                p3ActivationAttempts = 0
                p4ActivationGeneration++
                p4ActivationInFlight = false
                if (p4LanScope != null) stopP4LanSession()
                if (current != null) {
                    P3SelectedMediaPublisher.cancelViewer(
                        applicationContext, current, index(), engine is VlcEngine)
                    P3SelectedMediaPublisher.sample(
                        applicationContext, current, index(), engine is VlcEngine)
                }
                showMessage("Đã hủy Vietsub AI cho phim này.", false)
            } else {
                val allowed = P3SelectedMediaPublisher.requestViewer(
                    applicationContext, current, index(), engine is VlcEngine)
                if (allowed) {
                    p3ActivationAttempts = 0
                    handler.removeCallbacks(p3ActivationTick)
                    p3ActivationTick.run()
                    showMessage("Đang tìm phụ đề cho phim này...", false)
                } else {
                    showMessage("Hãy bật tín hiệu Vietsub và ghép PC trước.", true)
                }
            }
        }
"""

P3_RETRY = """    /** Bound only to explicit request, never to a native Play event. */
    private var p3ActivationAttempts = 0
    private val p3ActivationTick = object : Runnable {
        override fun run() {
            if (isFinishing || isDestroyed || closedSent || !::session.isInitialized ||
                engine !is VlcEngine || p4LanScope != null) return
            val playing = session.request ?: return
            if (!P3SelectedMediaPublisher.viewerRequested(
                    applicationContext, playing, index(), engine is VlcEngine)) return
            // Up to 30 min: P2 LEAN120 may process a full film. Existing
            // authenticated P4 activation is checked at most once per 15s.
            if (p3ActivationAttempts >= 120) {
                P3SelectedMediaPublisher.cancelViewer(
                    applicationContext, playing, index(), engine is VlcEngine)
                showMessage("Vietsub AI chưa sẵn sàng. Có thể bật lại.", true)
                return
            }
            if (!p4ActivationInFlight) {
                if (p3ActivationAttempts > 0) {
                    P3SelectedMediaPublisher.reaffirmViewer(
                        applicationContext, playing, index(), engine is VlcEngine)
                }
                p3ActivationAttempts++
                beginP4Activation()
            }
            handler.postDelayed(this, 15_000L)
        }
    }

"""

P4_PENDING_MESSAGE = """                if (result == null) {
                    showMessage("PC chưa sẵn sàng hoặc chưa có phụ đề nguồn cho phim.", true)
                    return@runOnUiThread
                }"""
P4_PENDING_REPLACEMENT = """                if (result == null) {
                    // Missing source is expected while the existing P2/D2
                    // pipeline runs. A bounded retry is owned by the user's
                    // still-current explicit request, not a new AI worker.
                    if (!P3SelectedMediaPublisher.viewerRequested(
                            applicationContext, r, idx, engine is VlcEngine)) {
                        showMessage("PC chưa sẵn sàng hoặc đã hủy Vietsub AI.", true)
                    }
                    return@runOnUiThread
                }"""
P4_SUCCESS = """                result.sessionSecret.fill(0)
                showMessage(
                    if (started) "Đã bật Vietsub AI. Đang chờ bản dịch đầu tiên..."
                    else "Phim đã đổi hoặc không thể bật Vietsub AI.", !started)"""
P4_SUCCESS_REPLACEMENT = """                result.sessionSecret.fill(0)
                if (started) {
                    handler.removeCallbacks(p3ActivationTick)
                    p3ActivationAttempts = 0
                    P3SelectedMediaPublisher.sample(
                        applicationContext, session.request, index(), engine is VlcEngine)
                }
                showMessage(
                    if (started) "Đã bật Vietsub AI. Đang chờ bản dịch đầu tiên..."
                    else "Phim đã đổi hoặc không thể bật Vietsub AI.", !started)"""

MENU_ROW = """        add(if (P3SelectedMediaPublisher.enabled(applicationContext))
                "Tắt tín hiệu tự tìm Vietsub" else "Bật tín hiệu tự tìm Vietsub",
                "AD01.13") {
            val want = !P3SelectedMediaPublisher.enabled(applicationContext)
            val ok = P3SelectedMediaPublisher.setEnabled(applicationContext, want)
            showMessage(
                if (!ok) "Cần ghép PC Vietsub AI trước."
                else if (want) "Đã bật tín hiệu chọn phim về PC."
                else "Đã tắt tín hiệu chọn phim về PC.",
                !ok,
            )
        }
"""


def patch_activity(text: str) -> str:
    if not isinstance(text, str) or (
        "P3SelectedMediaPublisher.accepted(" in text
        or "P3SelectedMediaPublisher.closed(" in text
    ):
        raise ValueError("P3_ACTIVITY_ALREADY_APPLIED")
    if (text.count("internal fun receiveP4Revision(") != 1
            or text.count("P4OwnerBootstrap.consume(applicationContext)") < 1
            or text.count('add("Hủy ghép đôi PC Vietsub AI"') != 1):
        raise ValueError("P3_REQUIRES_EXACT_P4_COMPOSED_SOURCE")
    rules = (
        (FIELD, TICK + P3_RETRY + FIELD),
        (CHOICE, CHOICE + """
        if (!choice.audio && ::session.isInitialized) {
            handler.removeCallbacks(p3ActivationTick)
            p3ActivationAttempts = 0
            P3SelectedMediaPublisher.cancelViewer(
                applicationContext, session.request, index(), engine is VlcEngine)
        }
        if (!closedSent && ::session.isInitialized) {
            P3SelectedMediaPublisher.sample(
                applicationContext, session.request, index(),
                engine is VlcEngine)
        }"""),
        (LOAD, """        session.load(production.request, next)
        P3SelectedMediaPublisher.accepted(
            applicationContext, session.request, session.index,
            "PLAY_REQUEST_ACCEPTED", engine is VlcEngine)
        handler.removeCallbacks(p3StatusTick)
        handler.postDelayed(p3StatusTick, 3_000L)
        flow.reset()"""),
        (ITEM, """        if (!switcher.goTo(i, itemTransition?.picks)) return
        P3SelectedMediaPublisher.accepted(
            applicationContext, session.request, session.index,
            "NEXT_QUEUE_ITEM_ACCEPTED", engine is VlcEngine)
        handler.removeCallbacks(p3StatusTick)
        handler.postDelayed(p3StatusTick, 3_000L)
        cancelCountdown()"""),
        (CLOSE, """        closedSent = true
        handler.removeCallbacks(p3StatusTick)
        handler.removeCallbacks(p3ActivationTick)
        p3ActivationAttempts = 0
        P3SelectedMediaPublisher.closed(applicationContext)
        commitPendingSeek()"""),
        (P4_BUTTON, P4_BUTTON_REQUEST),
        (P4_PENDING_MESSAGE, P4_PENDING_REPLACEMENT),
        (P4_SUCCESS, P4_SUCCESS_REPLACEMENT),
        (MENU, MENU_ROW + MENU),
    )
    for original, _ in rules:
        if text.count(original) != 1:
            raise ValueError("P3_SOURCE_ANCHOR_DRIFT")
    for original, updated in rules:
        text = text.replace(original, updated, 1)
    if text.count("P3SelectedMediaPublisher.accepted(") != 2:
        raise ValueError("P3_SOURCE_CALLBACK_COUNT_INVALID")
    if text.count("P3SelectedMediaPublisher.closed(") != 1:
        raise ValueError("P3_SOURCE_CLOSE_COUNT_INVALID")
    if (text.count("private val p3StatusTick =") != 1
            or text.count("P3SelectedMediaPublisher.sample(") != 4):
        raise ValueError("P3_SOURCE_STATE_SAMPLER_INVALID")
    if (text.count("private val p3ActivationTick =") != 1
            or text.count("P3SelectedMediaPublisher.requestViewer(") != 1
            or text.count("P3SelectedMediaPublisher.cancelViewer(") != 3
            or text.count("p3ActivationTick.run()") != 1):
        raise ValueError("P3_EXPLICIT_CONSENT_PATCH_INVALID")
    return text


def run(root: Path, *, apply: bool = False) -> str:
    if not isinstance(root, Path) or not root.is_absolute():
        raise ValueError("P3_EXPLICIT_ABSOLUTE_SOURCE_ROOT_REQUIRED")
    source = root / PKG
    needed = ["P4PinnedTls.kt", "P4PairingStore.kt", "P4LanClient.kt",
              "P4ActivationClient.kt", ACTIVITY_FILE]
    if not all((source / path).is_file() and not (source / path).is_symlink()
               for path in needed):
        raise ValueError("P3_REQUIRES_DISPOSABLE_P4_COMPOSED_CHECKOUT")
    target = source / ACTIVITY_FILE
    dest = source / KOTLIN_FILE
    if dest.exists() or dest.is_symlink():
        raise ValueError("P3_PUBLISHER_ALREADY_EXISTS")
    original = target.read_text(encoding="utf-8")
    updated = patch_activity(original)
    helper = (Path(__file__).resolve().parent / KOTLIN_FILE)
    if not helper.is_file() or helper.is_symlink():
        raise ValueError("P3_PINNED_PUBLISHER_SOURCE_MISSING")
    if "internal object P3SelectedMediaPublisher" not in helper.read_text("utf-8"):
        raise ValueError("P3_PINNED_PUBLISHER_INVALID")
    if not apply:
        return "P3_NATIVE_SOURCE_DRY_RUN_PASS"
    dest.write_bytes(helper.read_bytes())
    target.write_text(updated, encoding="utf-8")
    return "P3_NATIVE_SOURCE_APPLIED_DISPOSABLE_ONLY"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(run(args.source_root, apply=args.apply))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
