"""Offline, synthetic/full-length P2 EN/VI parity tests. No model or real media."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import unittest
from unittest.mock import patch

from cue_pipeline import Cue, render
from full_srt_pair_qa import audit_pair, main


def cues(count: int, *, vi: bool = False) -> tuple[Cue, ...]:
    return tuple(
        Cue(i, 3000 * i, 3000 * i + 2500,
            ("Xin chào và hẹn gặp lại." if vi else "Hello and see you later."))
        for i in range(1, count + 1)
    )


class FullSrtPairQATests(unittest.TestCase):
    def test_exact_parity_and_private_hash_report(self):
        src = render(cues(3), "srt")
        vi = render(cues(3, vi=True), "srt")
        got = audit_pair(src, vi)
        self.assertEqual(got["status"], "STRUCTURE_PASS_TRANSLATION_UNVERIFIED")
        self.assertEqual(got["cue_count"], 3)
        self.assertEqual(got["cue_timestamp_parity"], "PASS")
        self.assertEqual(got["semantic_fidelity"], "NOT_REVIEWED")
        self.assertEqual(got["real_redmi_playback"], "NOT_RUN")
        self.assertEqual(got["unchanged_source_text_cues"], 0)
        self.assertNotIn("Xin chào", json.dumps(got))
        self.assertNotIn("Hello", json.dumps(got))

    def test_full_1761_cue_synthetic_format_without_text_leak(self):
        src = render(cues(1761), "srt")
        vi = render(cues(1761, vi=True), "srt")
        report = audit_pair(src, vi)
        self.assertEqual(report["cue_count"], 1761)
        self.assertEqual(report["first_start_ms"], 3000)
        self.assertEqual(report["last_end_ms"], 1761 * 3000 + 2500)
        self.assertEqual(report["readability_flagged_count"], 0)

    def test_refuses_missing_cue(self):
        with self.assertRaisesRegex(ValueError, "P2_PAIR_CUE_COUNT_MISMATCH"):
            audit_pair(render(cues(3), "srt"), render(cues(2, vi=True), "srt"))

    def test_refuses_mismatched_time_without_repairing(self):
        changed = list(cues(2, vi=True))
        changed[1] = Cue(2, changed[1].start_ms + 100, changed[1].end_ms, changed[1].text)
        with self.assertRaisesRegex(ValueError, "P2_PAIR_CUE_TIMESTAMP_MISMATCH"):
            audit_pair(render(cues(2), "srt"), render(tuple(changed), "srt"))

    def test_identical_text_is_warning_not_meaning_certification(self):
        both = render(cues(2), "srt")
        report = audit_pair(both, both)
        self.assertEqual(report["unchanged_source_text_cues"], 2)
        self.assertEqual(report["semantic_fidelity"], "NOT_REVIEWED")

    def test_unchanged_id_list_is_bounded(self):
        both = render(cues(100), "srt")
        report = audit_pair(both, both)
        self.assertEqual(report["unchanged_source_text_cues"], 100)
        self.assertEqual(len(report["unchanged_source_text_ids"]), 40)
        self.assertTrue(report["unchanged_ids_truncated"])

    def test_vtt_to_srt_timings_are_compared_as_milliseconds(self):
        src = render(cues(3), "vtt")
        vi = render(cues(3, vi=True), "srt")
        got = audit_pair(src, vi, source_format="vtt", translated_format="srt")
        self.assertEqual(got["cue_timestamp_parity"], "PASS")

    def test_rejects_broken_utf8(self):
        with self.assertRaisesRegex(ValueError, "UTF8_REQUIRED"):
            audit_pair(render(cues(2), "srt"), b"\xff")

    def test_cli_uses_private_files_without_modification_or_text_output(self):
        with TemporaryDirectory() as td:
            en = Path(td) / "private-original.en.srt"
            vi = Path(td) / "private-output.vi.srt"
            original, translated = render(cues(2), "srt"), render(cues(2, vi=True), "srt")
            en.write_bytes(original)
            vi.write_bytes(translated)
            capture = io.StringIO()
            with patch.object(sys, "argv", ["qa", "--source", str(en), "--translated", str(vi)]):
                with redirect_stdout(capture):
                    self.assertEqual(main(), 0)
            report = json.loads(capture.getvalue())
            self.assertEqual(report["cue_count"], 2)
            for prohibited in (str(en), str(vi), "Hello", "Xin chào"):
                self.assertNotIn(prohibited, capture.getvalue())
            self.assertEqual(en.read_bytes(), original)
            self.assertEqual(vi.read_bytes(), translated)

    def test_cli_rejects_same_file_without_disclosing_path(self):
        with TemporaryDirectory() as td:
            p = Path(td) / "private-source.srt"
            original = render(cues(1), "srt")
            p.write_bytes(original)
            capture = io.StringIO()
            with patch.object(sys, "argv", ["qa", "--source", str(p), "--translated", str(p)]):
                with redirect_stdout(capture):
                    self.assertEqual(main(), 2)
            self.assertEqual(json.loads(capture.getvalue())["error_code"],
                             "P2_PAIR_DISTINCT_SOURCE_AND_OUTPUT_REQUIRED")
            self.assertNotIn(str(p), capture.getvalue())
            self.assertEqual(p.read_bytes(), original)

    def test_cli_refuses_bad_input_with_only_status_code(self):
        with TemporaryDirectory() as td:
            en = Path(td) / "secret.srt"
            vi = Path(td) / "translation.srt"
            en.write_bytes(render(cues(1), "srt"))
            vi.write_bytes(b"\xff bad translation")
            capture = io.StringIO()
            with patch.object(sys, "argv", ["qa", "--source", str(en), "--translated", str(vi)]):
                with redirect_stdout(capture):
                    self.assertEqual(main(), 2)
            self.assertEqual(json.loads(capture.getvalue()), {
                "status": "BLOCKED", "error_code": "P2_PAIR_INPUT_OR_STRUCTURE_INVALID",
            })
            self.assertNotIn(str(vi), capture.getvalue())

    def test_readability_warning_does_not_change_time(self):
        src = render((Cue(1, 1000, 1200, "Hello"),), "srt")
        vi = render((Cue(1, 1000, 1200, "Tiếng Việt dài, sẽ hiện quá nhanh."),), "srt")
        report = audit_pair(src, vi)
        self.assertEqual(report["readability_flagged_count"], 1)
        self.assertEqual(report["status"], "STRUCTURE_PASS_TRANSLATION_UNVERIFIED")
        self.assertEqual(report["first_start_ms"], 1000)


if __name__ == "__main__":
    unittest.main()
