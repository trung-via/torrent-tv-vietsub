"""Bounded P4 PlayerActivity bridge overlay on *already G1+G2-patched* OMP.

Source only: wires a trusted in-process offer entrypoint to the existing
G1 bytes import and a playback-clock cue overlay lifecycle. It DOES NOT
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
MENU_ANCHOR = '        add(I18n.s("player.subsRow", "v" to sSel.label), "AD01.3") { openSubsList() }'

# This whole bridge is deliberately in PlayerActivity (not a global singleton).
# Future pairing transport may call bindP4Session()/receiveP4Revision() *only from
# trusted in-process code* with a local secret, never arbitrary exported intents.
ACTIVITY_BRIDGE = """    /** P4: no external listener yet. Bound to THIS Activity and VLC media only. */
    private var p4SignedReceiver: P4SignedReceiver? = null
    private var p4SessionId: String? = null
    private var p4PendingOffer: P4SubtitleOffer? = null
    private var p4PendingRequest: PlayRequest? = null
    private var p4ImportInFlight = false
    private data class P4OverlayState(
        val request: PlayRequest, val itemIndex: Int, val playbackEngine: PlayerEngine,
        val sourceSha256: String, val timeline: P4CueTimeline,
    )
    private var p4OverlayState: P4OverlayState? = null
    private var p4OverlayView: android.widget.TextView? = null
    private var p4LastMuteMs = 0L
    private val p4StylePrefs by lazy {
        applicationContext.getSharedPreferences("p4-vietsub-style", android.content.Context.MODE_PRIVATE)
    }
    private fun p4BackgroundEnabled(): Boolean =
        p4StylePrefs.getBoolean("translucent_background", false)
    private fun applyP4Background(view: android.widget.TextView) {
        if (!p4BackgroundEnabled()) {
            view.background = null
            return
        }
        val d = resources.displayMetrics.density
        view.background = android.graphics.drawable.GradientDrawable().apply {
            setColor(android.graphics.Color.argb(155, 0, 0, 0))
            cornerRadius = 8f * d
        }
    }

    private fun clearP4Overlay() {
        handler.removeCallbacks(p4OverlayTick)
        p4OverlayState = null
        p4OverlayView?.let { (it.parent as? android.view.ViewGroup)?.removeView(it) }
        p4OverlayView = null
    }

    private fun ensureP4OverlayView(): android.widget.TextView {
        p4OverlayView?.let { return it }
        val video = findViewById<android.view.View>(R.id.player_video)
        val parent = video.parent as android.widget.FrameLayout
        val density = resources.displayMetrics.density
        val margin = (32 * density).toInt()
        val view = android.widget.TextView(this).apply {
            gravity = android.view.Gravity.CENTER
            setTextColor(android.graphics.Color.WHITE)
            textSize = 26f
            setShadowLayer(4f, 1f, 2f, android.graphics.Color.BLACK)
            setPadding(margin, (6 * density).toInt(),
                margin, (6 * density).toInt())
            applyP4Background(this)
            isFocusable = false
            isClickable = false
            visibility = android.view.View.GONE
        }
        val params = android.widget.FrameLayout.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.WRAP_CONTENT,
            android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL)
        params.bottomMargin = (54 * density).toInt()
        parent.addView(view, parent.indexOfChild(video) + 1, params)
        p4OverlayView = view
        return view
    }

    private val p4OverlayTick = object : Runnable {
        override fun run() {
            val state = p4OverlayState ?: return
            if (closedSent || isFinishing || isDestroyed ||
                !::session.isInitialized || session.request !== state.request ||
                index() != state.itemIndex || engine !== state.playbackEngine ||
                engine !is VlcEngine ||
                P1ProductionSubtitles.automaticChoice(applicationContext,
                    state.request, state.itemIndex) != "ON") {
                clearP4Overlay()
                return
            }
            val view = p4OverlayView ?: return
            // Do not display two subtitle tracks. Direct engine selection
            // does not invoke the user's PlayerSession track-choice callback.
            val nativeSelected = engine.subtitleTracks().any { it.selected }
            if (nativeSelected) {
                val now = android.os.SystemClock.uptimeMillis()
                if (now - p4LastMuteMs >= 500L) {
                    p4LastMuteMs = now
                    engine.selectSubtitle(null)
                }
            }
            val text = if (nativeSelected || session.error != null) "" else
                state.timeline.textAt(engine.positionMs)
            if (view.text.toString() != text) view.text = text
            view.visibility = if (text.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
            handler.postDelayed(this, 100L)
        }
    }

    private data class P4LanScope(
        val host: String, val port: Int, val sessionId: String,
        val readSecret: ByteArray, val certPinSha256: String,
    )
    private var p4LanScope: P4LanScope? = null
    private var p4LanGeneration = 0
    private var p4LanInFlight = false
    private var p4ActivationInFlight = false
    private var p4ActivationGeneration = 0
    private val p4LanPoll = object : Runnable {
        override fun run() {
            val scope = p4LanScope ?: return
            val current = if (::session.isInitialized) session.request else null
            if (current == null || P1ProductionSubtitles.automaticChoice(
                    applicationContext, current, index()) != "ON") {
                // An explicit OFF/OTHER choice revokes feed authorization.
                unbindP4Session()
                return
            }
            val gen = p4LanGeneration
            if (!p4LanInFlight) {
                p4LanInFlight = true
                Thread {
                    // A lost PC-side in-memory session is NOT a normal
                    // no-new-revision 204. Never auto-reactivate/bill Gemini.
                    var terminalFailure: String? = null
                    val offer = try {
                        P4LanClient.pollOnce(scope.host, scope.port, scope.sessionId,
                            scope.readSecret, scope.certPinSha256)
                    } catch (_: P4LanSessionExpired) {
                        terminalFailure = "SESSION_EXPIRED"
                        null
                    } catch (_: P4LanAuthorizationRejected) {
                        terminalFailure = "AUTH_REJECTED"
                        null
                    } catch (_: Exception) {
                        // Temporary network outage: retain the active movie,
                        // last accepted sidecar and bounded six-second polling.
                        null
                    }
                    runOnUiThread {
                        if (gen != p4LanGeneration || p4LanScope !== scope) return@runOnUiThread
                        p4LanInFlight = false
                        if (isFinishing || isDestroyed || closedSent) return@runOnUiThread
                        if (terminalFailure != null) {
                            val current = if (::session.isInitialized) session.request else null
                            val stillOn = current != null &&
                                P1ProductionSubtitles.automaticChoice(
                                    applicationContext, current, index()) == "ON"
                            // Stop stale polling, erase session secrets, revert
                            // unacknowledged imports; keep user's ON/OFF choice
                            // and last valid subtitle. No automatic activation.
                            unbindP4Session()
                            if (stillOn) {
                                showMessage(
                                    if (terminalFailure == "SESSION_EXPIRED")
                                        "Phiên Vietsub AI trên PC đã hết. Bật lại để kết nối."
                                    else "PC từ chối xác thực Vietsub AI. Kiểm tra kết nối an toàn.",
                                    true)
                            }
                        } else if (offer != null) {
                            receiveP4Revision(offer)
                        }
                    }
                }.start()
            }
            // Pull model: no inbound port/listener on the TV and no auto-start.
            handler.postDelayed(this, 6_000L)
        }
    }

    // Pairing is imported only from an app-private one-shot file staged by the
    // already-authorized owner laptop over ADB. No TV text input or prompt.

    /** Explicit per-film UI only, with an already paired PC and supplied EN text. */
    private fun beginP4Activation() {
        if (p4ActivationInFlight || p4LanScope != null || !::session.isInitialized ||
            engine !is VlcEngine || isFinishing || isDestroyed) return
        val r = session.request ?: return
        val idx = index()
        val media = P1ProductionSubtitles.mediaKey(r, idx) ?: run {
            showMessage("Không xác định được phim cho Vietsub AI.", true)
            return
        }
        // Quiet one-time import. Existing pinned laptop is never overwritten.
        P4OwnerBootstrap.consume(applicationContext)
        val device = P4PairingStore(applicationContext).load() ?: run {
            showMessage("Laptop chưa được kết nối an toàn.", true)
            return
        }
        p4ActivationInFlight = true
        val gen = ++p4ActivationGeneration
        showMessage("Đang kết nối Vietsub AI với PC...", false)
        Thread {
            val result = try {
                P4ActivationClient.activate(device.host, device.port,
                    media, device.deviceSecret, device.certPinSha256)
            } catch (_: Exception) { null }
            device.deviceSecret.fill(0)
            runOnUiThread {
                if (gen != p4ActivationGeneration) {
                    result?.sessionSecret?.fill(0)
                    return@runOnUiThread
                }
                p4ActivationInFlight = false
                if (result == null) {
                    showMessage("PC chưa sẵn sàng hoặc chưa có phụ đề nguồn cho phim.", true)
                    return@runOnUiThread
                }
                val same = !closedSent && !isFinishing && !isDestroyed &&
                    ::session.isInitialized && session.request === r && index() == idx &&
                    P1ProductionSubtitles.mediaKey(session.request, idx) == media
                val started = same && startP4LanSession(
                    device.host, device.port, result.sessionId,
                    result.sourceSha256, result.sessionSecret, device.certPinSha256)
                result.sessionSecret.fill(0)
                showMessage(
                    if (started) "Đã bật Vietsub AI. Đang chờ bản dịch đầu tiên..."
                    else "Phim đã đổi hoặc không thể bật Vietsub AI.", !started)
            }
        }.start()
    }

    /**
     * Trusted local pairing action only; caller supplies a one-time paired
     * server/session/secret after Human opt-in. No default running service.
     */
    internal fun startP4LanSession(
        host: String, port: Int, sessionId: String,
        sourceSha256: String, secret: ByteArray, certPinSha256: String,
    ): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper() || p4LanScope != null) return false
        try {
            P4LanClient.endpoint(host, port, sessionId)
            P4PinnedTls.normalizePin(certPinSha256)
        } catch (_: IllegalArgumentException) { return false }
        if (!bindP4Session(sessionId, sourceSha256, secret)) return false
        val r = session.request
        if (!P1ProductionSubtitles.setAutomaticOptIn(applicationContext, r, index(), true)) {
            unbindP4Session()
            return false
        }
        p4LanGeneration++
        p4LanScope = P4LanScope(host, port, sessionId, secret.clone(), certPinSha256)
        handler.post(p4LanPoll)
        return true
    }

    /** Only the paired instance that started this session can stop it. */
    internal fun stopP4LanSession() {
        if (Looper.myLooper() != Looper.getMainLooper()) return
        val current = if (::session.isInitialized) session.request else null
        if (p4LanScope != null && current != null) {
            P1ProductionSubtitles.setAutomaticOptIn(
                applicationContext, current, index(), false)
        }
        unbindP4Session()
        clearP4Overlay()
    }

    /** Only a later, private authenticated pairing flow may call this. */
    internal fun bindP4Session(sessionId: String, sourceSha256: String, key: ByteArray): Boolean {
        if (Looper.myLooper() != Looper.getMainLooper() || p4SignedReceiver != null ||
            p4PendingOffer != null || g2Recovery != null ||
            closedSent || isFinishing || isDestroyed || !::session.isInitialized ||
            engine !is VlcEngine) return false
        val current = session.request ?: return false
        val mediaKey = P1ProductionSubtitles.mediaKey(current, index()) ?: return false
        val ledger = P4AppliedLedger(applicationContext, sessionId, mediaKey, sourceSha256)
        val prior = ledger.read() ?: return false
        val receiver = try {
            P4SignedReceiver(
                sessionId, mediaKey, sourceSha256, key,
                acceptedVersion = prior.first, acceptedDigest = prior.second,
                onFirstFrameAccepted = { version, digest -> ledger.record(version, digest) }
            )
        } catch (_: IllegalArgumentException) { return false }
        p4SignedReceiver = receiver
        p4SessionId = sessionId
        return true
    }

    private fun abortP4Pending() {
        val offer = p4PendingOffer
        if (offer != null) p4SignedReceiver?.abortPending(offer.version, offer.payloadSha256)
        p4PendingOffer = null
        p4PendingRequest = null
    }

    private fun unbindP4Session() {
        handler.removeCallbacks(p4LanPoll)
        p4LanGeneration++
        p4ActivationGeneration++
        p4ActivationInFlight = false
        p4LanScope?.readSecret?.fill(0)
        p4LanScope = null
        p4LanInFlight = false
        abortP4Pending()
        p4SignedReceiver = null
        p4SessionId = null
    }

    /**
     * Trusted in-process P4 handoff entrypoint, NOT an exported TV listener.
     * An authenticated offer starts a background G1 file import, then swaps
     * the Activity's cue timeline without touching the playback session.
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
                if (g2Recovery != null || p4PendingOffer != null || p4ImportInFlight ||
                    r.engine != EngineMode.VLC || engine !is VlcEngine ||
                    format !in listOf("srt", "vtt")) {
                    false
                } else {
                    val timeline = receiver.parseTimeline(bytes, format)
                    val old = p4OverlayState
                    if (old != null && old.request === r && old.itemIndex == idx &&
                        old.sourceSha256 == offer.sourceSha256 &&
                        !timeline.extends(old.timeline)) return@receive false
                    // Create the view before any durable import; no playback reload.
                    ensureP4OverlayView()
                    val playbackEngine = engine
                    p4PendingOffer = offer
                    p4PendingRequest = r
                    p4ImportInFlight = true
                    Thread {
                        val before = try {
                            P1ProductionSubtitles.snapshotAutomaticBefore(
                                applicationContext, r, idx, nowKey)
                        } catch (_: Exception) { null }
                        val imported = try {
                            before != null && P1ProductionSubtitles.importAutomaticBytes(
                                applicationContext, bytes, r, idx, nowKey)
                        } catch (_: Exception) { false }
                        runOnUiThread {
                            p4ImportInFlight = false
                            val current = p4PendingOffer === offer &&
                                p4PendingRequest === r && p4SignedReceiver === receiver &&
                                !closedSent && !isFinishing && !isDestroyed &&
                                ::session.isInitialized && session.request === r &&
                                engine === playbackEngine &&
                                G2RefreshDecision.matchesCurrent(
                                    nowKey, P1ProductionSubtitles.mediaKey(session.request, index()),
                                    idx, index(), engine is VlcEngine, closedSent) &&
                                P1ProductionSubtitles.automaticChoice(
                                    applicationContext, r, idx) == "ON"
                            val acknowledged = if (current && imported && before != null) {
                                try {
                                    receiver.acknowledgeOverlayInstalled(sid, nowKey, "ON", "VLC",
                                        offer.version, offer.payloadSha256) == "OVERLAY_INSTALLED"
                                } catch (_: Exception) { false }
                            } else false
                            if (!acknowledged) {
                                if (imported && before != null) {
                                    P1ProductionSubtitles.rollbackAutomatic(
                                        applicationContext, before, bytes)
                                }
                                receiver.abortPending(offer.version, offer.payloadSha256)
                                if (p4PendingOffer === offer) abortP4Pending()
                            } else {
                                p4OverlayState = P4OverlayState(r, idx, playbackEngine,
                                    offer.sourceSha256, timeline)
                                abortP4Pending()
                                handler.removeCallbacks(p4OverlayTick)
                                handler.post(p4OverlayTick)
                                android.util.Log.i("TorrentTV-Vietsub", "P4_TV_OVERLAY_INSTALLED")
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

P4_MENU_ROWS = """        add(if (p4LanScope != null || p4ActivationInFlight)
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
        // Explicit device-level revocation is an optional advanced action,
        // never a prerequisite for enabling Vietsub on the current movie.
        add(if (p4BackgroundEnabled()) "Nền mờ phụ đề: Bật"
                else "Nền mờ phụ đề: Tắt", "AD01.15") {
            p4StylePrefs.edit().putBoolean(
                "translucent_background", !p4BackgroundEnabled()).apply()
            p4OverlayView?.let { applyP4Background(it) }
            showMessage(if (p4BackgroundEnabled()) "Đã bật nền mờ phụ đề."
                else "Đã tắt nền mờ phụ đề.", false)
        }
        val savedPc = P4PairingStore(applicationContext).load()
        if (savedPc != null) {
            savedPc.deviceSecret.fill(0)
            add("Ngắt ghép đôi PC Vietsub AI (nâng cao)", "AD01.12") {
                stopP4LanSession()
                val revoked = P4PairingStore(applicationContext).revoke()
                showMessage(if (revoked) "Đã hủy ghép đôi." else "Không thể hủy ghép đôi.", !revoked)
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
        FRAME_ANCHOR: (FRAME_ANCHOR, "FRAME"),
        DESTROY_ANCHOR: (DESTROY_ANCHOR.replace(
            "        handler.removeCallbacksAndMessages(null)",
            "        clearP4Overlay()\n        unbindP4Session()\n        handler.removeCallbacksAndMessages(null)"), "DESTROY"),
        LOAD_ANCHOR: (LOAD_ANCHOR.replace(
            "        clearG2Recovery()",
            "        P4OwnerBootstrap.consume(applicationContext)\n" +
            "        clearP4Overlay()\n        unbindP4Session()\n        clearG2Recovery()"), "LOAD"),
        ITEM_ANCHOR: (ITEM_ANCHOR.replace(
            "        clearG2Recovery()",
            "        clearP4Overlay()\n        unbindP4Session()\n        clearG2Recovery()"), "ITEM"),
        MENU_ANCHOR: (MENU_ANCHOR + "\n" + P4_MENU_ROWS, "MENU"),
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
