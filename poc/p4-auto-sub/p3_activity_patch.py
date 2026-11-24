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
MENU = '            add("Ngắt ghép đôi PC Vietsub AI (nâng cao)", "AD01.12") {'
FIELD = "    private var g2Recovery: G2RefreshRecovery? = null"
CHOICE = ("        if (!closedSent && ::session.isInitialized) "
          "P1ProductionSubtitles.noteTrackChoice(this, session.request, index(), choice)")
TICK = """    /** Sample live PlayerSession + G1/P4 per-movie choice, not last Play packet. */
    private val p3StatusTick = object : Runnable {
        override fun run() {
            if (isFinishing || isDestroyed || closedSent ||
                !::session.isInitialized) return
            // Keep the timer alive while sharing is OFF. If Vietsub AI is
            // enabled mid-playback, the next tick MUST resume fresh signed
            // TV status; an 8-second Owner TTL cannot survive a 15-second
            // P4 activation/reaffirmation interval on its own.
            if (P3SelectedMediaPublisher.enabled(applicationContext)) {
                P3SelectedMediaPublisher.sample(
                    applicationContext, session.request, session.index,
                    engine is VlcEngine)
            }
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
                cancelP3ViewerAndP4(current)
                showMessage("Đã hủy Vietsub AI cho phim này.", false)
            } else {
                // Import ONLY a previously authorized private ADB bootstrap;
                // this does not trust a new PC, open a listener or bypass TLS.
                P4OwnerBootstrap.consume(applicationContext)
                val enabled = P3SelectedMediaPublisher.enabled(applicationContext) ||
                    P3SelectedMediaPublisher.setEnabled(applicationContext, true)
                val selectedIndex = index()
                val allowed = enabled && P3SelectedMediaPublisher.requestViewer(
                    applicationContext, current, selectedIndex, engine is VlcEngine
                ) { acknowledged ->
                    showP3Delivery(current, selectedIndex, acknowledged)
                }
                if (allowed) {
                    p3ActivationAttempts = 0
                    p3LastDelivery = null
                    handler.removeCallbacks(p3ActivationTick)
                    p3ActivationTick.run()
                    showMessage("Đang gửi yêu cầu tìm Vietsub cho phim này đến PC...", false)
                } else {
                    showMessage("Không thể gửi: kiểm tra ghép PC an toàn và phim VLC.", true)
                }
            }
        }
"""

P4_SOURCE_MENU = """        add("Vietsub AI (mặc định)", "AD01.14") {
            switchP4SubtitleSource(downloadedVi = false)
        }
"""

P4_SWITCH_SOURCE = """    /** Switch only after a new source-specific, signed P4 activation. */
    private fun switchP4SubtitleSource(downloadedVi: Boolean) {
        if (p4ActivationInFlight || closedSent || isFinishing || isDestroyed ||
            !::session.isInitialized || engine !is VlcEngine) return
        val r = session.request ?: return
        val idx = index()
        if (!P3SelectedMediaPublisher.viewerRequested(
                applicationContext, r, idx, engine is VlcEngine)) {
            showMessage("Hãy bật Vietsub AI cho phim này trước.", true)
            return
        }
        val media = P1ProductionSubtitles.mediaKey(r, idx) ?: return
        val device = P4PairingStore(applicationContext).load() ?: run {
            showMessage("Laptop chưa được kết nối an toàn.", true)
            return
        }
        p4ActivationInFlight = true
        val gen = ++p4ActivationGeneration
        Thread {
            val result = try {
                if (downloadedVi) P4ActivationClient.activateDownloadedVi(
                    device.host, device.port, media,
                    device.deviceSecret, device.certPinSha256)
                else P4ActivationClient.activate(
                    device.host, device.port, media,
                    device.deviceSecret, device.certPinSha256)
            } catch (_: Exception) { null }
            device.deviceSecret.fill(0)
            runOnUiThread {
                if (gen != p4ActivationGeneration) {
                    result?.sessionSecret?.fill(0)
                    return@runOnUiThread
                }
                p4ActivationInFlight = false
                if (result == null) {
                    showMessage(if (downloadedVi)
                        "Chưa có phụ đề Việt tải sẵn cho phim này."
                        else "Vietsub AI chưa sẵn sàng.", true)
                    return@runOnUiThread
                }
                val same = !closedSent && !isFinishing && !isDestroyed &&
                    ::session.isInitialized && session.request === r &&
                    index() == idx && engine is VlcEngine &&
                    P1ProductionSubtitles.mediaKey(r, idx) == media &&
                    P3SelectedMediaPublisher.viewerRequested(
                        applicationContext, r, idx, engine is VlcEngine)
                var started = false
                if (same) {
                    // No P4 session is destroyed until the replacement is
                    // authenticated; old subtitles remain if it is absent.
                    unbindP4Session()
                    started = startP4LanSession(
                        device.host, device.port, result.sessionId,
                        result.sourceSha256, result.sessionSecret,
                        device.certPinSha256)
                }
                result.sessionSecret.fill(0)
                showMessage(if (started) {
                    if (downloadedVi) "Đang nạp Vietsub có sẵn (có thể lệch)..."
                    else "Đã chọn Vietsub AI. Đang chờ bản dịch..."
                } else "Phim đã đổi hoặc không thể đổi phụ đề.", !started)
            }
        }.start()
    }

"""

P3_RETRY = """    /** Bound only to explicit request, never to a native Play event. */
    private var p3ActivationAttempts = 0
    private var p3LastDelivery: Boolean? = null

    /** OFF and ORIGINAL share the same film-scoped cancellation. */
    private fun cancelP3ViewerAndP4(current: PlayRequest?) {
        handler.removeCallbacks(p3ActivationTick)
        p3ActivationAttempts = 0
        p3LastDelivery = null
        p4ActivationGeneration++
        p4ActivationInFlight = false
        if (p4LanScope != null) stopP4LanSession()
        if (current != null) {
            P3SelectedMediaPublisher.cancelViewer(
                applicationContext, current, index(), engine is VlcEngine)
            P3SelectedMediaPublisher.sample(
                applicationContext, current, index(), engine is VlcEngine)
        }
        // The one movie-scoped button owns both signal and request.
        // Clearing the global signal on OFF never implies an AI call.
        P3SelectedMediaPublisher.setEnabled(applicationContext, false)
    }

    /** HTTP 204 is a P3 signal receipt, NOT a claim that P2 has finished. */
    private fun showP3Delivery(
        expected: PlayRequest?, expectedIndex: Int, acknowledged: Boolean,
    ) {
        runOnUiThread {
            if (isFinishing || isDestroyed || closedSent || !::session.isInitialized ||
                p4LanScope != null || session.request !== expected ||
                index() != expectedIndex ||
                !P3SelectedMediaPublisher.viewerRequested(
                    applicationContext, expected, expectedIndex, engine is VlcEngine)
            ) return@runOnUiThread
            if (p3LastDelivery == acknowledged) return@runOnUiThread
            p3LastDelivery = acknowledged
            showMessage(
                if (acknowledged) "PC đã nhận tín hiệu tìm Vietsub. Đang chờ phụ đề..."
                else "PC chưa xác nhận yêu cầu Vietsub. Sẽ tự thử lại.",
                !acknowledged)
        }
    }

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
                    val selectedIndex = index()
                    P3SelectedMediaPublisher.reaffirmViewer(
                        applicationContext, playing, selectedIndex, engine is VlcEngine
                    ) { acknowledged ->
                        showP3Delivery(playing, selectedIndex, acknowledged)
                    }
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
P4_CONNECTING_MESSAGE = '        showMessage("Đang kết nối Vietsub AI với PC...", false)'
P4_CONNECTING_REPLACEMENT = """        // The one-tap P3 request already displayed progress. P4 polls for
        // source readiness in the background; it is NOT reconnecting the PC.
        if (!P3SelectedMediaPublisher.viewerRequested(
                applicationContext, r, idx, engine is VlcEngine)) {
            showMessage("Đang kết nối Vietsub AI với PC...", false)
        }"""
P4_PENDING_REPLACEMENT = """                if (result == null) {
                    android.util.Log.i("TorrentTV-Vietsub", "P4_TV_ACTIVATE_NOT_READY")
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
                    android.util.Log.i("TorrentTV-Vietsub", "P4_TV_SESSION_ACCEPTED")
                    handler.removeCallbacks(p3ActivationTick)
                    p3ActivationAttempts = 0
                    P3SelectedMediaPublisher.sample(
                        applicationContext, session.request, index(), engine is VlcEngine)
                }
                showMessage(
                    if (started) "Đã bật Vietsub AI. Đang chờ bản dịch đầu tiên..."
                    else "Phim đã đổi hoặc không thể bật Vietsub AI.", !started)"""

P4_FIRST_FRAME = """        if (!acknowledged) return false
        // Only after the persisted first-frame ACK is this new registry valid."""
P4_FIRST_FRAME_REPLACEMENT = """        if (!acknowledged) return false
        android.util.Log.i("TorrentTV-Vietsub", "P4_TV_G2_FIRST_FRAME_ACK")
        // Only after the persisted first-frame ACK is this new registry valid."""

P4_OFFER = """        val choice = P1ProductionSubtitles.automaticChoice(applicationContext, r, idx)
        return try {
            receiver.receive("""
P4_OFFER_REPLACEMENT = """        val choice = P1ProductionSubtitles.automaticChoice(applicationContext, r, idx)
        android.util.Log.i("TorrentTV-Vietsub", "P4_TV_OFFER_RECEIVED_UNVERIFIED")
        return try {
            receiver.receive("""

P4_REVOKE = """                stopP4LanSession()
                val revoked = P4PairingStore(applicationContext).revoke()"""
P4_REVOKE_REQUEST = """                handler.removeCallbacks(p3ActivationTick)
                p3ActivationAttempts = 0
                p4ActivationGeneration++
                p4ActivationInFlight = false
                if (::session.isInitialized) {
                    P3SelectedMediaPublisher.cancelViewer(
                        applicationContext, session.request, index(), engine is VlcEngine)
                }
                P3SelectedMediaPublisher.setEnabled(applicationContext, false)
                stopP4LanSession()
                val revoked = P4PairingStore(applicationContext).revoke()"""


def patch_activity(text: str) -> str:
    if not isinstance(text, str) or (
        "P3SelectedMediaPublisher.accepted(" in text
        or "P3SelectedMediaPublisher.closed(" in text
    ):
        raise ValueError("P3_ACTIVITY_ALREADY_APPLIED")
    if (text.count("internal fun receiveP4Revision(") != 1
            or text.count("P4OwnerBootstrap.consume(applicationContext)") < 1
            or text.count(MENU) != 1):
        raise ValueError("P3_REQUIRES_EXACT_P4_COMPOSED_SOURCE")
    rules = (
        (FIELD, TICK + P3_RETRY + P4_SWITCH_SOURCE + FIELD),
        (CHOICE, CHOICE + """
        if (!choice.audio && ::session.isInitialized &&
            P1ProductionSubtitles.automaticChoice(
                applicationContext, session.request, index()) != "ON") {
            // The manual subtitle selector has just changed to OFF/OTHER.
            // Cancel an in-flight P4 activate response even if the movie
            // identity is still the same; it must NEVER switch OFF back ON.
            handler.removeCallbacks(p3ActivationTick)
            p3ActivationAttempts = 0
            p4ActivationGeneration++
            p4ActivationInFlight = false
            P3SelectedMediaPublisher.cancelViewer(
                applicationContext, session.request, index(), engine is VlcEngine)
            if (p4LanScope != null) unbindP4Session()
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
        (P4_BUTTON, P4_BUTTON_REQUEST + P4_SOURCE_MENU),
        (P4_REVOKE, P4_REVOKE_REQUEST),
        (P4_CONNECTING_MESSAGE, P4_CONNECTING_REPLACEMENT),
        (P4_PENDING_MESSAGE, P4_PENDING_REPLACEMENT),
        (P4_SUCCESS, P4_SUCCESS_REPLACEMENT),
        (P4_FIRST_FRAME, P4_FIRST_FRAME_REPLACEMENT),
        (P4_OFFER, P4_OFFER_REPLACEMENT),
    )
    for original, _ in rules:
        if text.count(original) != 1:
            raise ValueError("P3_SOURCE_ANCHOR_DRIFT")
    for original, updated in rules:
        text = text.replace(original, updated, 1)
    voice_original = '        if (next == "ORIGINAL") {\n            stopP4LanSession()'
    if 'private fun setP4VoiceMode(' in text:
        if text.count(voice_original) != 1:
            raise ValueError("P3_VOICE_ORIGINAL_ANCHOR_DRIFT")
        text = text.replace(voice_original,
            '        if (next == "ORIGINAL") {\n'
            '            cancelP3ViewerAndP4(if (::session.isInitialized) session.request else null)', 1)
    if text.count("P3SelectedMediaPublisher.accepted(") != 2:
        raise ValueError("P3_SOURCE_CALLBACK_COUNT_INVALID")
    if text.count("P3SelectedMediaPublisher.closed(") != 1:
        raise ValueError("P3_SOURCE_CLOSE_COUNT_INVALID")
    if (text.count("private val p3StatusTick =") != 1
            or text.count("P3SelectedMediaPublisher.sample(") != 4):
        raise ValueError("P3_SOURCE_STATE_SAMPLER_INVALID")
    if (text.count("private val p3ActivationTick =") != 1
            or text.count("P3SelectedMediaPublisher.requestViewer(") != 1
            or text.count("P3SelectedMediaPublisher.cancelViewer(") != 4
            or text.count("p3ActivationTick.run()") != 1):
        raise ValueError("P3_EXPLICIT_CONSENT_PATCH_INVALID")
    if (text.count('"AD01.13"') != 0
            or text.count('"AD01.10"') != 1
            or text.count('"AD01.12"') != 1):
        raise ValueError("P3_ONE_TAP_MENU_CONTRACT_INVALID")
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
