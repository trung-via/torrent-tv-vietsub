// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import android.content.Context
import java.io.File
import java.security.MessageDigest
import kotlin.io.path.createTempDirectory

/** File recovery and session-identity probes using synthetic bytes, never actual media. */
fun main() {
    val root = createTempDirectory("g2_recovery_").toFile()
    val ctx = Context(root)
    val folder = File(root, "p1-production-subtitles").apply { mkdirs() }
    val key = "a".repeat(64)
    val contents = "1\n00:00:01,000 --> 00:00:03,000\nXin chào\n".toByteArray(Charsets.UTF_8)
    val hash = MessageDigest.getInstance("SHA-256").digest(contents).joinToString("") {
        "%02x".format(it.toInt() and 255)
    }
    val original = File(folder, key + "." + hash + ".srt").apply { writeBytes(contents) }
    val label = "Vietsub rời (đã lưu)"
    val old = SubFile(original.toURI().toString(), label, "srt", "vi")
    val other = SubFile("file:///other/track.srt", "Other", "srt", "en")
    val playing = PlayRequest(EngineMode.VLC, 0, listOf(
        QueueItem(listOf(other, old)), QueueItem(emptyList())
    ))
    var checked = 0
    fun verify(ok: Boolean) { check(ok); checked++ }

    val plan = G2RefreshRecovery.capture(ctx, playing, 0)
    verify(plan != null)
    val recovery = plan!!
    val refreshed = playing.copy(queue = listOf(QueueItem(listOf(other)), QueueItem(emptyList())))
    recovery.arm(refreshed, playing, true)
    verify(recovery.matchesCurrent(refreshed, 0))
    verify(!recovery.matchesCurrent(refreshed.copy(), 0)) // identity, not equality
    verify(!recovery.matchesCurrent(refreshed, 1))
    verify(recovery.wasPaused)
    verify(original.delete())
    verify(recovery.restoreOldFile())
    verify(original.readBytes().contentEquals(contents))
    verify(recovery.rollbackRequest(true) === playing)
    original.writeText("tamper", Charsets.UTF_8)
    verify(!recovery.restoreOldFile())
    verify(recovery.rollbackRequest(false)?.queue?.get(0)?.subtitles == listOf(other))
    verify(recovery.rollbackRequest(false)?.queue?.get(1)?.subtitles?.isEmpty() == true)

    // Never read a foreign or malformed old subtitle.
    val badFile = File(folder, key + "." + "b".repeat(64) + ".srt").apply { writeText("wrong") }
    val bad = playing.copy(queue = listOf(QueueItem(listOf(old.copy(url = badFile.toURI().toString())))))
    verify(G2RefreshRecovery.capture(ctx, bad, 0) == null)
    val foreign = playing.copy(queue = listOf(QueueItem(listOf(old.copy(url = "file:///tmp/outside.srt")))))
    verify(G2RefreshRecovery.capture(ctx, foreign, 0) == null)
    verify(G2RefreshRecovery.capture(ctx, playing.copy(engine = EngineMode.AUTO), 0) == null)
    verify(G2RefreshRecovery.capture(ctx, playing, 1) == null)
    val noOld = playing.copy(queue = listOf(QueueItem(listOf(other))))
    verify(G2RefreshRecovery.capture(ctx, noOld, 0) != null)
    verify(G2RefreshRecovery.capture(ctx, playing.copy(queue = listOf(QueueItem(listOf(old, old)))), 0) == null)

    root.deleteRecursively()
    println("G2 B2 recovery smoke " + checked + "/" + checked + " PASS (Kotlin/JVM stubs only)")
}
