package com.spacesarmat.omp.player
import android.content.Context

enum class EngineMode { VLC, AUTO }
data class SubFile(val url: String, val label: String, val ext: String, val lang: String)
data class QueueItem(val subtitles: List<SubFile>)
data class TrackPick(val label: String = "", val off: Boolean = false)
data class PlayRequest(val engine: EngineMode, val index: Int, val queue: List<QueueItem>, val subPick: List<TrackPick> = emptyList(), val subtitlesOn: Boolean = false)

internal object P1ProductionSubtitles {
    data class Prepared(val request: PlayRequest, val warning: String? = null)
    var updatedFile: SubFile? = null
    fun mediaKey(r: PlayRequest, i: Int): String? = if (r.engine == EngineMode.VLC && i in r.queue.indices) "media."+"a".repeat(64) else null
    fun prepare(ctx: Context, r: PlayRequest): Prepared {
        val newFile=updatedFile ?: return Prepared(r)
        val queue=r.queue.toMutableList()
        queue[r.index] = queue[r.index].copy(subtitles = queue[r.index].subtitles + newFile)
        return Prepared(r.copy(queue=queue))
    }
}