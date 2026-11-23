// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** One signed VieNeu cue from the existing P4 Owner/TV pairing. */
internal data class P4VoiceoverOffer(
    val schema: String,
    val sessionId: String,
    val mediaKey: String,
    val sourceSha256: String,
    val subtitleVersion: Int,
    val voiceId: String,
    val cueNumber: Int,
    val startMs: Long,
    val endMs: Long,
    val ttsKey: String,
    val wavSha256: String,
    val sampleRate: Int,
    val durationMs: Int,
    val signature: String,
)

/**
 * Pure native policy: no socket, audio device, Android context or provider.
 * The callback must verify WAV content and schedule at the current VLC clock.
 * A successful callback is not a speaker/audibility receipt.
 */
internal class P4VoiceoverReceiver(
    private val sessionId: String,
    private val mediaKey: String,
    private val sourceSha256: String,
    pairingSecret: ByteArray,
) {
    private val secret = pairingSecret.clone()
    private val heard = mutableMapOf<String, String>()

    init {
        require(SESSION.matches(sessionId)) { "P4_VOICE_SESSION_INVALID" }
        require(MEDIA.matches(mediaKey) && SHA.matches(sourceSha256)) {
            "P4_VOICE_IDENTITY_INVALID"
        }
        require(secret.size >= 16) { "P4_VOICE_KEY_REQUIRED" }
    }

    /** Called only on an explicit same-movie seek; never on a film switch. */
    @Synchronized
    fun resetForSeek(activeSession: String, activeMedia: String) {
        require(activeSession == sessionId && activeMedia == mediaKey) {
            "P4_VOICE_SEEK_WRONG_MEDIA"
        }
        heard.clear()
    }

    @Synchronized
    fun receive(
        offer: P4VoiceoverOffer,
        activeSession: String,
        activeMedia: String,
        presentationMode: String,
        engine: String,
        onNativeAudio: (P4VoiceoverOffer) -> Boolean,
    ): String {
        validate(offer)
        val expected = hmacHex(canonical(offer), secret)
        if (!MessageDigest.isEqual(hexBytes(expected), hexBytes(offer.signature))) {
            throw IllegalArgumentException("P4_VOICE_SIGNATURE_INVALID")
        }
        if (offer.sessionId != sessionId || offer.mediaKey != mediaKey ||
            offer.sourceSha256 != sourceSha256 || activeSession != sessionId ||
            activeMedia != mediaKey) {
            throw IllegalArgumentException("P4_VOICE_STALE_SESSION_OR_MEDIA")
        }
        if (presentationMode != "BOTH" && presentationMode != "VOICE") {
            return "P4_VOICE_DEFERRED_USER_CHOICE"
        }
        if (engine != "VLC") return "P4_VOICE_UNSUPPORTED_ENGINE"
        val prior = heard[offer.ttsKey]
        if (prior != null) {
            if (prior != offer.wavSha256) throw IllegalArgumentException("P4_VOICE_KEY_COLLISION")
            return "P4_VOICE_DUPLICATE"
        }
        val accepted = try { onNativeAudio(offer) } catch (_: Exception) { false }
        if (!accepted) return "P4_VOICE_NOT_QUEUED"
        heard[offer.ttsKey] = offer.wavSha256
        return "P4_VOICE_QUEUED_NOT_AUDIBLE_PROOF"
    }

    @Synchronized
    fun close() {
        secret.fill(0)
        heard.clear()
    }

    private fun validate(o: P4VoiceoverOffer) {
        if (o.schema != "TTV-P4-VOICEOVER-OFFER-V1" ||
            !SESSION.matches(o.sessionId) || !MEDIA.matches(o.mediaKey) ||
            !SHA.matches(o.sourceSha256) || !SHA.matches(o.ttsKey) ||
            !SHA.matches(o.wavSha256) || !SHA.matches(o.signature) ||
            !VOICE.matches(o.voiceId) ||
            o.subtitleVersion < 1 || o.cueNumber < 1 ||
            o.startMs < 0 || o.endMs <= o.startMs ||
            o.sampleRate != 48_000 || o.durationMs <= 0) {
            throw IllegalArgumentException("P4_VOICE_OFFER_INVALID")
        }
    }

    /** Exact sorted Python canonical JSON and its HMAC domain.
     * Values have been constrained to ASCII-safe tokens before encoding.
     */
    private fun canonical(o: P4VoiceoverOffer): ByteArray {
        val json = "{\"cue_number\":${o.cueNumber},\"duration_ms\":${o.durationMs}," +
            "\"end_ms\":${o.endMs},\"media_key\":\"${o.mediaKey}\"," +
            "\"sample_rate\":${o.sampleRate},\"schema\":\"${o.schema}\"," +
            "\"session_id\":\"${o.sessionId}\",\"source_sha256\":\"${o.sourceSha256}\"," +
            "\"start_ms\":${o.startMs},\"subtitle_version\":${o.subtitleVersion}," +
            "\"tts_key\":\"${o.ttsKey}\",\"voice_id\":\"${o.voiceId}\"," +
            "\"wav_sha256\":\"${o.wavSha256}\"}"
        return "TTV-P4-VOICEOVER-V1\n".toByteArray(Charsets.US_ASCII) +
            json.toByteArray(Charsets.US_ASCII)
    }

    companion object {
        private val SESSION = Regex("[A-Za-z0-9_-]{16,80}")
        private val MEDIA = Regex("media\\.[0-9a-f]{64}")
        private val SHA = Regex("[0-9a-f]{64}")
        private val VOICE = Regex("[A-Za-z0-9_-]{1,64}")
        private fun hexBytes(value: String) =
            ByteArray(value.length / 2) { i -> value.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
        private fun hmacHex(payload: ByteArray, secret: ByteArray): String {
            val h = Mac.getInstance("HmacSHA256")
            h.init(SecretKeySpec(secret, "HmacSHA256"))
            return h.doFinal(payload).joinToString("") { "%02x".format(it.toInt() and 255) }
        }
    }
}
