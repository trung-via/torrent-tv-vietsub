"""Local-only WAV cache and P4-first nonblocking fanout tests."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
import tempfile
from threading import Event
import unittest

from cue_pipeline import Cue, render
from voiceover_revision import NarrationCue
from voiceover_audio_store import VoiceoverWavStore
from voiceover_fanout import DualSubtitleVoiceConsumer, VieNeuBatchConsumer


@dataclass(frozen=True)
class Rev:
    version: int
    source_sha256: str
    media_key: str
    fmt: str
    translated_count: int
    total_count: int
    last_end_ms: int
    sha256: str
    payload: bytes


@dataclass(frozen=True)
class Source:
    media_key: str
    source_sha256: str


KEY = "media." + "a"*64
SRC = "b"*64


def mkrev(version: int = 1, cues: int = 2, media_key: str = KEY) -> Rev:
    rows = tuple(Cue(i, (i-1)*2000, (i-1)*2000+1800, f"Thử {i}")
                 for i in range(1, cues+1))
    payload = render(rows, "srt")
    return Rev(version, SRC, media_key, "srt", cues, 170,
               rows[-1].end_ms, hashlib.sha256(payload).hexdigest(), payload)


class WavStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = VoiceoverWavStore(Path(self.tmp.name))
        self.cue = NarrationCue(1, 1000, 3000, "Xin chào", "d"*64)

    def test_wav_committed_and_reused_without_invoking_stream(self):
        receipt, created = self.store.synthesize(
            self.cue, [[0.0, 0.1, -0.1], [0.5, -0.5]])
        self.assertTrue(created)
        self.assertEqual(receipt.samples, 5)
        self.assertEqual(self.store.read(self.cue), receipt)

        def must_not_run():
            raise AssertionError("provider must not be replayed")
            yield 0.0

        same, created = self.store.synthesize(self.cue, must_not_run())
        self.assertFalse(created)
        self.assertEqual(same, receipt)

    def test_failed_stream_blocks_unknown_effect_without_cache_poisoning(self):
        def broken():
            yield [0.0]
            raise RuntimeError("model failed")

        with self.assertRaisesRegex(RuntimeError, "model failed"):
            self.store.synthesize(self.cue, broken())
        self.assertIsNone(self.store.read(self.cue))
        with self.assertRaisesRegex(ValueError, "INFLIGHT_UNKNOWN_HOLD"):
            self.store.synthesize(self.cue, [[0.0]])
        self.assertFalse((self.store.root / (self.cue.tts_key+".json")).exists())

    def test_tampered_wav_rejected(self):
        self.store.synthesize(self.cue, [[0.0] * 32])
        wav = self.store.root / (self.cue.tts_key+".wav")
        with wav.open("ab") as f:
            f.write(b"tamper")
        with self.assertRaisesRegex(ValueError, "CACHE_VERIFY_FAILED"):
            self.store.read(self.cue)

    def test_bad_pcm_keeps_inflight(self):
        with self.assertRaisesRegex(ValueError, "PCM_RANGE_INVALID"):
            self.store.synthesize(self.cue, [[float("nan")]])
        with self.assertRaisesRegex(ValueError, "INFLIGHT_UNKNOWN_HOLD"):
            self.store.synthesize(self.cue, [[0.0]])


class FanoutTests(unittest.TestCase):
    def test_p4_first_tts_never_blocks_next_subtitle_and_coalesces(self):
        started, release = Event(), Event()
        subtitles, audios = [], []

        def subtitle(_source, revision):
            subtitles.append(revision.version)

        def voice(revision):
            audios.append(revision.version)
            if revision.version == 1:
                started.set()
                release.wait(3)

        flow = DualSubtitleVoiceConsumer(subtitle_sink=subtitle, voice_sink=voice)
        source = Source(KEY, SRC)
        try:
            flow.callback(source, mkrev(version=1))
            self.assertTrue(started.wait(2))
            flow.callback(source, mkrev(version=2, cues=3))
            flow.callback(source, mkrev(version=3, cues=4))
            self.assertEqual(subtitles, [1, 2, 3])
            release.set()
        finally:
            release.set()
            flow.close(wait=True)
        self.assertEqual(audios, [1, 3])

    def test_no_voice_sink_means_no_thread_or_model(self):
        subtitles = []
        flow = DualSubtitleVoiceConsumer(
            subtitle_sink=lambda handoff, rev: subtitles.append(rev.version))
        flow.callback(Source(KEY, SRC), mkrev())
        self.assertEqual(subtitles, [1])
        self.assertIsNone(flow._executor)
        flow.close()

    def test_wrong_media_or_digest_rejected_before_p4(self):
        subtitles = []
        flow = DualSubtitleVoiceConsumer(
            subtitle_sink=lambda handoff, rev: subtitles.append(rev.version))
        try:
            with self.assertRaisesRegex(ValueError, "MEDIA_MISMATCH"):
                flow.callback(Source("media."+"c"*64, SRC), mkrev())
            with self.assertRaisesRegex(ValueError, "SOURCE_MISMATCH"):
                flow.callback(Source(KEY, "d"*64), mkrev())
            self.assertEqual(subtitles, [])
        finally:
            flow.close()

    def test_tts_failure_cannot_retranslate_or_rollback_p4(self):
        subs, events = [], []
        flow = DualSubtitleVoiceConsumer(
            subtitle_sink=lambda _s, rev: subs.append(rev.version),
            voice_sink=lambda rev: (_ for _ in ()).throw(RuntimeError("TTS")),
            status=events.append)
        try:
            flow.callback(Source(KEY, SRC), mkrev())
        finally:
            flow.close()
        self.assertEqual(subs, [1])
        self.assertIn("VOICEOVER_TTS_HOLD_SUBTITLE_UNAFFECTED", events)

    def test_local_failure_isolated_and_recovered_without_replaying_good_cues(self):
        class FlakyTts:
            def __init__(self):
                self.calls = []
            def stream(self, cue):
                self.calls.append(cue.number)
                if cue.number == 1 and self.calls.count(1) == 1:
                    raise RuntimeError("local model failed")
                return [[0.0, 0.25, -0.25]]
        with tempfile.TemporaryDirectory() as root:
            store = VoiceoverWavStore(Path(root))
            tts = FlakyTts()
            events = []
            sink = VieNeuBatchConsumer(wav_store=store, tts=tts, status=events.append)
            self.assertEqual(len(sink(mkrev())), 1)
            self.assertEqual(tts.calls, [1, 2])
            self.assertIn("VOICEOVER_COVERAGE_PARTIAL", events)
            self.assertEqual(len(sink(mkrev())), 2)
            self.assertEqual(tts.calls, [1, 2, 1])
            self.assertEqual(len(sink(mkrev())), 2)
            self.assertEqual(tts.calls, [1, 2, 1])

    def test_real_audio_consumer_uses_only_one_source_revision(self):
        class FakeTts:
            def __init__(self):
                self.calls = []
            def stream(self, cue):
                self.calls.append(cue.number)
                return [[0.0, 0.25, -0.25]]
        with tempfile.TemporaryDirectory() as root:
            store = VoiceoverWavStore(Path(root))
            tts = FakeTts()
            ready = []
            sink = VieNeuBatchConsumer(
                wav_store=store, tts=tts, voice_id="v3turbo_test",
                on_audio_ready=lambda revision, cue, receipt:
                    ready.append((revision.version, cue.number, receipt.tts_key)))
            self.assertEqual(len(sink(mkrev(cues=2))), 2)
            self.assertEqual(len(ready), 2)
            self.assertEqual([row[1] for row in ready], [1, 2])
            self.assertEqual(len(sink(mkrev(cues=2))), 2)
            self.assertEqual(tts.calls, [1, 2])


if __name__ == "__main__":
    unittest.main()
