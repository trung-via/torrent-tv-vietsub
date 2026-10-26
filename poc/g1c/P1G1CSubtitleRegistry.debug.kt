// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.security.MessageDigest

/**
 * G1c DEBUG PoC only: register one ADB-delivered SRT against a verified
 * (saved server profile ID, torrent hash, file index), then reattach on reopen
 * with the registration marker OFF. No URL, credentials or raw hash is stored.
 *
 * SEL-01 PoC: saves native user-selected G1c ON/OFF per exact media key.
 * Does not infer ON from track presence and does not affect other media.
 */
internal object P1G1CSubtitleRegistry {
    private const val FLAG = "p1-g1c.register"
    private const val FILE_NAME = "p1-g1-external.vi.srt"
    private const val PREFS = "p1-g1c-subtitles"
    private const val LABEL = "P1 G1c - Saved SRT"
    private const val MAX_BYTES = 256 * 1024L
    private val serverIdPattern = Regex("[A-Za-z0-9_-]{1,80}")
    private val torrentHashPattern = Regex("[a-fA-F0-9]{40}")
    private val cuePattern = Regex("""(?m)^\d{1,6}\r?\n\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}""")
    private val hex = "0123456789abcdef".toCharArray()

    private fun digest(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { b ->
            val v = b.toInt() and 0xff
            "" + hex[v ushr 4] + hex[v and 15]
        }

    private fun key(server: String?, hash: String?, fileIndex: Int?): String? {
        if (server == null || !serverIdPattern.matches(server)) return null
        if (hash == null || !torrentHashPattern.matches(hash)) return null
        if (fileIndex == null || fileIndex < 0) return null
        // Prefix and separators prevent ambiguous concatenation.
        return "media." + digest(("p1g1c\u0000" + server + "\u0000" +
            hash.lowercase(java.util.Locale.ROOT) + "\u0000" + fileIndex).toByteArray(Charsets.UTF_8))
    }

    private fun checkedFileDigest(file: File): String? {
        if (!file.isFile || !file.canRead() || file.length() !in 1L..MAX_BYTES) return null
        val bytes = file.readBytes()
        if (bytes.isEmpty() || bytes.size.toLong() > MAX_BYTES) return null
        val text = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes)).toString()
        if (!cuePattern.containsMatchIn(text)) return null
        return digest(bytes)
    }

    /**
     * Called only from the existing PlayerSession.Ui.trackChosen callback.
     * Do not treat track availability as an explicit ON choice.
     * "other" clears an older G1c selection without overriding embedded tracks.
     */
    fun noteTrackChoice(context: Context, r: PlayRequest?, index: Int, choice: TrackChoice) {
        if (choice.audio || r == null || r.engine != EngineMode.VLC) return
        val item = r.queue.getOrNull(index) ?: return
        val mediaKey = key(r.serverProfileId, item.hash, item.fileIndex) ?: return
        try {
            val file = File(context.filesDir, FILE_NAME)
            // Reject any unrelated or spoofed subtitle label in the queue.
            val uri = Uri.fromFile(file).toString()
            if (item.subtitles.none { it.label == LABEL && it.url == uri }) return
            val checksum = checkedFileDigest(file) ?: return
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (prefs.getString(mediaKey, null) != checksum) return

            val value = when {
                choice.off -> "off"
                choice.label == LABEL -> "on"
                else -> "other"
            }
            // Separate from the existing content-hash association value.
            prefs.edit().putString("selection.$mediaKey", value).commit()
        } catch (_: IOException) {
            // Retain existing choice. A read failure must not interrupt playback.
        } catch (_: java.nio.charset.CharacterCodingException) {
        } catch (_: SecurityException) {
        }
    }

    fun prepare(context: Context, r: PlayRequest): PlayRequest {
        if (r.engine != EngineMode.VLC || r.index !in r.queue.indices) return r
        try {
            val file = File(context.filesDir, FILE_NAME)
            val marker = File(context.filesDir, FLAG)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val current = r.queue[r.index]
            val registrationKey = key(r.serverProfileId, current.hash, current.fileIndex)

            // One-shot explicit registration. Always consume to prevent a future
            // wrong movie from claiming a stale marker. Fail closed on missing ID.
            if (marker.isFile) {
                if (!marker.delete()) return r
                val checksum = if (registrationKey == null) null else checkedFileDigest(file)
                if (checksum == null || registrationKey == null) return r
                if (!prefs.edit().putString(registrationKey, checksum).commit()) return r
            }

            // With marker now OFF, only exact keys can restore. Revalidate
            // external bytes on each open; an overwritten/missing SRT is ignored.
            val currentChecksum = checkedFileDigest(file) ?: return r
            val changed = r.queue.toMutableList()
            var found = false
            for (i in changed.indices) {
                val item = changed[i]
                val mediaKey = key(r.serverProfileId, item.hash, item.fileIndex) ?: continue
                if (prefs.getString(mediaKey, null) != currentChecksum) continue
                if (item.subtitles.any { it.label == LABEL }) continue
                changed[i] = item.copy(subtitles = item.subtitles + SubFile(
                    url = Uri.fromFile(file).toString(),
                    label = LABEL,
                    ext = "srt",
                    lang = "vi",
                ))
                found = true
            }
            if (!found) return r
            val withSubs = r.copy(queue = changed)
            val selected = changed[r.index]
            val selectedKey = key(r.serverProfileId, selected.hash, selected.fileIndex) ?: return withSubs
            val uri = Uri.fromFile(file).toString()
            if (selected.subtitles.none { it.label == LABEL && it.url == uri }) return withSubs

            // Only explicit choices for this precise, verified media can win.
            // Use an exact title-only pick: no language fallback onto episode B.
            return when (prefs.getString("selection.$selectedKey", null)) {
                "on" -> withSubs.copy(subPick = listOf(TrackPick(label = LABEL)), subtitlesOn = true)
                "off" -> withSubs.copy(subPick = listOf(TrackPick(off = true)), subtitlesOn = false)
                else -> withSubs
            }
        } catch (_: IOException) {
            return r
        } catch (_: java.nio.charset.CharacterCodingException) {
            return r
        } catch (_: SecurityException) {
            return r
        }
    }
}
