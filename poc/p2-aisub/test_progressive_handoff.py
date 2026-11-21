"""Synthetic-only safety tests for progressive handoff; zero network, provider or TV."""
from __future__ import annotations

import hashlib
import unittest

from cue_pipeline import parse_cues
from progressive_handoff import (
    ProgressiveSubtitleSession, MAX_TARGET_CUES, MAX_TARGET_CHARS, MAX_TV_BYTES,
)

KEY_A = "media." + "a" * 64
KEY_B = "media." + "b" * 64


def time_srt(ms: int) -> str:
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, fraction = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02},{fraction:03}"


def srt(n: int, text: str = "Source dialogue.") -> bytes:
    blocks = []
    for i in range(1, n + 1):
        a = (i - 1) * 1000
        blocks.append(
            f"{i}\n{time_srt(a)} --> {time_srt(a+850)}\n{text} {i}"
        )
    return ("\n\n".join(blocks) + "\n").encode("utf8")


def translate(window, prefix: str = "Lời dịch") -> dict[int, str]:
    return {i: f"{prefix} số {i}" for i in window.ids}


def commit_next(session: ProgressiveSubtitleSession, version: int):
    w = session.next_window()
    assert w is not None
    return session.commit(
        w, translate(w), expected_version=version,
        source_sha256=session.source_sha256,
        media_key=session.media_key,
    )


class OfflineProgressiveTests(unittest.TestCase):
    def test_120_then_240_cumulative_and_original_timeline(self):
        src = srt(245)
        session = ProgressiveSubtitleSession(src, "srt", KEY_A)
        self.assertEqual(len(session.windows), 3)
        self.assertEqual([len(w.ids) for w in session.windows], [120, 120, 5])
        self.assertEqual(session.windows[0].ids[:2], (1, 2))
        self.assertEqual(session.windows[1].ids[:2], (121, 122))
        self.assertEqual([c.number for c in session.windows[1].before], [117, 118, 119, 120])
        self.assertEqual([c.number for c in session.windows[1].after], [241, 242, 243, 244])

        first = commit_next(session, 0)
        self.assertEqual(first.translated_count, 120)
        self.assertEqual(first.last_end_ms, 119850)
        self.assertEqual(first.version, 1)
        second = commit_next(session, 1)
        self.assertEqual(second.translated_count, 240)
        self.assertEqual(second.version, 2)
        third = commit_next(session, 2)
        self.assertTrue(third.complete)
        self.assertEqual(third.translated_count, 245)
        self.assertIsNone(session.next_window())
        self.assertEqual(hashlib.sha256(second.payload).hexdigest(), second.sha256)
        self.assertEqual(first.payload.rstrip(b"\n"), "\n\n".join(
            second.payload.decode("utf8").strip().split("\n\n")[:120]
        ).encode("utf8"))
        parsed = parse_cues(third.payload, "srt")
        original = parse_cues(src, "srt")
        self.assertEqual([(c.start_ms,c.end_ms) for c in parsed],
                         [(c.start_ms,c.end_ms) for c in original])
        self.assertEqual(parsed[130].text, "Lời dịch số 131")
        self.assertEqual(third.media_key, KEY_A)

    def test_warn_before_player_overtakes_translation(self):
        session = ProgressiveSubtitleSession(srt(240), "srt", KEY_A)
        self.assertEqual(session.horizon(0), "NO_SUBTITLES_YET")
        commit_next(session, 0)
        self.assertEqual(session.horizon(30_000), "AVAILABLE")
        self.assertEqual(session.horizon(110_000), "NEAR_TRANSLATED_HORIZON")
        self.assertEqual(session.horizon(119_850), "TRANSLATION_BEHIND_PLAYBACK")
        commit_next(session, 1)
        self.assertEqual(session.horizon(200_000), "AVAILABLE")

    def test_state_is_not_mutated_by_wrong_source_media_or_stale_commit(self):
        session = ProgressiveSubtitleSession(srt(241), "srt", KEY_A)
        w = session.next_window()
        assert w is not None
        for opts in [
            dict(expected_version=1,source_sha256=session.source_sha256,media_key=KEY_A),
            dict(expected_version=0,source_sha256="0"*64,media_key=KEY_A),
            dict(expected_version=0,source_sha256=session.source_sha256,media_key=KEY_B),
        ]:
            with self.subTest(opts=opts), self.assertRaises(ValueError):
                session.commit(w, translate(w), **opts)
            self.assertIsNone(session.revision)
        valid = commit_next(session, 0)
        self.assertEqual(valid.translated_count, 120)
        with self.assertRaisesRegex(ValueError,"STALE_REVISION"):
            session.commit(w,translate(w),expected_version=0,
                           source_sha256=session.source_sha256,media_key=KEY_A)
        self.assertIs(session.revision,valid)

    def test_invalid_provider_maps_do_not_mutate_revision(self):
        session = ProgressiveSubtitleSession(srt(241), "srt", KEY_A)
        first = commit_next(session,0)
        w = session.next_window()
        assert w is not None
        good = translate(w)
        bad_maps = [
            {**good, 9999:"Nội dung thừa"},
            {i:v for i,v in good.items() if i != 200},
            {**good, 121:"<script>"},
            {**good, 122:""},
            {**good, 123:"\ud800"},
            {**good, 124:None},
            dict(reversed(list(good.items()))),
            {str(i):v for i,v in good.items()},
        ]
        for bad in bad_maps:
            with self.subTest(reason=str(list(bad)[:2])), self.assertRaises(ValueError):
                session.commit(w,bad,expected_version=1,
                               source_sha256=session.source_sha256,media_key=KEY_A)
            self.assertIs(session.revision,first)

    def test_wrong_window_from_another_media_rejected(self):
        a = ProgressiveSubtitleSession(srt(240),"srt",KEY_A)
        b = ProgressiveSubtitleSession(srt(240),"srt",KEY_B)
        with self.assertRaisesRegex(ValueError,"WINDOW_IDENTITY_MISMATCH"):
            a.commit(b.next_window(),translate(a.next_window()),
                     expected_version=0,source_sha256=a.source_sha256,media_key=KEY_A)
        self.assertIsNone(a.revision)

    def test_one_large_source_cue_refused_without_splitting(self):
        with self.assertRaisesRegex(ValueError,"SOURCE_CUE_EXCEEDS_BATCH_BUDGET"):
            ProgressiveSubtitleSession(srt(1,"x"*(MAX_TARGET_CHARS+1)), "srt", KEY_A)

    def test_long_source_uses_character_budget_not_fixed_cue_count(self):
        s = ProgressiveSubtitleSession(srt(22, "a"*330), "srt", KEY_A)
        self.assertLess(len(s.windows[0].ids), MAX_TARGET_CUES)
        self.assertEqual(sum(len(w.ids) for w in s.windows),22)
        self.assertTrue(all(sum(len(c.text) for c in w.target) <= MAX_TARGET_CHARS for w in s.windows))

    def test_size_limit_rolls_back_and_keeps_old_output(self):
        session = ProgressiveSubtitleSession(srt(240),"srt",KEY_A)
        w0 = session.next_window()
        assert w0 is not None
        first = session.commit(
            w0, {i:"A"*2000 for i in w0.ids},
            expected_version=0,
            source_sha256=session.source_sha256, media_key=KEY_A,
        )
        w = session.next_window()
        assert w is not None
        huge = {i:"B"*2000 for i in w.ids}
        with self.assertRaisesRegex(ValueError,"TV_SUBTITLE_SIZE_LIMIT"):
            session.commit(w, huge, expected_version=1,
                           source_sha256=session.source_sha256,media_key=KEY_A)
        self.assertIs(session.revision,first)
        self.assertLess(len(first.payload), MAX_TV_BYTES)

    def test_vtt_identifier_settings_and_cumulative_render(self):
        raw = (b"WEBVTT\n\nscene-one\n00:00:01.000 --> 00:00:02.250 align:start\nHello\n"
               b"\nscene-two\n00:00:03.500 --> 00:00:05.000\nGoodbye\n")
        session = ProgressiveSubtitleSession(raw,"vtt",KEY_A,max_cues=1)
        first = commit_next(session,0)
        second = commit_next(session,1)
        self.assertTrue(first.payload.startswith(b"WEBVTT\n"))
        self.assertTrue(second.complete)
        cues = parse_cues(second.payload,"vtt")
        self.assertEqual(cues[0].identifier,"scene-one")
        self.assertEqual(cues[0].settings," align:start")
        self.assertEqual((cues[1].start_ms,cues[1].end_ms),(3500,5000))

    def test_invalid_session_inputs_and_horizon(self):
        for args in [{"max_cues":121},{"max_cues":True},{"max_chars":6501},
                     {"context":-1},{"context":True}]:
            with self.subTest(args=args),self.assertRaises(ValueError):
                ProgressiveSubtitleSession(srt(2),"srt",KEY_A,**args)
        for bad in ["", "film X", KEY_A.upper(), "media." + "xyz"]:
            with self.subTest(key=bad),self.assertRaisesRegex(ValueError,"MEDIA_IDENTITY_REQUIRED"):
                ProgressiveSubtitleSession(srt(2),"srt",bad)
        session = ProgressiveSubtitleSession(srt(2),"srt",KEY_A)
        for invalid in [-1,1.5,True]:
            with self.subTest(value=invalid),self.assertRaises(ValueError):
                session.horizon(invalid)

    def test_does_not_modify_original_source_or_return_times_for_translation(self):
        raw=srt(124)
        original_hash=hashlib.sha256(raw).hexdigest()
        session=ProgressiveSubtitleSession(raw,"srt",KEY_A)
        _=commit_next(session,0)
        self.assertEqual(hashlib.sha256(raw).hexdigest(),original_hash)
        self.assertEqual(session.source_sha256,original_hash)
        self.assertEqual(session.next_window().ids,(121,122,123,124))
        final = commit_next(session,1)
        self.assertTrue(final.complete)
        self.assertEqual(final.translated_count,124)
        self.assertIsNone(session.next_window())

    def test_complete_session_refuses_extra_revision(self):
        session=ProgressiveSubtitleSession(srt(2),"srt",KEY_A)
        commit_next(session,0)
        self.assertIsNone(session.next_window())
        with self.assertRaisesRegex(ValueError,"SESSION_ALREADY_COMPLETE"):
            session.commit(session.windows[0],translate(session.windows[0]),
                           expected_version=1,source_sha256=session.source_sha256,media_key=KEY_A)


if __name__=="__main__":
    unittest.main()
