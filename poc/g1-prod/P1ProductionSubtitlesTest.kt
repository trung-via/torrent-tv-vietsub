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

    @Test fun savedSidecarWaitsForLateExternalTrackInsteadOfImpostorEmbeddedTrack() {
        val engine = FakeEngine()
        val ui = object : PlayerSession.Ui {
            override fun changed() {}
            override fun itemEnded() {}
        }
        val sidecar = SubFile("file:///app/a.srt", label, "srt", "vi")
        val q = QueueItem("http://example.invalid/a", "A", "a".repeat(40), 0, listOf(sidecar), 0)
        val session = PlayerSession(engine, ui)
        session.load(request().copy(queue = listOf(q), subPick = listOf(TrackPick(label = label))))

        // VLC initially reports embedded subtitles, including a misleading same-label title.
        val embedded = EngineTrack("embedded", "vi", label)
        engine.subs = listOf(embedded)
        assertEquals(-1, P1ProductionSubtitles.savedSidecarTrackIndex(
            listOf(TrackPick(label = label)), q.subtitles, engine.subs))
        engine.listener!!.onTracksChanged()
        assertEquals("unset", engine.selectedSubId)

        // Once addSlave/mapExternal fires a later track event, select only that file.
        engine.subs = listOf(embedded, EngineTrack("late", "vi", label, external = 0))
        assertEquals(1, P1ProductionSubtitles.savedSidecarTrackIndex(
            listOf(TrackPick(label = label)), q.subtitles, engine.subs))
        engine.listener!!.onTracksChanged()
        assertEquals("late", engine.selectedSubId)

        // The one-shot automatic choice must not override a later manual selection.
        engine.selectedSubId = "user-selected"
        engine.listener!!.onTracksChanged()
        assertEquals("user-selected", engine.selectedSubId)
    }

    @Test fun offAndOtherChoicesAreNotReappliedWhenSavedSidecarArrivesLate() {
        val sidecar = SubFile("file:///app/a.srt", label, "srt", "vi")
        val q = QueueItem("http://example.invalid/a", "A", "a".repeat(40), 0, listOf(sidecar), 0)
        val expected = listOf(TrackPick(label = label))
        assertNull(P1ProductionSubtitles.savedSidecarTrackIndex(
            listOf(TrackPick(off = true)), q.subtitles, emptyList()))
        assertNull(P1ProductionSubtitles.savedSidecarTrackIndex(
            listOf(TrackPick(label = "Other")), q.subtitles, emptyList()))
        assertNull(P1ProductionSubtitles.savedSidecarTrackIndex(
            expected, emptyList(), emptyList()))

        for (selected in listOf("off", "e0")) {
            val engine = FakeEngine()
            val ui = object : PlayerSession.Ui {
                override fun changed() {}
                override fun itemEnded() {}
            }
            val session = PlayerSession(engine, ui)
            session.load(request().copy(queue = listOf(q), subPick = expected))
            engine.subs = listOf(EngineTrack("embedded", "en", "Other"))
            engine.listener!!.onTracksChanged() // saved ON remains pending
            assertEquals("unset", engine.selectedSubId)
            session.selectSub(selected) // explicit user choice wins
            val userChoice = engine.selectedSubId
            engine.subs = engine.subs + EngineTrack("late", "vi", label, external = 0)
            engine.listener!!.onTracksChanged()
            assertEquals(userChoice, engine.selectedSubId)
        }
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
        engine.subs = listOf(EngineTrack("subB", "en", "Other", selected = true))
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
