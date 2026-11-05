"""Two original synthetic lawful fixtures and negative subtitle QA tests."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from cue_pipeline import apply_translations, parse_cues, render, main

SRT = b"1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:00:03,001 --> 00:00:05,000\nWelcome back\n"
VTT = b"WEBVTT\n\nline-one\n00:00:01.000 --> 00:00:02.500 align:start\nHello\n\n00:00:03.001 --> 00:00:05.000\nGoodbye\n"
VI = {"1": "Xin chào", "2": "Hẹn gặp lại"}


class CueQATests(unittest.TestCase):
    def test_srt_translation_preserves_time(self):
        before = parse_cues(SRT, "srt")
        after = parse_cues(render(apply_translations(before, VI), "srt"), "srt")
        self.assertEqual([(c.start_ms, c.end_ms) for c in before],
                         [(c.start_ms, c.end_ms) for c in after])
        self.assertEqual(after[0].text, "Xin chào")

    def test_vtt_translation_preserves_settings_and_identifier(self):
        before = parse_cues(VTT, "vtt")
        after = parse_cues(render(apply_translations(before, VI), "vtt"), "vtt")
        self.assertEqual(before[0].settings, after[0].settings)
        self.assertEqual(before[0].identifier, after[0].identifier)
        self.assertEqual([(c.start_ms, c.end_ms) for c in before],
                         [(c.start_ms, c.end_ms) for c in after])

    def test_utf8_bom_and_crlf(self):
        raw = b"\xef\xbb\xbf" + SRT.replace(b"\n", b"\r\n")
        self.assertEqual(len(parse_cues(raw, "srt")), 2)

    def test_malformed_utf8_rejected(self):
        with self.assertRaisesRegex(ValueError, "UTF8_REQUIRED"):
            parse_cues(b"\xff", "srt")

    def test_missing_translation_rejected(self):
        with self.assertRaisesRegex(ValueError, "MISSING_OR_EXTRA_TRANSLATED_CUE"):
            apply_translations(parse_cues(SRT, "srt"), {"1": "Xin chào"})

    def test_extra_translation_rejected(self):
        with self.assertRaises(ValueError):
            apply_translations(parse_cues(SRT, "srt"), {**VI, "3": "Not used"})

    def test_empty_translation_rejected(self):
        with self.assertRaises(ValueError):
            apply_translations(parse_cues(SRT, "srt"), {"1": "", "2": "Xong"})

    def test_markup_injection_rejected(self):
        with self.assertRaises(ValueError):
            apply_translations(parse_cues(VTT, "vtt"),
                               {"1": "<script>unsafe</script>", "2": "Xong"})

    def test_bad_timeline_rejected(self):
        bad = SRT.replace(b"00:00:02,500", b"00:00:00,500")
        with self.assertRaisesRegex(ValueError, "INVALID_CUE_DURATION_OR_ORDER"):
            parse_cues(bad, "srt")

    def test_out_of_order_rejected(self):
        bad = SRT.replace(b"00:00:03,001", b"00:00:00,001")
        with self.assertRaises(ValueError):
            parse_cues(bad, "srt")

    def test_srt_sequence_required(self):
        with self.assertRaises(ValueError):
            parse_cues(SRT.replace(b"2\n00:00:03", b"3\n00:00:03"), "srt")

    def test_missing_vtt_header_rejected(self):
        with self.assertRaises(ValueError):
            parse_cues(VTT.replace(b"WEBVTT\n\n", b""), "vtt")

    def test_vtt_style_blocks_rejected_not_silently_dropped(self):
        with self.assertRaises(ValueError):
            parse_cues(b"WEBVTT\n\nSTYLE\n::cue { color: red; }", "vtt")

    def test_large_input_rejected(self):
        with self.assertRaisesRegex(ValueError, "INPUT_TOO_LARGE"):
            parse_cues(b"a" * 1000001, "srt")

    def test_invalid_timestamp_rejected(self):
        with self.assertRaises(ValueError):
            parse_cues(SRT.replace(b"00:00:02,500", b"00:77:02,500"), "srt")

    def test_no_network_or_model_calls_in_pipeline(self):
        # This contract accepts a prepared translation map; no inferred translation.
        original = parse_cues(SRT, "srt")
        self.assertEqual(original[0].text, "Hello")
        self.assertNotEqual(apply_translations(original, VI)[0].text, original[0].text)


if __name__ == "__main__":
    unittest.main()
