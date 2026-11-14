// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import org.json.JSONObject
import java.net.URL
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * Owner-opted-in native source of genuine selected-file events for P3.
 *
 * This is a *client* of the already authorized P4 certificate-pinned private
 * HTTPS PC endpoint. No TV listener, no exported Android components, no ADB,
 * no credentials in media URLs, no subtitles/movie content. Disabled by
 * default, P4 device pairing alone does not enable metadata forwarding.
 *
 * UI title is NOT a filename, so the signed event deliberately carries only
 * hash + fileIndex. PC must independently read the TorrServer file metadata.
 * The P4 per-movie OFF/OTHER choice remains authoritative downstream.
 */
internal object P3SelectedMediaPublisher {
    private const val PREFS = "p3-owner-selected-media-v1"
    private const val ENABLED = "owner_enabled"
    private const val SCHEMA = "TTV-P3-TV-SELECTION-V1"
    private const val STATUS_SCHEMA = "TTV-P3-TV-STATE-V1"
    private const val STATUS_TIMEOUT_MS = 2_000L
    private val HASH_RX = Regex("(?:[a-f0-9]{40}|[a-f0-9]{64})")
    private val SESSION_RX = Regex("[a-f0-9]{32}")
    private val KINDS = setOf(
        "PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED",
        "PLAYBACK_CLOSED", "VIEWER_VIETSUB_REQUESTED",
    )
    private val random = SecureRandom()
    private val bootId = randomHex()
    private val statusSequence = AtomicLong(0L)
    private val generation = AtomicLong(0L)
    private val queue = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "p3-tv-signal").apply { isDaemon = true }
    }

    private data class Current(
        val session: String, val hash: String, val fileIndex: Int,
        val kind: String,
    ) {
        @Volatile var requestedByViewer: Boolean = false
    }
    @Volatile private var active: Current? = null

    internal fun enabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(ENABLED, false)

    /** ONLY user-initiated on-TV menu toggle. Pairing does NOT imply consent. */
    internal fun setEnabled(ctx: Context, on: Boolean): Boolean {
        if (on) {
            val paired = P4PairingStore(ctx).load() ?: return false
            paired.deviceSecret.fill(0)
        }
        val ok = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(ENABLED, on).commit()
        if (!on) {
            active = null
            generation.incrementAndGet()
        }
        return ok
    }

    /** Called only AFTER PlayerActivity.load or successful goTo. */
    internal fun accepted(
        ctx: Context, request: PlayRequest?, itemIndex: Int, kind: String,
        nativeVlc: Boolean,
    ) {
        if (!enabled(ctx) || !nativeVlc || request?.engine != EngineMode.VLC ||
            kind !in KINDS || kind == "PLAYBACK_CLOSED") return
        val item = request?.queue?.getOrNull(itemIndex) ?: return
        val hash = item.hash?.lowercase() ?: return
        val fileIndex = item.fileIndex ?: return
        if (!HASH_RX.matches(hash) || fileIndex !in 0..65535) return
        val selected = Current(randomHex(), hash, fileIndex, kind)
        active = selected
        generation.incrementAndGet()
        // Same single executor: independently sampled ACTUAL PlayerSession
        // G1/P4 choice is signed BEFORE the selection event is sent.
        sample(ctx, request, itemIndex, nativeVlc)
        enqueue(ctx.applicationContext, selected, kind)
    }

    /** A P3 global metadata toggle is NOT a per-film request.
     * Only a direct "Bật Vietsub AI" tap may authorize current film search.
     * An existing active session is used; after enabling P3 mid-video a new
     * session is created WITHOUT inventing a signed Play event.
     */
    internal fun viewerRequested(
        ctx: Context, request: PlayRequest?, selectedIndex: Int,
        nativeVlc: Boolean,
    ): Boolean {
        val selected = active ?: return false
        val item = request?.queue?.getOrNull(selectedIndex) ?: return false
        return enabled(ctx) && nativeVlc && request.engine == EngineMode.VLC &&
            item.hash?.lowercase() == selected.hash &&
            item.fileIndex == selected.fileIndex && selected.requestedByViewer
    }

    /** Called ONLY by the direct on-TV Vietsub AI button. */
    internal fun requestViewer(
        ctx: Context, request: PlayRequest?, selectedIndex: Int,
        nativeVlc: Boolean,
    ): Boolean {
        if (!enabled(ctx) || !nativeVlc || request?.engine != EngineMode.VLC) {
            return false
        }
        val item = request.queue.getOrNull(selectedIndex) ?: return false
        val hash = item.hash?.lowercase() ?: return false
        val index = item.fileIndex ?: return false
        if (!HASH_RX.matches(hash) || index !in 0..65535 ||
            P1ProductionSubtitles.mediaKey(request, selectedIndex) == null) return false
        val previous = active
        val current = if (previous != null && previous.hash == hash &&
            previous.fileIndex == index) previous
            else Current(randomHex(), hash, index, "PLAY_REQUEST_ACCEPTED")
        if (previous !== current) {
            // User enabled metadata sharing in the middle of playback; do not
            // forge a native PlayRequest event. A viewer tap is distinct.
            active = current
            generation.incrementAndGet()
        }
        if (current.requestedByViewer) return true
        current.requestedByViewer = true
        // One bounded serial executor: authenticated REQUESTED status must
        // precede signed viewer-tap event for this exact native selection.
        sample(ctx, request, selectedIndex, nativeVlc)
        enqueue(ctx.applicationContext, current, "VIEWER_VIETSUB_REQUESTED")
        return true
    }

    /** Bounded retry of the SAME explicit request, not a Play event.
     * A missed status during transport congestion must not strand the job;
     * owner V3 + durable replay/one-POST claims deduplicate safely.
     */
    internal fun reaffirmViewer(
        ctx: Context, request: PlayRequest?, selectedIndex: Int,
        nativeVlc: Boolean,
    ) {
        if (!viewerRequested(ctx, request, selectedIndex, nativeVlc)) return
        val current = active ?: return
        sample(ctx, request, selectedIndex, nativeVlc)
        enqueue(ctx.applicationContext, current, "VIEWER_VIETSUB_REQUESTED")
    }

    /** A current user's OFF/OTHER/manual choice revokes any pending request. */
    internal fun cancelViewer(
        ctx: Context, request: PlayRequest?, selectedIndex: Int,
        nativeVlc: Boolean,
    ) {
        val current = active ?: return
        if (!current.requestedByViewer) return
        current.requestedByViewer = false
        // Revoke all not-yet-sent REQUESTED status and viewer-tap packets
        // belonging to the old generation, even if the executor is backed up.
        generation.incrementAndGet()
        sample(ctx, request, selectedIndex, nativeVlc)
    }

    /** A signed close only invalidates an existing selection, never starts AI. */
    internal fun closed(ctx: Context) {
        val old = active ?: return
        active = null
        generation.incrementAndGet()
        if (enabled(ctx)) {
            enqueue(ctx.applicationContext, old, "PLAYBACK_CLOSED")
            enqueueStatus(ctx.applicationContext, old, false, "OTHER")
        }
    }

    /** Native status must be sampled on PlayerActivity main thread, not
     * replayed from the earlier Play event. Pause/resume retain the same
     * session; only an actual selected-file change generates a new session.
     */
    internal fun sample(
        ctx: Context, request: PlayRequest?, selectedIndex: Int,
        nativeVlc: Boolean,
    ) {
        val current = active ?: return
        if (!enabled(ctx)) return
        val item = request?.queue?.getOrNull(selectedIndex)
        val isSame = nativeVlc && request?.engine == EngineMode.VLC &&
            item?.hash?.lowercase() == current.hash &&
            item?.fileIndex == current.fileIndex
        // Real per-media P4 ON/OFF/OTHER, NEVER infer ON from global consent.
        val nativeChoice = if (isSame) P1ProductionSubtitles.automaticChoice(
            ctx, request, selectedIndex) else "OTHER"
        // REQUESTED is a session-scoped explicit viewer intent BEFORE there
        // is an EN/VI source or P4 receiver. P4 automaticChoice remains ON
        // only after a real authenticated P4 activation and valid source.
        val choice = if (isSame && current.requestedByViewer &&
            nativeChoice != "ON") "REQUESTED" else nativeChoice
        enqueueStatus(ctx.applicationContext, current, isSame, choice)
    }

    private fun enqueueStatus(ctx: Context, selected: Current,
                              isActive: Boolean, actualChoice: String) {
        val gen = generation.get()
        val sampledAt = android.os.SystemClock.elapsedRealtime()
        val sequence = statusSequence.incrementAndGet()
        queue.execute {
            if (generation.get() != gen || active !== selected || !enabled(ctx) ||
                (actualChoice == "REQUESTED" && !selected.requestedByViewer) ||
                android.os.SystemClock.elapsedRealtime() - sampledAt > STATUS_TIMEOUT_MS) {
                return@execute
            }
            val paired = P4PairingStore(ctx).load() ?: return@execute
            try {
                if (generation.get() != gen || active !== selected ||
                    (actualChoice == "REQUESTED" && !selected.requestedByViewer)) {
                    return@execute
                }
                postStatusOnce(paired, selected, isActive, actualChoice, sequence)
            } catch (_: Exception) {
                // Signed status is best-effort, expiry on PC is fail-closed.
            } finally {
                paired.deviceSecret.fill(0)
            }
        }
    }

    private fun randomHex(): String {
        val bytes = ByteArray(16)
        random.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun enqueue(ctx: Context, selected: Current, kind: String) {
        val gen = generation.get()
        queue.execute {
            if (generation.get() != gen || active !== selected || !enabled(ctx) ||
                (kind == "VIEWER_VIETSUB_REQUESTED" &&
                    !selected.requestedByViewer)) return@execute
            val paired = P4PairingStore(ctx).load() ?: return@execute
            try {
                if (generation.get() != gen || active !== selected ||
                    (kind == "VIEWER_VIETSUB_REQUESTED" &&
                        !selected.requestedByViewer)) return@execute
                postOnce(paired, selected, kind)
            } catch (_: Exception) {
                // Metadata signal is strictly best-effort and MUST NOT
                // interrupt native playback or expose private torrent data.
            } finally {
                paired.deviceSecret.fill(0)
            }
        }
    }

    private fun postOnce(
        paired: P4PairingStore.Pairing, current: Current, kind: String,
    ) {
        if (!KINDS.contains(kind) || !SESSION_RX.matches(current.session) ||
            !HASH_RX.matches(current.hash) || current.fileIndex !in 0..65535 ||
            paired.deviceSecret.size != 32 ||
            !P4LanClient.isPrivateIPv4(paired.host) ||
            paired.port !in 1024..65535
        ) return
        val sent = System.currentTimeMillis()
        val nonce = randomHex()
        val canonical = "$SCHEMA\n$kind\n" +
            "${current.session}\n${current.hash}\n${current.fileIndex}\n$sent\n$nonce"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(paired.deviceSecret, "HmacSHA256"))
        val signature = mac.doFinal(canonical.toByteArray(Charsets.US_ASCII))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val body = JSONObject()
            .put("schema", SCHEMA)
            .put("kind", kind)
            .put("tv_session_id", current.session)
            .put("torrent_hash", current.hash)
            .put("file_index", current.fileIndex)
            .put("sent_at_ms", sent)
            .put("nonce", nonce)
            .put("signature", signature)
            .toString().toByteArray(Charsets.UTF_8)
        if (body.isEmpty() || body.size > 1024) return
        postJson(paired, "/p3/selection", body)
    }

    private fun postStatusOnce(
        paired: P4PairingStore.Pairing, current: Current,
        isActive: Boolean, choice: String, sequence: Long,
    ) {
        if (!SESSION_RX.matches(bootId) || sequence < 1L ||
            !SESSION_RX.matches(current.session) ||
            !HASH_RX.matches(current.hash) || current.hash.length != 40 ||
            current.fileIndex !in 0..65535 ||
            choice !in setOf("ON", "REQUESTED", "OFF", "OTHER") ||
            current.kind !in setOf("PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED") ||
            paired.deviceSecret.size != 32
        ) return
        val sent = System.currentTimeMillis()
        val nonce = randomHex()
        val flag = if (isActive) "1" else "0"
        val canonical = "$STATUS_SCHEMA\n$bootId\n$sequence\n" +
            "${current.kind}\n${current.session}\n${current.hash}\n" +
            "${current.fileIndex}\n$flag\n$choice\n$sent\n$nonce"
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(paired.deviceSecret, "HmacSHA256"))
        val signature = mac.doFinal(canonical.toByteArray(Charsets.US_ASCII))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val body = JSONObject()
            .put("schema", STATUS_SCHEMA)
            .put("boot_id", bootId)
            .put("sequence", sequence)
            .put("kind", current.kind)
            .put("tv_session_id", current.session)
            .put("torrent_hash", current.hash)
            .put("file_index", current.fileIndex)
            .put("active", isActive)
            .put("subtitle_choice", choice)
            .put("sent_at_ms", sent)
            .put("nonce", nonce)
            .put("signature", signature)
            .toString().toByteArray(Charsets.UTF_8)
        if (body.isEmpty() || body.size > 1024) return
        postJson(paired, "/p3/state", body)
    }

    private fun postJson(
        paired: P4PairingStore.Pairing, route: String, body: ByteArray,
    ) {
        if (!P4LanClient.isPrivateIPv4(paired.host) ||
            paired.port !in 1024..65535 ||
            route !in setOf("/p3/state", "/p3/selection")) return
        // Reuse exactly the same paired PC certificate-pinned HTTPS transport.
        // No device listener, cleartext, WAN or new PC port.
        val url = URL("https://${paired.host}:${paired.port}$route")
        val conn = P4PinnedTls.open(url, paired.certPinSha256)
        try {
            conn.requestMethod = "POST"
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 3000
            conn.readTimeout = 5000
            conn.useCaches = false
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setFixedLengthStreamingMode(body.size)
            conn.outputStream.use { it.write(body) }
            if (conn.responseCode != 204) {
                throw IllegalArgumentException("P3_OWNER_ENDPOINT_NOT_READY")
            }
        } finally {
            conn.disconnect()
        }
    }
}
