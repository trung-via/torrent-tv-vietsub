"""P2-AISUB.2c subtitle QA tests: pure, synthetic, no provider calls."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import unicodedata
import unittest
from unittest.mock import patch

from cue_pipeline import Cue, parse_cues, render
from subtitle_quality import analyze_cues, main


def cue(number: int, text: str, duration_ms: int = 2500) -> Cue:
    return Cue(number, (number - 1) * 3000, (number - 1) * 3000 + duration_ms, text)


class VietnameseSubtitleQualityTests(unittest.TestCase):
    def test_realistic_synthetic_12_cue_duration_flags_four_over_speed(self):
        lengths = [28, 30, 29, 41, 38, 41, 44, 27, 51, 54, 46, 34]
        cues = tuple(cue(i, "X" * length) for i, length in enumerate(lengths, 1))
        report = analyze_cues(cues)
        flagged = [f for f in report["flags"] if "READING_SPEED" in f["codes"]]
        self.assertEqual([f["id"] for f in flagged], [7, 9, 10, 11])
        self.assertEqual(report["flagged_cues"], 4)
        self.assertEqual(report["flags"][0]["cps_x10"], 176)
        self.assertEqual(report["human_semantic_review"], "REQUIRED")

    def test_exactly_seventeen_cps_is_allowed_and_slightly_more_is_flagged(self):
        acceptable = cue(1, "a" * 42 + "!", duration_ms=2500) # 43 / 2.5 >17
        report = analyze_cues((cue(1, "a" * 34, 2000),))
        self.assertEqual(report["flagged_cues"], 0)
        self.assertEqual(report["status"], "READABILITY_HEURISTICS_PASS")
        self.assertEqual(analyze_cues((acceptable,))["flags"][0]["codes"], ["READING_SPEED", "LINE_TOO_LONG"])

    def test_child_profile_is_more_strict_than_adult(self):
        one = cue(1, "T" * 37)
        self.assertEqual(analyze_cues((one,), profile="adult")["flagged_cues"], 0)
        self.assertEqual(analyze_cues((one,), profile="children")["flags"][0]["codes"], ["READING_SPEED"])

    def test_overlong_line_but_ok_cps_flags_line_only(self):
        report = analyze_cues((cue(1, "a" * 43, 6000),))
        self.assertEqual(report["flags"][0]["codes"], ["LINE_TOO_LONG"])

    def test_two_lines_within_limits_pass_three_lines_warn(self):
        good = cue(1, "Em đến.\nAnh ở đâu?", duration_ms=6000)
        bad = cue(2, "Một\nHai\nBa", duration_ms=6000)
        self.assertEqual(analyze_cues((good,))["flagged_cues"], 0)
        self.assertEqual(analyze_cues((bad,))["flags"][0]["codes"], ["TOO_MANY_LINES"])

    def test_cp437_and_strange_whitespace_are_soft_flags(self):
        sample = cue(1, "Em kh├┤ng  chß║»c.")
        reasons = analyze_cues((sample,))["flags"][0]["codes"]
        self.assertIn("CP437_MOJIBAKE_SUSPECTED", reasons)
        self.assertIn("UNUSUAL_WHITESPACE", reasons)

    def test_non_nfc_is_detected_but_not_rewritten(self):
        text = unicodedata.normalize("NFD", "Đã đến rồi.")
        c = cue(1, text, duration_ms=5000)
        before = c.text
        report = analyze_cues((c,))
        self.assertIn("NON_NFC_TEXT", report["flags"][0]["codes"])
        self.assertEqual(c.text, before)

    def test_unicode_vietnamese_cps_uses_normalized_codepoints(self):
        composed = cue(1, "Chuyện đã qua rồi!", duration_ms=2000)
        decomposed = cue(1, unicodedata.normalize("NFD", composed.text), duration_ms=2000)
        self.assertEqual(
            len(unicodedata.normalize("NFC", decomposed.text)), len(composed.text)
        )
        self.assertEqual(
            analyze_cues((decomposed,))["flags"][0]["char_count"],
            len(composed.text),
        )

    def test_readability_report_does_not_claim_semantic_translation_pass(self):
        report = analyze_cues((cue(1, "Vâng."),))
        self.assertEqual(report["status"], "READABILITY_HEURISTICS_PASS")
        self.assertEqual(report["human_semantic_review"], "REQUIRED")
        self.assertIn("vietnamese_pronouns_and_relationships", report["human_review_dimensions"])
        self.assertIn("semantic_fidelity", report["human_review_dimensions"])

    def test_all_thresholds_are_tunable_bounded(self):
        sample = cue(1, "x" * 51)
        original = analyze_cues((sample,))
        self.assertEqual(original["flagged_cues"], 1)
        changed = analyze_cues((sample,), max_cps=30, max_line_chars=60)
        self.assertEqual(changed["flagged_cues"], 0)
        for kwargs in (
            {"profile": "everything"},
            {"max_cps": 0},
            {"max_cps": float("nan")},
            {"max_cps": float("inf")},
            {"max_line_chars": 5},
            {"max_line_chars": True},
            {"max_lines": 0},
            {"max_lines": False},
        ):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                analyze_cues((sample,), **kwargs)

    def test_invalid_timing_rejected_even_for_direct_cues(self):
        with self.assertRaisesRegex(ValueError, "QUALITY_INVALID_CUE_TIMING"):
            analyze_cues((Cue(1, 1000, 1000, "No."),))

    def test_cli_reads_srt_and_preserves_file_bytes(self):
        original = render((cue(1, "Không có gì đâu."), cue(2, "Em kh├┤ng  rồi.")), "srt")
        with TemporaryDirectory() as d:
            p = Path(d) / "synthetic.srt"
            p.write_bytes(original)
            with patch.object(sys, "argv", ["quality", "--input", str(p)]):
                with redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(), 0)
            result = json.loads(output.getvalue())
            self.assertEqual(result["total_cues"], 2)
            self.assertEqual(result["flags"][0]["id"], 2)
            self.assertNotIn(str(p), output.getvalue())
            self.assertNotIn("kh├┤ng", output.getvalue())
            self.assertEqual(p.read_bytes(), original)

    def test_cli_accepts_vtt_without_modifying_settings(self):
        data = b"WEBVTT\n\nline-x\n00:00:01.000 --> 00:00:05.000 align:start\nHello\n"
        with TemporaryDirectory() as d:
            p = Path(d) / "synthetic.vtt"
            p.write_bytes(data)
            with patch.object(sys, "argv", ["quality", "--input", str(p)]):
                with redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(), 0)
            report = json.loads(output.getvalue())
            self.assertEqual(report["total_cues"], 1)
            self.assertEqual(p.read_bytes(), data)

    def test_cli_rejects_unrelated_file_extensions(self):
        with TemporaryDirectory() as d:
            p = Path(d) / "source.mkv"
            p.write_bytes(b"not a movie")
            with patch.object(sys, "argv", ["quality", "--input", str(p)]):
                with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
                    main()

    def test_source_has_no_file_write_or_network_transport(self):
        import inspect
        import subtitle_quality
        source = inspect.getsource(subtitle_quality)
        for unwanted in (
            "write_bytes(", "write_text(", ".open(\"w", "subprocess", "requests.",
            "urllib.request", "socket.", "api_key", "agy -p",
        ):
            self.assertNotIn(unwanted, source)


if __name__ == "__main__":
    unittest.main()
