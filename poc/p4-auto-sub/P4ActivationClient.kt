// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.os.Looper
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * PC already has matching EN timed subtitle; TV sends only opaque mediaKey.
 * Device pairing key is provisioned separately and never leaves this method.
 * Host creates a fresh per-film session+sourceHash; TV derives matching key.
 * Signed metadata, no DNS/WAN, no TV listener. Plain HTTP is not confidential.
 */
internal object P4ActivationClient {
    internal data class Activated(
        val sessionId: String,
        val sourceSha256: String,
        val sessionSecret: ByteArray,
    )

    private val MEDIA = Regex("media\\.[0-9a-f]{64}")
    private val SHA = Regex("[0-9a-f]{64}")
    private val SESSION = Regex("[A-Za-z0-9_-]{16,80}")

    /** Never on UI thread; every request has a new 128-bit nonce. */
    internal fun activate(
        host: String, port: Int, mediaKey: String, deviceSecret: ByteArray,
    ): Activated {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            throw IllegalStateException("P4_ACTIVATE_MAIN_THREAD_FORBIDDEN")
        }
        if (!MEDIA.matches(mediaKey) || deviceSecret.size != 32) {
            throw IllegalArgumentException("P4_ACTIVATE_INPUT_INVALID")
        }
        val nonce = ByteArray(16).also { SecureRandom().nextBytes(it) }
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        val request = JSONObject()
            .put("schema", "TTV-P4-ACTIVATE-V1")
            .put("media_key", mediaKey)
            .put("nonce", nonce)
            .put("auth", sign(deviceSecret,"TTV-P4-ACTIVATE-V1\n$mediaKey\n$nonce"))
            .toString().toByteArray(Charsets.US_ASCII)
        if (request.size > 800) throw IllegalArgumentException("P4_ACTIVATE_SIZE_INVALID")
        val conn = P4LanClient.activationEndpoint(host,port).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.instanceFollowRedirects = false
            conn.connectTimeout = 3_000
            conn.readTimeout = 5_000
            conn.useCaches = false
            conn.doOutput = true
            conn.setRequestProperty("Content-Type","application/json")
            conn.setFixedLengthStreamingMode(request.size)
            conn.outputStream.use { it.write(request) }
            if (conn.responseCode != 200) throw IllegalArgumentException("P4_ACTIVATE_NOT_READY")
            if (conn.contentType?.substringBefore(';')!="application/json") {
                throw IllegalArgumentException("P4_ACTIVATE_CONTENT_TYPE_INVALID")
            }
            val out=ByteArrayOutputStream()
            conn.inputStream.use { input ->
                val buf=ByteArray(512)
                while (true) {
                    val n=input.read(buf)
                    if (n<0) break
                    if (out.size()+n>2048) throw IllegalArgumentException("P4_ACTIVATE_RESPONSE_TOO_LARGE")
                    out.write(buf,0,n)
                }
            }
            val data=JSONObject(out.toString("UTF-8"))
            val keys=data.keys().asSequence().toSet()
            if (keys!=setOf("schema","media_key","nonce","session_id","source_sha256","auth") ||
                data.getString("schema")!="TTV-P4-ACTIVATED-V1" ||
                data.getString("media_key")!=mediaKey || data.getString("nonce")!=nonce) {
                throw IllegalArgumentException("P4_ACTIVATE_SCOPE_INVALID")
            }
            val session=data.getString("session_id")
            val source=data.getString("source_sha256")
            val tag=data.getString("auth")
            if (!SESSION.matches(session) || !SHA.matches(source) || !SHA.matches(tag)) {
                throw IllegalArgumentException("P4_ACTIVATE_RESPONSE_INVALID")
            }
            val expected=sign(deviceSecret,
                "TTV-P4-ACTIVATED-V1\n$mediaKey\n$nonce\n$session\n$source")
            val actual=ByteArray(32){ i->tag.substring(i*2,i*2+2).toInt(16).toByte() }
            val correct=ByteArray(32){ i->expected.substring(i*2,i*2+2).toInt(16).toByte() }
            if (!MessageDigest.isEqual(actual,correct)) {
                throw IllegalArgumentException("P4_ACTIVATE_AUTH_INVALID")
            }
            val derived=hmac(deviceSecret,
                "TTV-P4-SESSION-KEY-V1\n$session\n$mediaKey\n$source")
            return Activated(session,source,derived)
        } finally {
            conn.disconnect()
        }
    }

    private fun hmac(secret: ByteArray, message: String): ByteArray {
        val mac=Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret,"HmacSHA256"))
        return mac.doFinal(message.toByteArray(Charsets.US_ASCII))
    }

    private fun sign(secret: ByteArray, message: String): String =
        hmac(secret,message).joinToString("") { "%02x".format(it.toInt() and 255) }
}
