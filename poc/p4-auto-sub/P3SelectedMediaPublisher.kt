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
        "PLAYBACK_CLOSED",
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
    )
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
        // Same single executor: independently sampled ACTUAL PlayerSession
        // G1/P4 choice is signed BEFORE the selection event is sent.
        sample(ctx, request, itemIndex, nativeVlc)
        enqueue(ctx.applicationContext, selected, kind)
    }

    /** A signed close only invalidates an existing selection, never starts AI. */
    internal fun closed(ctx: Context) {
        val old = active ?: return
        active = null
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
            item.fileIndex == current.fileIndex
        // Real per-media P4 ON/OFF/OTHER, NEVER infer ON from global consent.
        val choice = if (isSame) P1ProductionSubtitles.automaticChoice(
            ctx, request, selectedIndex) else "OTHER"
        enqueueStatus(ctx.applicationContext, current, isSame, choice)
    }

    private fun enqueueStatus(ctx: Context, selected: Current,
                              isActive: Boolean, actualChoice: String) {
        val gen = generation.get()
        val sampledAt = android.os.SystemClock.elapsedRealtime()
        val sequence = statusSequence.incrementAndGet()
        queue.execute {
            if (generation.get() != gen || !enabled(ctx) ||
                android.os.SystemClock.elapsedRealtime() - sampledAt > STATUS_TIMEOUT_MS) {
                return@execute
            }
            val paired = P4PairingStore(ctx).load() ?: return@execute
            try {
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
        val gen = generation.incrementAndGet()
        queue.execute {
            if (generation.get() != gen || !enabled(ctx)) return@execute
            val paired = P4PairingStore(ctx).load() ?: return@execute
            try {
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
            choice !in setOf("ON", "OFF", "OTHER") ||
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
