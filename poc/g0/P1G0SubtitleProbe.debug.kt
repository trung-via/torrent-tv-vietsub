// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.IOException

/**
 * P1 G0 only: opt-in local Unicode SRT render probe, NOT an external-file importer.
 * This class is installed in the Android debug source set only.
 * Explicitly enable with a marker in the debug APK's private filesDir.
 */
internal object P1G0SubtitleProbe {
    private const val FLAG = "p1-g0.enable"
    private const val ASSET = "p1-vietsub-utf8.srt"
    private const val LABEL = "P1 G0 - Việt"

    fun prepare(context: Context, r: PlayRequest): PlayRequest {
        // Fail closed: no injection for Auto/Media3, invalid media, or no debug marker.
        if (r.engine != EngineMode.VLC || r.index !in r.queue.indices) return r
        if (!File(context.filesDir, FLAG).isFile) return r

        val current = r.queue[r.index]
        if (current.subtitles.any { it.label == LABEL }) return r

        // App-private copy; no storage permission, SMB, Android picker or network service.
        val local = File(context.filesDir, ASSET)
        return try {
            context.assets.open(ASSET).use { source ->
                local.outputStream().use { destination -> source.copyTo(destination) }
            }
            val items = r.queue.toMutableList()
            items[r.index] = current.copy(
                subtitles = current.subtitles + SubFile(
                    url = Uri.fromFile(local).toString(),
                    label = LABEL,
                    ext = "srt",
                    lang = "vi",
                ),
            )
            r.copy(queue = items)
        } catch (_: IOException) {
            // The normal player request survives. No input URL, path or secret is logged.
            r
        }
    }
}
