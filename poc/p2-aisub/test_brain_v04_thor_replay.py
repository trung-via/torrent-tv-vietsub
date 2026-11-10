"""Synthetic fixtures ONLY; never embeds Thor source dialogue."""
from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

from brain_v04_thor_replay import (
    HISTORICAL, RANGES, SOURCE_CUES, SOURCE_SHA256, ThorReplayBlocked,
    baseline, inspect_source, main, prepare_plan,
)
from cue_pipeline import parse_cues


def fake_srt(count=1761):
    entries = []
    for n in range(1, count+1):
        start = 1000 + n * 3000
        end = start + 2000
        def t(ms):
            h, rest = divmod(ms, 3600000)
            m, rest = divmod(rest, 60000)
            s, ms = divmod(rest, 1000)
            return f"{h:02}:{m:02}:{s:02},{ms:03}"
        entries.append(f"{n}\n{t(start)} --> {t(end)}\nThe sample {n} remains synthetic.")
    return ("\n\n".join(entries) + "\n").encode("utf-8")


class ThorReplayTests(unittest.TestCase):
    def test_historical_baseline_is_not_a_new_measurement(self):
        b = baseline()
        self.assertEqual(b["source_sha256"], SOURCE_SHA256)
        self.assertEqual(b["source_cue_count"], 1761)
        self.assertEqual(b["v04_new_generation"], "NOT_RUN")
        self.assertEqual(b["speed_winner"], "NONE")
        self.assertFalse(b["default_change_authorized"])
        self.assertFalse(b["film_text_embedded"])

    def test_archived_v034_3x3_window_totals(self):
        b = baseline()["historical_v034_initial_wall_seconds"]
        self.assertEqual(round(sum(HISTORICAL["QUALITY_60"]), 3), 228.507)
        self.assertEqual(round(sum(HISTORICAL["FAST_120"]), 3), 226.239)
        self.assertEqual(round(sum(HISTORICAL["EXP_160"]), 3), 224.980)
        self.assertEqual([x for x in b["FAST_120"]["per_window"]], [66.091, 85.538, 74.61])

    def test_sha_wrong_rejects_even_structurally_good_srt(self):
        with self.assertRaisesRegex(ThorReplayBlocked, "THOR_EN_EXACT_SHA_REQUIRED"):
            inspect_source(fake_srt())

    def test_synthetic_injected_sha_and_count_verifies_windows(self):
        s = fake_srt()
        v = inspect_source(s, expected_sha=hashlib.sha256(s).hexdigest())
        self.assertEqual((v["cue_count"], v["status"]), (1761, "THOR_EXACT_SOURCE_VERIFIED"))
        self.assertEqual(v["windows"], [[181,340], [561,720], [1081,1240]])
        self.assertEqual(v["translation_performed"], False)

    def test_wrong_cue_count_rejected(self):
        s = fake_srt(1600)
        with self.assertRaisesRegex(ThorReplayBlocked, "THOR_EN_CUE_COUNT_MISMATCH"):
            inspect_source(s, expected_sha=hashlib.sha256(s).hexdigest())

    def test_wrong_encoding_rejected_even_with_known_hash(self):
        invalid = b"\xff\x00"
        with self.assertRaisesRegex(ThorReplayBlocked, "THOR_EN_STRUCTURAL_PARSE_FAILED"):
            inspect_source(invalid, expected_sha=hashlib.sha256(invalid).hexdigest())

    def test_plan_uses_exact_same_three_legacy_windows(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d)/"private.en.srt"
            src.write_bytes(fake_srt())
            work = Path(d)/"fresh-plan"
            received = []
            def planner(s, root, windows, glossary):
                received.append((s, root, windows, glossary))
                return {"trials": 9, "model_calls": 0}
            out = prepare_plan(src, work, planner=planner,
                expected_sha=hashlib.sha256(src.read_bytes()).hexdigest())
            self.assertEqual(received[0][2], RANGES)
            self.assertEqual(out["v04_trial_count"], 9)
            self.assertEqual(out["v04_real_translation"], "NOT_RUN")
            self.assertEqual(out["model_calls"], 0)

    def test_no_existing_dir_overwrite(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d)/"en.srt"
            src.write_bytes(fake_srt())
            work = Path(d)/"old-checkpoints"
            work.mkdir()
            original = work/"checkpoint.json"
            original.write_text("SAFE", encoding="utf-8")
            with self.assertRaisesRegex(ThorReplayBlocked,"THOR_REPLAY_WORKDIR_ALREADY_EXISTS"):
                prepare_plan(src, work, planner=lambda *args: self.fail("should not plan"),
                    expected_sha=hashlib.sha256(src.read_bytes()).hexdigest())
            self.assertEqual(original.read_text(), "SAFE")

    def test_wrong_source_rejected_before_model_or_planner(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d)/"not-thor.en.srt"
            src.write_bytes(fake_srt())
            with self.assertRaisesRegex(ThorReplayBlocked, "THOR_EN_EXACT_SHA_REQUIRED"):
                prepare_plan(src, Path(d)/"new", planner=lambda *args: self.fail("should not plan"))

    def test_unavailable_source_sanitized_cli(self):
        out = io.StringIO()
        with tempfile.TemporaryDirectory() as d:
            secret_path = Path(d)/"PRIVATE_SOURCE_THAT_MUST_NOT_LEAK.srt"
            with redirect_stdout(out):
                rc = main(["precheck", "--source", str(secret_path)])
        self.assertEqual(rc, 2)
        self.assertEqual(json.loads(out.getvalue())["error_code"], "THOR_EN_SOURCE_UNAVAILABLE")
        self.assertNotIn("PRIVATE_SOURCE_THAT_MUST_NOT_LEAK", out.getvalue())

    def test_baseline_cli_safe_to_print(self):
        out = io.StringIO()
        with redirect_stdout(out):
            rc = main(["baseline"])
        b = json.loads(out.getvalue())
        self.assertEqual(rc, 0)
        self.assertEqual(b["speed_winner"], "NONE")
        self.assertNotIn("-->", out.getvalue())

    def test_cannot_claim_new_run_after_plan(self):
        with tempfile.TemporaryDirectory() as d:
            src = Path(d)/"en.srt"
            src.write_bytes(fake_srt())
            p = prepare_plan(src,Path(d)/"new",planner=lambda *args:{"trials":9,"model_calls":0},
                             expected_sha=hashlib.sha256(src.read_bytes()).hexdigest())
            self.assertNotIn("winner", p)
            self.assertEqual(p["speed_winner"], "NONE")


if __name__ == "__main__":
    unittest.main()
