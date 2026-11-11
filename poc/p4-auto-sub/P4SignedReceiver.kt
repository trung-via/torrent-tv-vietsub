// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** Native, session-scoped G2 delivery policy. No sockets, ADB, Android exports or TV mutations. */
internal data class P4SubtitleOffer(
    val sessionId: String,
    val mediaKey: String,
    val sourceSha256: String,
    val version: Int,
    val format: String,
    val translatedCount: Int,
    val totalCount: Int,
    val lastEndMs: Long,
    val payloadSha256: String,
    val payload: ByteArray,
    val signature: String,
)

internal class P4SignedReceiver(
    private val pairedSessionId: String,
    private val pairedMediaKey: String,
    private val pairedSourceSha256: String,
    pairingSecret: ByteArray,
) {
    private val secret = pairingSecret.clone()
    private var lastVersion = 0
    private var lastDigest: String? = null

    init {
        require(SESSION.matches(pairedSessionId)) { "P4_SESSION_ID_INVALID" }
        require(MEDIA.matches(pairedMediaKey)) { "P4_MEDIA_KEY_INVALID" }
        require(SHA.matches(pairedSourceSha256)) { "P4_SOURCE_HASH_INVALID" }
        require(secret.size >= 16) { "P4_PAIRING_SECRET_REQUIRED" }
    }

    /** Apply callback must be wired to G1 bytes import + SAME-item G2 VLC reload. */
    @Synchronized
    fun receive(
        offer: P4SubtitleOffer, activeSessionId: String, activeMediaKey: String,
        subtitleChoice: String, engine: String,
        onG2Apply: (ByteArray, String) -> Boolean,
    ): String {
        validate(offer)
        if (offer.sessionId != pairedSessionId ||
            offer.mediaKey != pairedMediaKey ||
            offer.sourceSha256 != pairedSourceSha256 ||
            activeSessionId != pairedSessionId ||
            activeMediaKey != pairedMediaKey) {
            throw IllegalArgumentException("P4_SESSION_OR_MEDIA_MISMATCH")
        }
        val signatureBytes = hexBytes(offer.signature)
        val calculatedBytes = hexBytes(hmacHex(canonical(offer), secret))
        if (!MessageDigest.isEqual(signatureBytes, calculatedBytes)) {
            throw IllegalArgumentException("P4_AUTHENTICATION_FAILED")
        }
        if (offer.version < lastVersion) throw IllegalArgumentException("P4_STALE_REVISION")
        if (offer.version == lastVersion) {
            if (lastDigest == offer.payloadSha256) return "DUPLICATE_NOOP"
            throw IllegalArgumentException("P4_REVISION_COLLISION")
        }
        if (engine != "VLC") return "DEFERRED_UNSUPPORTED_ENGINE"
        if (subtitleChoice != "ON") return "DEFERRED_USER_SUBTITLE_CHOICE"
        val ok = try { onG2Apply(offer.payload.clone(), offer.format) } catch (_: Exception) { false }
        if (ok != true) return "G2_APPLY_FAILED_RETAIN_LAST_VALID"
        lastVersion = offer.version
        lastDigest = offer.payloadSha256
        return "APPLIED_TO_G2"
    }

    internal fun lastAppliedForTest(): Int = lastVersion

    private fun validate(o: P4SubtitleOffer) {
        if (!SESSION.matches(o.sessionId) || !MEDIA.matches(o.mediaKey) ||
            !SHA.matches(o.sourceSha256) || !SHA.matches(o.payloadSha256) ||
            !SHA.matches(o.signature)) throw IllegalArgumentException("P4_OFFER_IDENTITY_INVALID")
        if (o.version !in 1..1_000_000 || o.format !in setOf("srt", "vtt") ||
            o.translatedCount !in 1..2000 || o.totalCount !in o.translatedCount..2000 ||
            o.lastEndMs <= 0 || o.payload.isEmpty() || o.payload.size > 256 * 1024) {
            throw IllegalArgumentException("P4_OFFER_BOUNDS_INVALID")
        }
        if (shaHex(o.payload) != o.payloadSha256) {
            throw IllegalArgumentException("P4_PAYLOAD_HASH_MISMATCH")
        }
        val result = parseCues(o.payload, o.format)
        if (result.first != o.translatedCount || result.second != o.lastEndMs) {
            throw IllegalArgumentException("P4_SUBTITLE_METADATA_MISMATCH")
        }
    }

    private fun parseCues(payload: ByteArray, fmt: String): Pair<Int, Long> {
        val body = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(payload)).toString().removePrefix("\uFEFF")
                .replace("\r\n", "\n")
        } catch (_: Exception) { throw IllegalArgumentException("P4_UTF8_INVALID") }
        if ('\u0000' in body || '\r' in body) {
            throw IllegalArgumentException("P4_SUBTITLE_INVALID")
        }
        val sections = body.trimEnd('\n').split(Regex("\n[ \t]*\n+"))
        val blocks = if (fmt == "vtt") {
            if (sections.firstOrNull() != "WEBVTT") {
                throw IllegalArgumentException("P4_VTT_HEADER_INVALID")
            }
            sections.drop(1)
        } else sections
        if (blocks.isEmpty() || blocks.size > 2000) {
            throw IllegalArgumentException("P4_CUE_COUNT_INVALID")
        }
        var previousStart = -1L
        var lastEnd = 0L
        blocks.forEachIndexed { i, block ->
            val lines = block.split("\n")
            val offset = if (fmt == "srt") {
                if (lines.firstOrNull() != (i + 1).toString()) {
                    throw IllegalArgumentException("P4_SRT_SEQUENCE_INVALID")
                }
                1
            } else if (lines.firstOrNull()?.contains(" --> ") == true) 0 else 1
            if (lines.size < offset + 2 || lines.drop(offset + 1).none { it.isNotBlank() }) {
                throw IllegalArgumentException("P4_CUE_TEXT_INVALID")
            }
            val pair = lines[offset].split(" --> ")
            if (pair.size != 2) throw IllegalArgumentException("P4_CUE_TIMING_INVALID")
            val start = millis(pair[0], fmt)
            val end = millis(if (fmt == "vtt") pair[1].substringBefore(' ') else pair[1], fmt)
            if (end <= start || start < previousStart) {
                throw IllegalArgumentException("P4_CUE_ORDER_INVALID")
            }
            previousStart = start
            lastEnd = end
        }
        return Pair(blocks.size, lastEnd)
    }

    private fun millis(value: String, fmt: String): Long {
        val rx = if (fmt == "srt") SRT_TIME else VTT_TIME
        val match = rx.matchEntire(value) ?: throw IllegalArgumentException("P4_TIME_INVALID")
        val segments = value.replace(',', '.').split(':', '.').map { it.toLong() }
        val h = if (segments.size == 4) segments[0] else 0L
        val m = segments[segments.size - 3]
        val sec = segments[segments.size - 2]
        val ms = segments.last()
        if (m > 59 || sec > 59 || h > 99 || match.value != value) {
            throw IllegalArgumentException("P4_TIME_RANGE_INVALID")
        }
        return ((h * 60 + m) * 60 + sec) * 1000 + ms
    }

    companion object {
        private val SESSION = Regex("[A-Za-z0-9_-]{16,80}")
        private val MEDIA = Regex("media\\.[0-9a-f]{64}")
        private val SHA = Regex("[0-9a-f]{64}")
        private val SRT_TIME = Regex("\\d{2}:\\d{2}:\\d{2},\\d{3}")
        private val VTT_TIME = Regex("(?:\\d{2}:)?\\d{2}:\\d{2}\\.\\d{3}")

        private fun shaHex(b: ByteArray) =
            MessageDigest.getInstance("SHA-256").digest(b).joinToString("") {
                "%02x".format(it.toInt() and 255)
            }

        private fun hexBytes(v: String): ByteArray =
            ByteArray(v.length / 2) { i -> v.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

        private fun hmacHex(data: String, key: ByteArray): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(key, "HmacSHA256"))
            return mac.doFinal(data.toByteArray(Charsets.US_ASCII)).joinToString("") {
                "%02x".format(it.toInt() and 255)
            }
        }

        /** Exact Python sorted-key compact JSON; all string fields match safe ASCII regexes. */
        private fun canonical(o: P4SubtitleOffer): String =
            "{\"fmt\":\"" + o.format + "\"," +
            "\"last_end_ms\":" + o.lastEndMs + "," +
            "\"media_key\":\"" + o.mediaKey + "\"," +
            "\"payload_sha256\":\"" + o.payloadSha256 + "\"," +
            "\"session_id\":\"" + o.sessionId + "\"," +
            "\"source_sha256\":\"" + o.sourceSha256 + "\"," +
            "\"total_count\":" + o.totalCount + "," +
            "\"translated_count\":" + o.translatedCount + "," +
            "\"v\":\"TTV-P4-SUBTITLE-V1\"," +
            "\"version\":" + o.version + "}"
    }
}
