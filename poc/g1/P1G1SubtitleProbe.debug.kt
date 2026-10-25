// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction

/**
 * P1a G1b diagnostic ONLY. The SRT must arrive via an authorized ADB transfer,
 * not APK assets. This is intentionally NOT a persistent importer or production
 * media association: G1c and the full EXTERNAL_SRT_E2E gate stay UNVERIFIED.
 *
 * The marker is one-shot: after a validated request it is consumed, ensuring
 * a later reopen cannot be mistaken for stored-track persistence.
 */
internal object P1G1SubtitleProbe {
    private const val FLAG = "p1-g1.enable"
    private const val EXTERNAL_NAME = "p1-g1-external.vi.srt"
    private const val LABEL = "P1 G1 - External SRT"
    private const val MAX_BYTES = 256 * 1024L

    fun prepare(context: Context, r: PlayRequest): PlayRequest {
        // The operator must explicitly choose VLC and a current queue item.
        if (r.engine != EngineMode.VLC || r.index !in r.queue.indices) return r
        val marker = File(context.filesDir, FLAG)
        if (!marker.isFile) return r

        val current = r.queue[r.index]
        if (current.subtitles.any { it.label == LABEL }) return r

        val file = File(context.filesDir, EXTERNAL_NAME)
        return try {
            if (!file.isFile || !file.canRead() || file.length() !in 1L..MAX_BYTES) return r

            // Strict UTF-8 and bounded input. No path, media URL or content is logged.
            val data = file.readBytes()
            if (data.isEmpty() || data.size.toLong() > MAX_BYTES) return r
            val decoded = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(data)).toString()
            if (!looksLikeSrt(decoded)) return r

            val updated = r.queue.toMutableList()
            updated[r.index] = current.copy(
                subtitles = current.subtitles + SubFile(
                    url = Uri.fromFile(file).toString(),
                    label = LABEL,
                    ext = "srt",
                    lang = "vi",
                ),
            )

            // No persistent registration: next movie/reopen must have no G1.
            // Do not report G1c persistence or complete G1 E2E from this hook.
            if (!marker.delete()) return r
            r.copy(queue = updated)
        } catch (_: IOException) {
            r
        } catch (_: SecurityException) {
            r
        }
    }

    private fun looksLikeSrt(text: String): Boolean =
        Regex("""(?m)^\d{1,6}\r?\n\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}""")
            .containsMatchIn(text)
}
