"""Offline regressions for subtitle->voice fan-out; no provider or TV."""
from __future__ import annotations

from dataclasses import dataclass, replace
import unittest

from cue_pipeline import Cue, render
from voiceover_revision import plan_voiceover, assess_voice_fit


@dataclass(frozen=True)
class SubtitleRevision:
    """Test-shaped #179 revision until the candidate merges into main."""
    version: int
    source_sha256: str
    media_key: str
    fmt: str
    translated_count: int
    total_count: int
    last_end_ms: int
    sha256: str
    payload: bytes


A = "media." + "a" * 64
B = "media." + "b" * 64


def revision(n: int, *, version: int = 1,
             media: str = A, text_prefix: str = "Lời Việt") -> SubtitleRevision:
    import hashlib
    cues = tuple(Cue(i, (i - 1) * 2000, (i - 1) * 2000 + 1800,
                     f"{text_prefix} {i}") for i in range(1, n + 1))
    data = render(cues, "srt")
    return SubtitleRevision(version, "e" * 64, media, "srt", n, 170,
                            cues[-1].end_ms,
                            hashlib.sha256(data).hexdigest(), data)


class VoiceoverRevisionTests(unittest.TestCase):
    def test_first_batch_and_next_batch_only_new_cues(self):
        first = plan_voiceover(revision(50), voice_id="viet_nam_voice")
        self.assertEqual(len(first.new_cues), 50)
        self.assertEqual(first.new_cues[0].number, 1)
        self.assertEqual(first.new_cues[-1].number, 50)
        keys = tuple(x.tts_key for x in first.new_cues)
        second = plan_voiceover(revision(170, version=2),
                                voice_id="viet_nam_voice",
                                completed_keys=keys)
        self.assertEqual(len(second.new_cues), 120)
        self.assertEqual(second.new_cues[0].number, 51)
        self.assertEqual(second.new_cues[-1].number, 170)
        repeated = plan_voiceover(revision(50), voice_id="viet_nam_voice",
                                  completed_keys=keys)
        self.assertTrue(repeated.is_caught_up)

    def test_wrong_film_voice_or_mutated_old_translation_never_reuses_audio(self):
        keys = tuple(x.tts_key for x in plan_voiceover(
            revision(2), voice_id="preset_a").new_cues)
        for changed in (
            dict(revision=revision(3, media=B), voice_id="preset_a"),
            dict(revision=revision(3), voice_id="preset_b"),
            dict(revision=revision(3, text_prefix="Changed"), voice_id="preset_a"),
        ):
            with self.subTest(changed=changed), self.assertRaisesRegex(
                    ValueError, "VOICEOVER_RECEIPT_PREFIX_MISMATCH"):
                plan_voiceover(changed["revision"], voice_id=changed["voice_id"],
                               completed_keys=keys)

    def test_missing_or_failed_audio_not_marked_completed(self):
        first = plan_voiceover(revision(2), voice_id="v")
        one_done = (first.new_cues[0].tts_key,)
        repeated = plan_voiceover(revision(2), voice_id="v",
                                  completed_keys=one_done)
        self.assertEqual([x.number for x in repeated.new_cues], [2])

    def test_invalid_digest_count_and_receipt_rejected(self):
        base = revision(2)
        with self.assertRaisesRegex(ValueError, "DIGEST"):
            plan_voiceover(replace(base, sha256="0" * 64), voice_id="voice")
        with self.assertRaisesRegex(ValueError, "CUES_INVALID"):
            plan_voiceover(replace(base, translated_count=3), voice_id="voice")
        with self.assertRaisesRegex(ValueError, "AHEAD"):
            plan_voiceover(base, voice_id="voice", completed_keys=("0"*64,)*3)

    def test_audio_fit_fallback_not_clipped(self):
        self.assertEqual(assess_voice_fit(cue_duration_ms=2000,
                                          audio_duration_ms=1700), "PLAY_AS_IS")
        self.assertEqual(assess_voice_fit(cue_duration_ms=2000,
                                          audio_duration_ms=2400), "TIME_STRETCH")
        self.assertEqual(assess_voice_fit(cue_duration_ms=2000,
                                          audio_duration_ms=2800),
                         "REWRITE_OR_USE_ORIGINAL_AUDIO")


if __name__ == "__main__":
    unittest.main()
