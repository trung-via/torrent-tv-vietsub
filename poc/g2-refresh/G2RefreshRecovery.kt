// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import java.io.File
import java.net.URI
import java.security.MessageDigest
import java.util.Locale

/**
 * B2: one-shot, same-item G2 rollback. Capture no more than 256 KiB of the old G1-owned
 * subtitle before G1 importSelected replaces its registry entry and deletes the old file.
 * Never touches a torrent URL, a foreign sidecar or another queue entry.
 */
internal class G2RefreshRecovery private constructor(
    private val original: PlayRequest,
    private val index: Int,
    private val mediaKey: String,
    private val old: SavedOld?,
) {
    private data class SavedOld(val file: File, val bytes: ByteArray, val digest: String)
    private var expected: PlayRequest? = null
    private var fallback: PlayRequest? = null
    var wasPaused: Boolean = false
        private set

    fun arm(refreshed: PlayRequest, previous: PlayRequest, paused: Boolean) {
        check(expected == null && P1ProductionSubtitles.mediaKey(refreshed, index) == mediaKey)
        expected = refreshed
        fallback = previous
        wasPaused = paused
    }

    fun matchesCurrent(current: PlayRequest?, currentIndex: Int): Boolean =
        expected != null && current === expected && currentIndex == index &&
            P1ProductionSubtitles.mediaKey(current, currentIndex) == mediaKey

    /** Restore an old file only at its original, G1 identity-scoped location. No registry rollback:
     *  newly imported Vietsub is still saved for the next intentional playback open.
     */
    fun restoreOldFile(): Boolean {
        val saved = old ?: return true
        return try {
            val file = saved.file
            if (file.isFile) return file.length() == saved.bytes.size.toLong() &&
                digest(file.readBytes()) == saved.digest
            if (file.exists() || !file.parentFile.isDirectory) return false
            val tmp = File.createTempFile("g2-restore-", ".tmp", file.parentFile)
            try {
                tmp.writeBytes(saved.bytes)
                if (digest(tmp.readBytes()) != saved.digest || !tmp.renameTo(file)) return false
            } finally { tmp.delete() }
            file.isFile && digest(file.readBytes()) == saved.digest
        } catch (_: Exception) { false }
    }

    /** If old bytes cannot be recovered, reopen video with that one invalid G1-owned URI removed. */
    fun rollbackRequest(oldRestored: Boolean): PlayRequest? {
        val prior = fallback ?: return null
        if (oldRestored || old == null) return prior
        val q = prior.queue.toMutableList()
        q[index] = q[index].copy(subtitles = q[index].subtitles.filterNot {
            it.label == G1_LABEL && G2RefreshDecision.isScopedOldFile(
                it.url, mediaKey, old.file.parentFile)
        })
        return prior.copy(queue = q, subPick = emptyList(), subtitlesOn = false)
    }

    companion object {
        private const val MAX_BYTES = 256 * 1024
        private const val G1_LABEL = "Vietsub rời (đã lưu)"
        private val shaName = Regex("^[0-9a-f]{64}\\.([0-9a-f]{64})\\.(srt|vtt)$")

        private fun digest(bytes: ByteArray): String =
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
                "%02x".format(Locale.ROOT, it.toInt() and 255)
            }

        fun capture(ctx: Context, playing: PlayRequest, idx: Int): G2RefreshRecovery? {
            if (playing.engine != EngineMode.VLC || playing.index != idx ||
                idx !in playing.queue.indices) return null
            val key = P1ProductionSubtitles.mediaKey(playing, idx) ?: return null
            val items = playing.queue[idx].subtitles.filter { it.label == G1_LABEL }
            if (items.size > 1) return null
            if (items.isEmpty()) return G2RefreshRecovery(playing, idx, key, null)
            val folder = File(ctx.filesDir, "p1-production-subtitles")
            val url = items.single().url
            if (!G2RefreshDecision.isScopedOldFile(url, key, folder)) return null
            val saved = try {
                val f = File(URI(url)).canonicalFile
                if (!f.isFile || f.length() !in 1L..MAX_BYTES.toLong()) return null
                val bytes = f.readBytes()
                val hash = shaName.matchEntire(f.name)?.groupValues?.get(1) ?: return null
                if (digest(bytes) != hash) return null
                SavedOld(f, bytes, hash)
            } catch (_: Exception) { return null }
            return G2RefreshRecovery(playing, idx, key, saved)
        }
    }
}
