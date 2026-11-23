"""Offline VieNeu SDK adapter contract using injected fake engine."""
import unittest

from voiceover_revision import NarrationCue
from voiceover_vieneu import VieNeuOnnxSession


class FakeEngine:
    def __init__(self):
        self.calls = []
        self.closed = False

    def infer_stream(self, text, *, voice):
        self.calls.append((text, voice))
        yield [0.0, 0.1]
        yield [0.2]

    def close(self):
        self.closed = True


class VieNeuAdapterTests(unittest.TestCase):
    def test_owner_selected_ngoc_linh_is_default_and_lazy(self):
        from voiceover_vieneu import DEFAULT_VOICE_CACHE_ID, DEFAULT_VOICE_PRESET
        from voiceover_revision import plan_voiceover
        self.assertEqual(DEFAULT_VOICE_PRESET, "Ngọc Linh")
        self.assertEqual(DEFAULT_VOICE_CACHE_ID, "ngoc_linh_v3turbo_onnx")
        session = VieNeuOnnxSession(factory=FakeEngine)
        self.assertEqual(session.voice, "Ngọc Linh")
        self.assertIsNone(session._engine)
        cue = NarrationCue(1, 0, 1500, "Thuyết minh phim", "a" * 64)
        self.assertEqual(len(list(session.stream(cue))), 2)
        self.assertEqual(session._engine.calls,
                         [("Thuyết minh phim", "Ngọc Linh")])
        session.close()

    def test_one_local_engine_reused_across_cues(self):
        engines = []

        def factory():
            engine = FakeEngine()
            engines.append(engine)
            return engine

        session = VieNeuOnnxSession(voice="Minh Đức", factory=factory)
        cue1 = NarrationCue(1, 0, 1500, "Xin chào", "0" * 64)
        cue2 = NarrationCue(2, 2000, 3500, "Tiếp theo", "1" * 64)
        self.assertEqual(len(engines), 0)
        self.assertEqual(len(list(session.stream(cue1))), 2)
        self.assertEqual(len(list(session.stream(cue2))), 2)
        self.assertEqual(len(engines), 1)
        self.assertEqual(engines[0].calls,
                         [("Xin chào", "Minh Đức"), ("Tiếp theo", "Minh Đức")])
        session.close()
        self.assertTrue(engines[0].closed)

    def test_rejects_invalid_cue_before_provider(self):
        session = VieNeuOnnxSession(voice="v", factory=lambda: FakeEngine())
        with self.assertRaisesRegex(ValueError, "VIENEU_TIMED"):
            list(session.stream(NarrationCue(1, 20, 10, "abc", "0" * 64)))
        self.assertIsNone(session._engine)

    def test_empty_stream_fails(self):
        class Empty:
            def infer_stream(self, text, *, voice):
                return iter(())

        session = VieNeuOnnxSession(voice="v", factory=Empty)
        with self.assertRaisesRegex(ValueError, "VIENEU_EMPTY_STREAM"):
            list(session.stream(NarrationCue(1, 0, 2000, "hi", "0" * 64)))


if __name__ == "__main__":
    unittest.main()
