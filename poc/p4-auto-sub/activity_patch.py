"""Bounded P4 PlayerActivity bridge overlay on *already G1+G2-patched* OMP.

Source only: wires a trusted in-process offer entrypoint to the existing
G1 bytes import and G2 reload/first-frame/rollback lifecycle. It DOES NOT
create a socket, exported Android component or transport a file to the TV.
"""
from __future__ import annotations

FIELD_ANCHOR = "    private var g2Recovery: G2RefreshRecovery? = null"
CLEAR_ANCHOR = """    private fun clearG2Recovery() {
        handler.removeCallbacks(g2RecoveryTimeout)
        g2Recovery = null
    }"""
FRAME_ANCHOR = """        if (g2Recovery?.matchesCurrent(session.request, index()) == true) {
            clearG2Recovery()"""
DESTROY_ANCHOR = """    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)"""
LOAD_ANCHOR = """    private fun load(r: PlayRequest, choose: Boolean = true) {
        clearG2Recovery()"""
ITEM_ANCHOR = """        if (q == null || i !in q.indices || i == session.index) return
        clearG2Recovery()"""

# This whole bridge is deliberately in PlayerActivity (not a global singleton).
# Future pairing transport may call bindP4Session()/receiveP4Revision() *only from
# trusted in-process code* with a local secret, never arbitrary exported intents.
ACTIVITY_BRIDGE = """    /** P4: no external listener yet. Bound to THIS Activity and VLC media only. */
    private var p4SignedReceiver: P4SignedReceiver? = null
    private var p4SessionId: String? = null
    private var p4PendingOffer: P4SubtitleOffer? = null
    private var p4PendingRequest: PlayRequest? = null
    private var p4ExpectedRefresh: PlayRequest? = null

    private data class P4LanScope(val host: String, val port: Int, val sessionId: String)
    private var p4LanScope: P4LanScope? = null
    private var p4LanGeneration = 0
    private var p4LanInFlight = false
    private val p4LanPoll = object : Runnable {
        override fun run() {
            val scope = p4LanScope ?: return
            val gen = p4LanGeneration
            if (!p4LanInFlight) {
                p4LanInFlight = true
                Thread {
                    val offer = try {
                        P4LanClient.pollOnce(scope.host, scope.port, scope.sessionId)
                    } catch (_: Exception) { null }
                    runOnUiThread {
                        if (gen != p4LanGeneration || p4LanScope !== scope) return@runOnUiThread
                        p4LanInFlight = false
                        if (!isFinishing && !isDestroyed && !closedSent && offer != null) {
                            receiveP4Revision(offer)
                        }
                    }
                }.start()
            }
            // Pull model: no inbound port/listener on the TV and no auto-start.
            handler.postDelayed(this, 6_000L)
        }
    }

    /**
     * Trusted local pairing action only; caller supplies a one-time paired
     * server/session/secret after Human opt-in. No default running service.
     */
    internal fun startP4LanSession(
        host: String, port: Int, sessionId: String,
        sourceSha256: String, secret: ByteArray,
    ): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper() || p4LanScope != null) return false
        try { P4LanClient.endpoint(host, port, sessionId) }
        catch (_: IllegalArgumentException) { return false }
        if (!bindP4Session(sessionId, sourceSha256, secret)) return false
        p4LanGeneration++
        p4LanScope = P4LanScope(host, port, sessionId)
        handler.post(p4LanPoll)
        return true
    }

    /** Only the paired instance that started this session can stop it. */
    internal fun stopP4LanSession() {
        if (Looper.myLooper() != Looper.getMainLooper()) return
        unbindP4Session()
    }

    /** Only a later, private authenticated pairing flow may call this. */
    internal fun bindP4Session(sessionId: String, sourceSha256: String, key: ByteArray): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper() || p4SignedReceiver != null ||
            p4PendingOffer != null || g2Recovery != null ||
            closedSent || isFinishing || isDestroyed || !::session.isInitialized ||
            engine !is VlcEngine) return false
        val current = session.request ?: return false
        val mediaKey = P1ProductionSubtitles.mediaKey(current, index()) ?: return false
        val receiver = try { P4SignedReceiver(sessionId, mediaKey, sourceSha256, key) }
            catch (_: IllegalArgumentException) { return false }
        p4SignedReceiver = receiver
        p4SessionId = sessionId
        return true
    }

    private fun abortP4Pending() {
        val offer = p4PendingOffer
        if (offer != null) p4SignedReceiver?.abortPending(offer.version, offer.payloadSha256)
        p4PendingOffer = null
        p4PendingRequest = null
        p4ExpectedRefresh = null
    }

    private fun unbindP4Session() {
        handler.removeCallbacks(p4LanPoll)
        p4LanGeneration++
        p4LanScope = null
        p4LanInFlight = false
        abortP4Pending()
        p4SignedReceiver = null
        p4SessionId = null
    }

    /** G2 first-frame callback already proved the refreshed PlayRequest is current. */
    private fun acknowledgeP4FirstFrame() {
        val offer = p4PendingOffer ?: return
        val receiver = p4SignedReceiver ?: run { abortP4Pending(); return }
        val current = session.request ?: run { abortP4Pending(); return }
        if (current !== p4ExpectedRefresh) {
            abortP4Pending()
            return
        }
        val mediaKey = P1ProductionSubtitles.mediaKey(current, index())
        val choice = P1ProductionSubtitles.automaticChoice(applicationContext, current, index())
        try {
            receiver.acknowledgeFirstFrame(
                p4SessionId.orEmpty(), mediaKey.orEmpty(), choice,
                if (engine is VlcEngine) "VLC" else "OTHER",
                offer.version, offer.payloadSha256
            )
        } catch (_: IllegalArgumentException) {
            // An OFF/OTHER switch or session change invalidates this async ACK.
        } finally {
            abortP4Pending()
        }
    }

    /**
     * Trusted in-process P4 handoff entrypoint, NOT an exported TV listener.
     * An authenticated offer may start a background G1 file import, followed
     * by the same-item G2 player reload. The receiver is still pending until
     * onFirstFrameShown validates the new active VLC frame.
     */
    internal fun receiveP4Revision(offer: P4SubtitleOffer): String {
        if (Looper.myLooper() != Looper.getMainLooper() ||
            closedSent || isFinishing || isDestroyed || !::session.isInitialized) {
            return "P4_PLAYER_NOT_READY"
        }
        val r = session.request ?: return "P4_PLAYER_NOT_READY"
        val idx = index()
        val nowKey = P1ProductionSubtitles.mediaKey(r, idx) ?: return "P4_MEDIA_NOT_READY"
        val receiver = p4SignedReceiver ?: return "P4_NOT_PAIRED"
        val sid = p4SessionId ?: return "P4_NOT_PAIRED"
        val choice = P1ProductionSubtitles.automaticChoice(applicationContext, r, idx)
        return try {
            receiver.receive(
                offer, sid, nowKey, choice,
                if (engine is VlcEngine) "VLC" else "OTHER"
            ) { bytes, format ->
                if (g2Recovery != null || p4PendingOffer != null ||
                    r.engine != EngineMode.VLC || engine !is VlcEngine ||
                    format !in listOf("srt", "vtt")) {
                    false
                } else {
                    p4PendingOffer = offer
                    p4PendingRequest = r
                    Thread {
                        // Snapshot BEFORE G1's registry replaces and deletes old bytes.
                        val snapshot = G2RefreshRecovery.capture(applicationContext, r, idx)
                        val imported = try {
                            snapshot != null && P1ProductionSubtitles.importAutomaticBytes(
                                applicationContext, bytes, r, idx, nowKey)
                        } catch (_: Exception) { false }
                        runOnUiThread {
                            if (p4PendingOffer !== offer || p4PendingRequest !== r ||
                                closedSent || isFinishing || isDestroyed ||
                                !::session.isInitialized || session.request !== r ||
                                !G2RefreshDecision.matchesCurrent(
                                    nowKey, P1ProductionSubtitles.mediaKey(session.request, index()),
                                    idx, index(), engine is VlcEngine, closedSent) ||
                                P1ProductionSubtitles.automaticChoice(
                                    applicationContext, r, idx) != "ON" ||
                                !imported || snapshot == null) {
                                snapshot?.restoreOldFile()
                                abortP4Pending()
                            } else {
                                val fresh = G2RefreshInPlace.prepare(applicationContext, r, idx)
                                if (fresh == null) {
                                    snapshot.restoreOldFile()
                                    abortP4Pending()
                                } else {
                                    try {
                                        commitPendingSeek()
                                        val ms = engine.positionMs.coerceAtLeast(0L)
                                        val paused = !engine.playWhenReady
                                        val audio = engine.audioTracks().firstOrNull { it.selected }
                                        val audioPick = audio?.let {
                                            TrackPick.of(it.label?.trim().orEmpty(),
                                                it.language?.trim().orEmpty())
                                        } ?: fresh.audioPick
                                        val queue = fresh.queue.mapIndexed { i, item ->
                                            item.copy(resumeMs = session.resumeOf(i))
                                        }
                                        val priorQueue = r.queue.mapIndexed { i, item ->
                                            item.copy(resumeMs = session.resumeOf(i))
                                        }
                                        val newRequest = fresh.copy(
                                            queue = queue, startAtMs = ms, audioPick = audioPick)
                                        val previous = r.copy(
                                            queue = priorQueue, startAtMs = ms, audioPick = audioPick)
                                        snapshot.arm(newRequest, previous, paused)
                                        p4ExpectedRefresh = newRequest
                                        g2Recovery = snapshot
                                        session.load(newRequest)
                                        if (paused) engine.pause()
                                        if (!paused) handler.postDelayed(g2RecoveryTimeout, 25_000L)
                                        showMessage("Đang tự cập nhật Vietsub AI...", false)
                                    } catch (_: Exception) {
                                        if (!rollbackG2Refresh()) abortP4Pending()
                                    }
                                }
                            }
                        }
                    }.start()
                    true
                }
            }
        } catch (_: IllegalArgumentException) {
            "P4_OFFER_REJECTED"
        }
    }

"""

def _once(text: str, old: str, new: str, tag: str) -> str:
    if text.count(old) != 1:
        raise ValueError("P4_ACTIVITY_ANCHOR_" + tag)
    return text.replace(old, new, 1)


def patch_activity(original: str) -> str:
    if "private var p4SignedReceiver:" in original:
        raise ValueError("P4_ACTIVITY_ALREADY_APPLIED")
    anchors = {
        FIELD_ANCHOR: (ACTIVITY_BRIDGE + FIELD_ANCHOR, "FIELD"),
        CLEAR_ANCHOR: (CLEAR_ANCHOR.replace(
            "        g2Recovery = null",
            "        g2Recovery = null\n        abortP4Pending()"), "CLEAR"),
        FRAME_ANCHOR: (FRAME_ANCHOR.replace(
            "            clearG2Recovery()",
            "            acknowledgeP4FirstFrame()\n            clearG2Recovery()"), "FRAME"),
        DESTROY_ANCHOR: (DESTROY_ANCHOR.replace(
            "        handler.removeCallbacksAndMessages(null)",
            "        unbindP4Session()\n        handler.removeCallbacksAndMessages(null)"), "DESTROY"),
        LOAD_ANCHOR: (LOAD_ANCHOR.replace(
            "        clearG2Recovery()",
            "        unbindP4Session()\n        clearG2Recovery()"), "LOAD"),
        ITEM_ANCHOR: (ITEM_ANCHOR.replace(
            "        clearG2Recovery()",
            "        unbindP4Session()\n        clearG2Recovery()"), "ITEM"),
    }
    text = original
    # All original G2 anchors must be unique *before* edits.
    for old, (_, tag) in anchors.items():
        if text.count(old) != 1:
            raise ValueError("P4_ACTIVITY_ANCHOR_" + tag)
    for old, (new, tag) in anchors.items():
        text = _once(text, old, new, tag)
    if text.count("internal fun receiveP4Revision(") != 1:
        raise ValueError("P4_ACTIVITY_ENTRYPOINT_INVALID")
    return text
