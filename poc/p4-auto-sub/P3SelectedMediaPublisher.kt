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
    private val HASH_RX = Regex("(?:[a-f0-9]{40}|[a-f0-9]{64})")
    private val SESSION_RX = Regex("[a-f0-9]{32}")
    private val KINDS = setOf(
        "PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED",
        "PLAYBACK_CLOSED",
    )
    private val random = SecureRandom()
    private val generation = AtomicLong(0L)
    private val queue = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "p3-tv-signal").apply { isDaemon = true }
    }

    private data class Current(
        val session: String, val hash: String, val fileIndex: Int,
    )
    @Volatile private var active: Current? = null

    internal fun enabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(ENABLED, false)

    /** ONLY user-initiated on-TV menu toggle. Pairing does NOT imply consent. */
    internal fun setEnabled(ctx: Context, on: Boolean): Boolean {
        if (on && P4PairingStore(ctx).load() == null) return false
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
    ) {
        if (!enabled(ctx) || kind !in KINDS || kind == "PLAYBACK_CLOSED") return
        val item = request?.queue?.getOrNull(itemIndex) ?: return
        val hash = item.hash?.lowercase() ?: return
        val fileIndex = item.fileIndex ?: return
        if (!HASH_RX.matches(hash) || fileIndex !in 0..65535) return
        val selected = Current(randomHex(), hash, fileIndex)
        active = selected
        enqueue(ctx.applicationContext, selected, kind)
    }

    /** A signed close only invalidates an existing selection, never starts AI. */
    internal fun closed(ctx: Context) {
        val old = active ?: return
        active = null
        if (enabled(ctx)) enqueue(ctx.applicationContext, old, "PLAYBACK_CLOSED")
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

        // P4PinnedTls enforces the owner's pinned certificate. P4LanClient
        // enforces private IPv4; no hostname resolution, redirects or WAN.
        val url = URL("https://${paired.host}:${paired.port}/p3/selection")
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
