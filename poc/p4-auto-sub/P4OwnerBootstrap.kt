// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import java.io.File

/**
 * One-laptop developer bootstrap. A previously authorized ADB host stages a
 * single, private app-owned file using "run-as" (debug build only).
 * No exported component, pairing network endpoint or TV text input.
 *
 * The file is consumed ONLY inside the application's UID, then erased.
 * Subsequent access reuses P4PairingStore's AndroidKeyStore AES-GCM.
 */
internal object P4OwnerBootstrap {
    private const val FILE_NAME = "p4-owner-bootstrap-v1.txt"
    private val TOKEN = Regex(
        """((?:10|172|192)\.(?:[0-9]{1,3}\.){2}[0-9]{1,3}):([0-9]{4,5})\|([a-fA-F0-9]{64})\|([a-fA-F0-9]{64})"""
    )

    /** Called on main thread when entering the native player or activating AI. */
    internal fun consume(ctx: Context): Boolean {
        val file = File(ctx.filesDir, FILE_NAME)
        if (!file.isFile) return false
        try {
            // No automatic replacement of an existing paired laptop.
            val store = P4PairingStore(ctx)
            if (store.load() != null) return false
            if (file.length() !in 130L..240L) return false
            val raw = try {
                Charsets.US_ASCII.newDecoder()
                    .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                    .decode(java.nio.ByteBuffer.wrap(file.readBytes())).toString().trimEnd('\n', '\r')
            } catch (_: Exception) { return false }
            val values = TOKEN.matchEntire(raw) ?: return false
            val host = values.groupValues[1]
            val port = values.groupValues[2].toIntOrNull() ?: return false
            val pin = values.groupValues[4].lowercase()
            // Full RFC1918 validation belongs to the existing P4LanClient.
            try {
                P4LanClient.activationEndpoint(host, port)
                P4PinnedTls.normalizePin(pin)
            } catch (_: IllegalArgumentException) { return false }
            val hex = values.groupValues[3]
            val bytes = ByteArray(32) { i ->
                hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
            }
            return try { store.save(host, port, bytes, pin) }
            finally { bytes.fill(0) }
        } finally {
            // Private one-time bootstrap, never persisted in plaintext on the TV.
            file.delete()
        }
    }
}
