package com.spacesarmat.omp.player
import android.content.Context
import java.io.File
import kotlin.io.path.createTempDirectory

fun main(){
 val root=createTempDirectory("g2_stub_").toFile()
 val ctx=Context(root)
 val folder=File(root,"p1-production-subtitles").apply { mkdirs() }
 val older=File(folder,"${"a".repeat(64)}.${"b".repeat(64)}.srt").apply {writeText("old")}
 val refreshed=File(folder,"${"a".repeat(64)}.${"c".repeat(64)}.srt").apply{writeText("new")}
 val label="Vietsub rời (đã lưu)"
 val other=SubFile("file:///some/other.srt","Other","srt","en")
 val old=SubFile("file://" + older.absolutePath,label,"srt","vi")
 P1ProductionSubtitles.updatedFile=SubFile("file://" + refreshed.absolutePath,label,"srt","vi")
 val playing=PlayRequest(EngineMode.VLC,0,listOf(QueueItem(listOf(other,old)),QueueItem(emptyList())))
 val output=G2RefreshInPlace.prepare(ctx,playing,0) ?: error("replacement rejected")
 check(output.queue[0].subtitles==listOf(other,P1ProductionSubtitles.updatedFile))
 check(output.queue[1].subtitles.isEmpty())
 check(output.subPick==listOf(TrackPick(label=label))&&output.subtitlesOn)
 check(playing.queue[0].subtitles==listOf(other,old))
 val impostor=playing.copy(queue=listOf(QueueItem(listOf(other,old.copy(url="file:///tmp/not-g1.srt")))))
 check(G2RefreshInPlace.prepare(ctx,impostor,0)==null)
 val multi=playing.copy(queue=listOf(QueueItem(listOf(other,old,old))))
 check(G2RefreshInPlace.prepare(ctx,multi,0)==null)
 check(G2RefreshInPlace.prepare(ctx,playing.copy(engine=EngineMode.AUTO),0)==null)
 println("G2 integration smoke 7/7 PASS (Kotlin/JVM stubs, not Android)")
 root.deleteRecursively()
}