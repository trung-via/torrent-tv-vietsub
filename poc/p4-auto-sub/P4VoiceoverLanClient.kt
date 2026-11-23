// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.os.Looper
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Optional narration GET using the already-pinned P4 HTTPS connection. */
internal object P4VoiceoverLanClient {
    private val SESSION = Regex("[A-Za-z0-9_-]{16,80}")
    private val SHA = Regex("[0-9a-f]{64}")
    private const val MAX_JSON = 160_000
    private const val MAX_WAV = 3_000_000
    internal data class Page(val offers: List<P4VoiceoverOffer>, val more: Boolean)

    private fun hex(bytes: ByteArray) =
        bytes.joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun fetch(
        host: String, port: Int, sid: String, secret: ByteArray, pin: String,
        scope: String, path: String, accept: String, cap: Int, cursor: Int? = null,
    ): Pair<Int, ByteArray> {
        if (Looper.myLooper() == Looper.getMainLooper())
            throw IllegalStateException("P4_VOICE_MAIN_THREAD_FORBIDDEN")
        P4LanClient.endpoint(host, port, sid) // original RFC1918/port/session gates
        if (!SESSION.matches(sid) || secret.size < 16 || !path.startsWith("/"))
            throw IllegalArgumentException("P4_VOICE_REQUEST_SCOPE_INVALID")
        val nonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val nonceHex = hex(nonce)
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        val signature = hex(mac.doFinal(
            "TTV-P4-VOICE-READ-V1\n$sid\n$scope\n$nonceHex"
                .toByteArray(Charsets.US_ASCII)))
        val conn = P4PinnedTls.open(URL("https://$host:$port/p4$path"), pin)
        try {
            conn.requestMethod = "GET"
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 3000
            conn.readTimeout = 5000
            conn.useCaches = false
            conn.setRequestProperty("X-P4-Nonce", nonceHex)
            conn.setRequestProperty("X-P4-Authorization", signature)
            conn.setRequestProperty("Accept", accept)
            if (cursor != null)
                conn.setRequestProperty("X-P4-After-Cue", cursor.toString())
            val code = conn.responseCode
            if (code == 204) return 204 to ByteArray(0)
            if (code == 401 || code == 403) throw P4LanAuthorizationRejected()
            if (code == 404) throw P4LanSessionExpired()
            if (code != 200 || conn.contentType?.substringBefore(';') != accept)
                throw IllegalArgumentException("P4_VOICE_HTTP_INVALID")
            if (conn.contentLength > cap)
                throw IllegalArgumentException("P4_VOICE_BYTES_TOO_LARGE")
            val out = ByteArrayOutputStream()
            conn.inputStream.use { stream ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = stream.read(buf)
                    if (n < 0) break
                    if (out.size() + n > cap)
                        throw IllegalArgumentException("P4_VOICE_BYTES_TOO_LARGE")
                    out.write(buf, 0, n)
                }
            }
            return 200 to out.toByteArray()
        } finally {
            conn.disconnect()
        }
    }

    internal fun listCues(
        host: String, port: Int, sid: String, secret: ByteArray,
        pin: String, afterCue: Int,
    ): Page {
        if (afterCue !in 0..100_000) throw IllegalArgumentException("P4_VOICE_CURSOR_INVALID")
        val (code, body) = fetch(
            host, port, sid, secret, pin, "manifest:$afterCue",
            "/voice/$sid", "application/json", MAX_JSON, afterCue)
        if (code == 204) return Page(emptyList(), false)
        val root = JSONObject(String(body, Charsets.UTF_8))
        if (root.keys().asSequence().toSet() != setOf(
                "schema", "session_id", "media_key", "source_sha256",
                "after_cue", "more", "offers") ||
            root.getString("schema") != "TTV-P4-VOICEOVER-MANIFEST-V1" ||
            root.getString("session_id") != sid ||
            root.getInt("after_cue") != afterCue)
            throw IllegalArgumentException("P4_VOICE_MANIFEST_INVALID")
        val offers = root.getJSONArray("offers")
        if (offers.length() > 32) throw IllegalArgumentException("P4_VOICE_PAGE_TOO_LARGE")
        val result = (0 until offers.length()).map { i ->
            val o = offers.getJSONObject(i)
            if (o.keys().asSequence().toSet() != setOf(
                    "schema", "session_id", "media_key", "source_sha256",
                    "subtitle_version", "voice_id", "cue_number",
                    "start_ms", "end_ms", "tts_key", "wav_sha256",
                    "sample_rate", "duration_ms", "signature"))
                throw IllegalArgumentException("P4_VOICE_CUE_SCHEMA_INVALID")
            val cue = P4VoiceoverOffer(
                o.getString("schema"), o.getString("session_id"),
                o.getString("media_key"), o.getString("source_sha256"),
                o.getInt("subtitle_version"), o.getString("voice_id"),
                o.getInt("cue_number"), o.getLong("start_ms"),
                o.getLong("end_ms"), o.getString("tts_key"),
                o.getString("wav_sha256"), o.getInt("sample_rate"),
                o.getInt("duration_ms"), o.getString("signature"))
            if (cue.sessionId != sid || cue.mediaKey != root.getString("media_key") ||
                cue.sourceSha256 != root.getString("source_sha256") ||
                cue.cueNumber <= afterCue)
                throw IllegalArgumentException("P4_VOICE_CUE_IDENTITY_INVALID")
            cue // The caller must verify HMAC through P4VoiceoverReceiver.
        }
        return Page(result, root.getBoolean("more"))
    }

    internal fun wav(
        host: String, port: Int, sid: String, secret: ByteArray,
        pin: String, offer: P4VoiceoverOffer,
    ): ByteArray {
        if (sid != offer.sessionId || !SHA.matches(offer.ttsKey) ||
            !SHA.matches(offer.wavSha256))
            throw IllegalArgumentException("P4_VOICE_WAV_IDENTITY_INVALID")
        val (code, bytes) = fetch(
            host, port, sid, secret, pin, "audio:" + offer.ttsKey,
            "/audio/" + sid + "/" + offer.ttsKey, "audio/wav", MAX_WAV)
        if (code != 200 || bytes.size < 44 ||
            !bytes.copyOfRange(0,4).contentEquals("RIFF".toByteArray()) ||
            !bytes.copyOfRange(8,12).contentEquals("WAVE".toByteArray()))
            throw IllegalArgumentException("P4_VOICE_WAV_FORMAT_INVALID")
        if (hex(MessageDigest.getInstance("SHA-256").digest(bytes)) != offer.wavSha256)
            throw IllegalArgumentException("P4_VOICE_WAV_HASH_INVALID")
        return bytes // Not proof of AudioTrack playback.
    }
}
