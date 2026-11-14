// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import java.io.File

/** Candidate G2 bridge: replace G1 sidecar *for the same VLC item* before an in-place playback reload.
 *  This is NOT zero-interruption libVLC hot-add; it can briefly buffer after reload.
 */
internal object G2RefreshInPlace {
    private const val G1_LABEL = "Vietsub rời (đã lưu)"

    fun prepare(ctx: Context, playing: PlayRequest, idx: Int): PlayRequest? {
        if (playing.engine != EngineMode.VLC || idx != playing.index || idx !in playing.queue.indices) return null
        val key = P1ProductionSubtitles.mediaKey(playing, idx) ?: return null
        val oldItem = playing.queue[idx]
        val prior = oldItem.subtitles.filter { it.label == G1_LABEL }
        if (prior.size > 1) return null
        if (prior.isNotEmpty() && !G2RefreshDecision.isScopedOldFile(
                prior.single().url, key, File(ctx.filesDir, "p1-production-subtitles"))) return null

        // Drop only the previously owned G1 URI; never remove ordinary external/embedded choices.
        val newQueue = playing.queue.toMutableList()
        newQueue[idx] = oldItem.copy(subtitles = oldItem.subtitles.filterNot { it.label == G1_LABEL })
        val updated = P1ProductionSubtitles.prepare(ctx, playing.copy(queue = newQueue))
        if (updated.warning != null) return null
        val newFiles = updated.request.queue[idx].subtitles.filter { it.label == G1_LABEL }
        if (newFiles.size != 1 || !newFiles.single().url.startsWith("file://")) return null
        return updated.request.copy(
            index = idx,
            subPick = listOf(TrackPick(label = G1_LABEL)),
            subtitlesOn = true,
        )
    }
}