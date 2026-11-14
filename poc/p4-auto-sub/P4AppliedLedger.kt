// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import java.security.MessageDigest
import java.util.Locale

/**
 * App-private accepted subtitle cursor. Only a verified G2 first-frame ACK
 * may persist a new accepted version. A crashed/partial preference record
 * blocks pairing instead of silently restarting at version zero.
 *
 * Scope is the triple TV-session/media/source SHA. The full secret and media
 * path are never stored, exported or logged.
 */
internal class P4AppliedLedger(
    ctx: Context, sessionId: String, mediaKey: String, sourceSha256: String,
) {
    private val prefs = ctx.getSharedPreferences("p4-approved-revisions-v1", Context.MODE_PRIVATE)
    private val scope = digest(
        ("TTV-P4-LEDGER-V1:" + sessionId + "|" + mediaKey + "|" + sourceSha256)
            .toByteArray(Charsets.US_ASCII)
    )
    private val versionKey = "$scope.version"
    private val hashKey = "$scope.sha256"

    /** null means corrupt persistent state: refuse re-enrollment. */
    @Synchronized
    fun read(): Pair<Int, String?>? {
        val version = prefs.getInt(versionKey, 0)
        val hash = prefs.getString(hashKey, null)
        if (version == 0 && hash == null) return Pair(0, null)
        if (version !in 1..1_000_000 || hash == null || !SHA.matches(hash)) {
            return null
        }
        return Pair(version, hash)
    }

    /** Fail closed on stale/colliding versions, storage write failure or corruption. */
    @Synchronized
    fun record(version: Int, hash: String): Boolean {
        if (version !in 1..1_000_000 || !SHA.matches(hash)) return false
        val prior = read() ?: return false
        if (version < prior.first) return false
        if (version == prior.first) return prior.second == hash
        return prefs.edit().putInt(versionKey, version).putString(hashKey, hash).commit()
    }

    companion object {
        private val SHA = Regex("[0-9a-f]{64}")
        private fun digest(data: ByteArray): String = MessageDigest.getInstance("SHA-256")
            .digest(data).joinToString("") { "%02x".format(Locale.ROOT, it.toInt() and 255) }
    }
}
