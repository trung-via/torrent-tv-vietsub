// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager

/**
 * Explicit, per-device, certificate-pinned HTTPS to one literal RFC1918 host.
 *
 * The leaf SHA-256 comes from trusted, out-of-band PC pairing. The *default*
 * HttpsURLConnection hostname verifier must still validate the certificate's
 * IP-address SAN; no trust-all manager, wildcard hostname bypass, or global
 * TLS settings are installed. A changed cert requires explicit re-pairing.
 */
internal object P4PinnedTls {
    private val SHA256 = Regex("[0-9a-f]{64}")

    internal fun normalizePin(raw: String): String {
        val pin = raw.lowercase()
        if (!SHA256.matches(pin)) throw IllegalArgumentException("P4_TLS_PIN_REQUIRED")
        return pin
    }

    internal fun open(url: URL, rawPin: String): HttpsURLConnection {
        if (url.protocol != "https") throw IllegalArgumentException("P4_TLS_HTTPS_ONLY")
        if (!P4LanClient.isPrivateIPv4(url.host)) {
            throw IllegalArgumentException("P4_TLS_PRIVATE_IP_REQUIRED")
        }
        val pin = normalizePin(rawPin)
        val expected = ByteArray(32) { i ->
            pin.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>?, authType: String?) {
                throw CertificateException("P4_TLS_SERVER_ONLY")
            }
            override fun checkServerTrusted(chain: Array<X509Certificate>?, authType: String?) {
                if (chain == null || chain.isEmpty() || authType.isNullOrBlank()) {
                    throw CertificateException("P4_TLS_CHAIN_INVALID")
                }
                // Exact leaf pin from a trusted pairing step, not global trust.
                val cert = chain[0]
                cert.checkValidity()
                val hasExactIpSan = try {
                    cert.subjectAlternativeNames?.any { san ->
                        san.size >= 2 && san[0] == 7 && san[1] == url.host
                    } == true
                } catch (_: Exception) { false }
                if (!hasExactIpSan) {
                    throw CertificateException("P4_TLS_IP_SAN_MISMATCH")
                }
                val actual = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
                if (!MessageDigest.isEqual(actual, expected)) {
                    throw CertificateException("P4_TLS_CERT_PIN_MISMATCH")
                }
            }
        }
        // TLSv1.2 is a strict compatible baseline; never negotiate TLSv1.0/1.1.
        val context = SSLContext.getInstance("TLSv1.2")
        context.init(null, arrayOf(trust), SecureRandom())
        val conn = url.openConnection() as HttpsURLConnection
        conn.sslSocketFactory = context.socketFactory
        // Do NOT call setHostnameVerifier: Android default verifies the IP SAN.
        return conn
    }
}
