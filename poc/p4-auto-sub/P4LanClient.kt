// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.os.Looper
import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Unattended polling *client* for a single private IPv4 P2 LAN feed.
 *
 * No TV listener, exported activity, hostname/DNS or WAN endpoints. A signed
 * P4 offer must still pass P4SignedReceiver HMAC, media, session and ON checks.
 * HMAC provides authenticity/integrity, but HTTP is NOT encrypted. Never send
 * passwords/API keys/copyrighted source film to this endpoint.
 */
internal object P4LanClient {
    private const val MAX_WIRE_BYTES = 400_000
    private val SESSION_RX = Regex("[A-Za-z0-9_-]{16,80}")
    private val B64_RX = Regex("(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?")

    internal fun endpoint(host: String, port: Int, sessionId: String): URL {
        if (!isPrivateIPv4(host)) throw IllegalArgumentException("P4_LAN_IP_REQUIRED")
        if (port !in 1024..65535) throw IllegalArgumentException("P4_LAN_PORT_INVALID")
        if (!SESSION_RX.matches(sessionId)) throw IllegalArgumentException("P4_SESSION_ID_INVALID")
        return URL("http://$host:$port/p4/revision/$sessionId")
    }

    private fun isPrivateIPv4(value: String): Boolean {
        if (!Regex("(?:[0-9]{1,3}\\.){3}[0-9]{1,3}").matches(value)) return false
        val values = value.split(".").mapNotNull { it.toIntOrNull() }
        if (values.size != 4 || values.any { it !in 0..255 }) return false
        if (values.joinToString(".") != value) return false // reject aliases, octal-like values
        return values[0] == 10 ||
            (values[0] == 172 && values[1] in 16..31) ||
            (values[0] == 192 && values[1] == 168)
    }

    /** Must be called off the UI thread. No redirects or unbounded response. */
    internal fun pollOnce(host: String, port: Int, sessionId: String): P4SubtitleOffer? {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw IllegalStateException("P4_LAN_MAIN_THREAD_FORBIDDEN")
        }
        val url = endpoint(host, port, sessionId)
        val connection = (url.openConnection() as HttpURLConnection)
        try {
            connection.requestMethod = "GET"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 3_000
            connection.readTimeout = 5_000
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            when (connection.responseCode) {
                204 -> return null
                200 -> Unit
                else -> throw IllegalArgumentException("P4_LAN_HTTP_NOT_OK")
            }
            if (connection.contentType?.substringBefore(';') != "application/json") {
                throw IllegalArgumentException("P4_LAN_CONTENT_TYPE_INVALID")
            }
            val out = ByteArrayOutputStream()
            connection.inputStream.use { stream ->
                val buf = ByteArray(8192)
                while (true) {
                    val n = stream.read(buf)
                    if (n < 0) break
                    if (out.size() + n > MAX_WIRE_BYTES) {
                        throw IllegalArgumentException("P4_LAN_WIRE_TOO_LARGE")
                    }
                    out.write(buf,0,n)
                }
            }
            return decodeOffer(out.toByteArray())
        } finally {
            connection.disconnect()
        }
    }

    /**
     * Parse a fixed JSON envelope. All values are still untrusted until the
     * native P4SignedReceiver verifies SHA256+HMAC and active movie/session.
     */
    internal fun decodeOffer(bytes: ByteArray): P4SubtitleOffer {
        if (bytes.isEmpty() || bytes.size > MAX_WIRE_BYTES) {
            throw IllegalArgumentException("P4_LAN_WIRE_INVALID")
        }
        val decoded = try {
            Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) {
            throw IllegalArgumentException("P4_LAN_UTF8_INVALID")
        }
        val json = try { JSONObject(decoded) } catch (_: Exception) {
            throw IllegalArgumentException("P4_LAN_JSON_INVALID")
        }
        val allowed = setOf(
            "schema","session_id","media_key","source_sha256","version",
            "fmt","translated_count","total_count","last_end_ms",
            "payload_sha256","payload_b64","signature",
        )
        val keys = json.keys().asSequence().toSet()
        if (keys != allowed || json.getString("schema") != "TTV-P4-LAN-REVISION-V1") {
            throw IllegalArgumentException("P4_LAN_ENVELOPE_INVALID")
        }
        val encoded = json.getString("payload_b64")
        if (!B64_RX.matches(encoded) || encoded.length > 350_000) {
            throw IllegalArgumentException("P4_LAN_BASE64_INVALID")
        }
        val payload = try { Base64.decode(encoded, Base64.NO_WRAP) }
            catch (_: IllegalArgumentException) {
                throw IllegalArgumentException("P4_LAN_BASE64_INVALID")
            }
        return P4SubtitleOffer(
            sessionId=json.getString("session_id"),
            mediaKey=json.getString("media_key"),
            sourceSha256=json.getString("source_sha256"),
            version=json.getInt("version"),
            format=json.getString("fmt"),
            translatedCount=json.getInt("translated_count"),
            totalCount=json.getInt("total_count"),
            lastEndMs=json.getLong("last_end_ms"),
            payloadSha256=json.getString("payload_sha256"),
            payload=payload,
            signature=json.getString("signature"),
        )
    }
}
