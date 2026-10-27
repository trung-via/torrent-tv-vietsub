// SPDX-License-Identifier: GPL-3.0-only
package com.spacesarmat.omp.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure G1 validation and episode-bound choice regressions; no TV/Android provider needed. */
class P1ProductionSubtitlesTest {
    private val label = "Vietsub rời (đã lưu)"
    private val srt = "1\n00:00:01,000 --> 00:00:02,500\nTiếng Việt có dấu\n"
    private val vtt = "WEBVTT\n\n00:01.000 --> 00:02.500\nXin chào Việt Nam\n"

    private fun request(
        profile: String? = "server_a1",
        engine: EngineMode = EngineMode.VLC,
        hash: String? = "a".repeat(40),
        index: Int? = 0,
    ): PlayRequest = PlayRequest(
        queue = listOf(QueueItem("http://example.invalid/stream", "Episode", hash, index, emptyList(), 0)),
        index = 0,
        startAtMs = 0,
        seekStep = 10,
        autoNext = false,
        audioLang = "en",
        subLang = "vi",
        subtitlesOn = true,
        session = 10,
        engine = engine,
        serverProfileId = profile,
    )

    @Test fun strictUnicodeAndCueValidation() {
        assertEquals("srt", P1ProductionSubtitles.detectedExtension(srt.toByteArray(Charsets.UTF_8)))
        assertEquals("vtt", P1ProductionSubtitles.detectedExtension(vtt.toByteArray(Charsets.UTF_8)))
        assertNull(P1ProductionSubtitles.detectedExtension("WEBVTT\nno cues".toByteArray()))
        assertNull(P1ProductionSubtitles.detectedExtension("not a subtitle".toByteArray()))
        assertNull(P1ProductionSubtitles.detectedExtension(byteArrayOf(0xC3.toByte(), 0x28)))
        assertNull(P1ProductionSubtitles.detectedExtension((srt + "\u0000").toByteArray()))
        assertNull(P1ProductionSubtitles.detectedExtension(ByteArray(256 * 1024 + 1) { 65 }))
    }

    @Test fun mediaIdentityIsStrictAndEpisodeSpecific() {
        val a = P1ProductionSubtitles.mediaKey(request(), 0)
        assertTrue(a?.startsWith("media.") == true)
        assertNotEquals(a, P1ProductionSubtitles.mediaKey(request(profile = "server_b"), 0))
        assertNotEquals(a, P1ProductionSubtitles.mediaKey(request(hash = "b".repeat(40)), 0))
        assertNotEquals(a, P1ProductionSubtitles.mediaKey(request(index = 1), 0))
        assertNull(P1ProductionSubtitles.mediaKey(request(profile = "bad profile"), 0))
        assertNull(P1ProductionSubtitles.mediaKey(request(hash = "not-a-hash"), 0))
        assertNull(P1ProductionSubtitles.mediaKey(request(index = -1), 0))
        assertNull(P1ProductionSubtitles.mediaKey(request(engine = EngineMode.AUTO), 0))
        assertNull(P1ProductionSubtitles.mediaKey(request(), 1))
    }

    @Test fun episodeTransitionsCannotInheritProductionOnOrOff() {
        val baseline = listOf(TrackPick(label = "Original"))
        val on = P1ProductionSubtitles.transitionPicks("on", true, baseline)
        val off = P1ProductionSubtitles.transitionPicks("off", false, baseline)
        assertEquals(label, on.single().label)
        assertFalse(on.single().off)
        assertTrue(off.single().off)
        assertEquals(baseline, P1ProductionSubtitles.transitionPicks("on", false, baseline))
        assertEquals(baseline, P1ProductionSubtitles.transitionPicks("other", true, baseline))
        assertEquals(baseline, P1ProductionSubtitles.transitionPicks(null, false, baseline))
    }

    @Test fun sessionAppliesEachEpisodeChoiceWithoutDroppingResume() {
        val engine = FakeEngine()
        val ui = object : PlayerSession.Ui {
            override fun changed() {}
            override fun itemEnded() {}
        }
        val sidecar = SubFile("file:///app/a.srt", label, "srt", "vi")
        val q = listOf(
            QueueItem("http://example.invalid/a", "A", "a".repeat(40), 0, listOf(sidecar), 0),
            QueueItem("http://example.invalid/b", "B", "b".repeat(40), 1, emptyList(), 120_000),
        )
        val original = request().copy(queue = q, subPick = listOf(TrackPick(label = label)))
        val session = PlayerSession(engine, ui)
        session.load(original)
        engine.subs = listOf(EngineTrack("subA", "vi", label, external = 0))
        engine.listener?.onTracksChanged()
        assertEquals("subA", engine.selectedSubId)

        engine.positionMs = 55_000
        engine.durationMs = 500_000
        session.goTo(1, subtitlePicksForItem = listOf(TrackPick(off = true)))
        engine.subs = listOf(EngineTrack("subB", "en", "Other"))
        engine.listener?.onTracksChanged()
        assertNull(engine.selectedSubId)
        assertEquals(120_000L, engine.opened.last().second)
        assertEquals(55_000L, session.resumeOf(0))

        engine.positionMs = 150_000
        engine.durationMs = 500_000
        session.goTo(0, subtitlePicksForItem = listOf(TrackPick(label = label)))
        engine.subs = listOf(EngineTrack("subA", "vi", label, external = 0))
        engine.listener?.onTracksChanged()
        assertEquals("subA", engine.selectedSubId)
        assertEquals(55_000L, engine.opened.last().second)
        assertEquals(150_000L, session.resumeOf(1))
    }
}
