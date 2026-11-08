"""P2-AISUB Context Engine v2a: original synthetic/offline/source-scoped tests."""
from __future__ import annotations

from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from context_engine_v2 import (
    CONFIRM, SCHEMA, _strict_json, create_plan, cue_duration_budget,
    inspect_translations, main, validate_manifest,
)
from cue_pipeline import Cue, parse_cues, render

BASE = Path(__file__).with_name("fixtures")
SOURCE = BASE / "agy_scene12_en.srt"
MANIFEST = BASE / "context_v2_synthetic.json"


def fixture():
    source = SOURCE.read_bytes()
    context = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return source, context


def translations():
    return {str(i): "Đã đến." for i in range(1, 13)}


class ContextV2ATests(unittest.TestCase):

    def test_source_sha_and_full_authored_context_are_explicit(self):
        source, meta = fixture()
        self.assertEqual(meta["schema"], SCHEMA)
        self.assertEqual(hashlib.sha256(source).hexdigest(), meta["source_sha256"])
        self.assertEqual(meta["provenance"], "original_synthetic")
        out = validate_manifest(meta, parse_cues(source, "srt"), source)
        self.assertEqual(out["address"][("linh", "minh")]["other"], "anh")
        self.assertEqual(out["address"][("minh", "linh")]["other"], "em")

    def test_two_scenes_12_cues_correct_timing_and_no_cross_scene_context(self):
        source, meta = fixture()
        plan = create_plan(source, "srt", meta)
        self.assertEqual(plan["total_cues"], 12)
        self.assertFalse(plan["model_or_network_call"])
        self.assertEqual([s["scene_id"] for s in plan["scenes"]],
                         ["station_reunion", "station_decision"])
        a, b = [s["batches"][0] for s in plan["scenes"]]
        self.assertEqual([x["id"] for x in a["target"]], list(range(1, 7)))
        self.assertEqual([x["id"] for x in b["target"]], list(range(7, 13)))
        self.assertEqual(a["read_only_after"], [])
        self.assertEqual(b["read_only_before"], [])
        self.assertEqual(a["target"][0]["start_ms"], 3000)
        self.assertEqual(a["target"][0]["end_ms"], 5500)
        self.assertEqual(a["target"][0]["readable_char_budget_17cps"], 42)
        self.assertEqual(a["target"][0]["address"]["self"], "em")
        self.assertEqual(a["target"][1]["address"]["self"], "anh")
        self.assertEqual(a["target"][0]["context_warnings"], [])

    def test_source_content_change_rejected_without_updating_sha(self):
        source, meta = fixture()
        with self.assertRaisesRegex(ValueError, "CONTEXT_SOURCE_SHA256_MISMATCH"):
            create_plan(source.replace(b"last train", b"next train"), "srt", meta)

    def test_wrong_digest_shape_and_source_mismatch_rejected(self):
        source, meta = fixture()
        for altered in ("0" * 64, "XYZ", 123, True):
            changed = deepcopy(meta)
            changed["source_sha256"] = altered
            with self.subTest(altered=altered), self.assertRaises(ValueError):
                create_plan(source, "srt", changed)

    def test_scene_gap_overlap_order_and_coverage_are_fail_closed(self):
        source, meta = fixture()
        for field, value in (("cue_start", 8), ("cue_start", 6),
                             ("cue_end", 13), ("cue_end", 11)):
            changed = deepcopy(meta)
            changed["scenes"][1][field] = value
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                create_plan(source, "srt", changed)
        changed = deepcopy(meta)
        changed["scenes"].pop()
        with self.assertRaisesRegex(ValueError, "CONTEXT_UNCOVERED_CUES"):
            create_plan(source, "srt", changed)

    def test_turns_not_in_order_duplicate_or_missing_are_rejected(self):
        source, meta = fixture()
        changed = deepcopy(meta)
        changed["scenes"][0]["turns"].pop()
        with self.assertRaisesRegex(ValueError, "CONTEXT_SCENE_TURNS_INCOMPLETE"):
            create_plan(source, "srt", changed)
        changed = deepcopy(meta)
        changed["scenes"][0]["turns"][0]["id"] = 3
        with self.assertRaisesRegex(ValueError, "CONTEXT_TURN_ID_MISMATCH"):
            create_plan(source, "srt", changed)
        changed = deepcopy(meta)
        changed["scenes"][1]["id"] = changed["scenes"][0]["id"]
        with self.assertRaises(ValueError):
            create_plan(source, "srt", changed)

    def test_unknown_cast_or_same_sender_and_addressee_rejected(self):
        source, meta = fixture()
        for who in ("missing", "linh"):
            changed = deepcopy(meta)
            changed["scenes"][0]["turns"][0]["addressee"] = who
            with self.subTest(who=who), self.assertRaises(ValueError):
                create_plan(source, "srt", changed)

    def test_conflicting_or_unsupported_directed_pronoun_rules_rejected(self):
        source, meta = fixture()
        changed = deepcopy(meta)
        changed["address_rules"].append(deepcopy(changed["address_rules"][0]))
        with self.assertRaises(ValueError):
            create_plan(source, "srt", changed)
        changed = deepcopy(meta)
        changed["address_rules"][0]["evidence"] = "model_guessed"
        with self.assertRaises(ValueError):
            create_plan(source, "srt", changed)
        changed = deepcopy(meta)
        changed["provenance"] = "human_supplied_local"
        with self.assertRaisesRegex(ValueError, "CONTEXT_REAL_ADDRESS_REQUIRES_HUMAN_REVIEW"):
            create_plan(source, "srt", changed)

    def test_missing_address_rule_reports_unknown_and_never_infers_gender(self):
        source, meta = fixture()
        meta["address_rules"] = []
        plan = create_plan(source, "srt", meta)
        sample = plan["scenes"][0]["batches"][0]["target"][0]
        self.assertIsNone(sample["address"])
        self.assertEqual(sample["context_warnings"], ["UNCONFIRMED_PRONOUN_PAIR"])
        report = inspect_translations(source, "srt", meta, translations())
        self.assertEqual(report["context_warning_count"], 12)
        self.assertFalse(report["quality_certified"])

    def test_unknown_speaker_or_addressee_remains_unknown(self):
        source, meta = fixture()
        meta["scenes"][1]["turns"][0]["speaker"] = None
        plan = create_plan(source, "srt", meta)
        row = plan["scenes"][1]["batches"][0]["target"][0]
        self.assertIsNone(row["address"])
        self.assertIn("SPEAKER_OR_ADDRESSEE_UNKNOWN", row["context_warnings"])

    def test_inspect_timings_are_not_modified_and_quality_is_only_heuristic(self):
        source, meta = fixture()
        before = parse_cues(source, "srt")
        result = inspect_translations(source, "srt", meta, translations())
        self.assertEqual(result["cue_count"], 12)
        self.assertEqual(result["readability"]["flagged_cues"], 0)
        self.assertEqual(result["semantic_review"], "REQUIRED")
        self.assertFalse(result["quality_certified"])
        self.assertTrue(result["pronoun_consistency_not_machine_proven"])
        self.assertTrue(result["no_subtitle_rewrite"])
        self.assertEqual(before, parse_cues(source, "srt"))

    def test_readability_flags_real_duration_without_fake_2p5_second_assumption(self):
        source, meta = fixture()
        revised = translations()
        revised["7"] = "Câu thoại Việt dài thật là dài và vượt xa ngân sách hiển thị 2.5 giây."
        report = inspect_translations(source, "srt", meta, revised)
        self.assertEqual([f["id"] for f in report["readability"]["flags"]], [7])
        self.assertIn("READING_SPEED", report["readability"]["flags"][0]["codes"])
        self.assertEqual(report["readability"]["flags"][0]["duration_ms"], 2500)

    def test_cp437_mojibake_cannot_be_marked_as_clean(self):
        source, meta = fixture()
        revised = translations()
        revised["1"] = "Em kh├┤ng"
        with self.assertRaisesRegex(ValueError, "CONTEXT_TRANSLATION_CP437_SUSPECTED"):
            inspect_translations(source, "srt", meta, revised)

    def test_missing_extra_id_and_non_utf8_translation_rejected(self):
        source, meta = fixture()
        changed = translations()
        del changed["3"]
        with self.assertRaisesRegex(ValueError, "MISSING_OR_EXTRA_TRANSLATED_CUE"):
            inspect_translations(source, "srt", meta, changed)
        changed = translations()
        changed["13"] = "Một câu thêm"
        with self.assertRaises(ValueError):
            inspect_translations(source, "srt", meta, changed)
        changed = translations()
        changed["3"] = "\ud800"
        with self.assertRaisesRegex(ValueError, "CONTEXT_TRANSLATION_UTF8_INVALID"):
            inspect_translations(source, "srt", meta, changed)

    def test_vtt_preserves_actual_milliseconds_and_context_plan(self):
        source, meta = fixture()
        cues = parse_cues(source, "srt")
        vtt = render(cues, "vtt")
        meta["source_sha256"] = hashlib.sha256(vtt).hexdigest()
        plan = create_plan(vtt, "vtt", meta)
        self.assertEqual(plan["format"], "vtt")
        self.assertEqual(plan["scenes"][0]["batches"][0]["target"][0]["start_ms"], 3000)
        self.assertEqual(inspect_translations(vtt, "vtt", meta, translations())["cue_count"], 12)

    def test_large_same_scene_split_retains_only_within_scene_neighbor_context(self):
        cues = tuple(Cue(i, i * 3000, i * 3000 + 2500, f"Input {i}.") for i in range(1, 14))
        source = render(cues, "srt")
        _, meta = fixture()
        meta["source_sha256"] = hashlib.sha256(source).hexdigest()
        meta["scenes"] = [{
            "id": "one_long_scene",
            "cue_start": 1, "cue_end": 13, "summary": "Original synthetic long fictional scene.",
            "turns": [
                {"id": i, "speaker": "linh" if i % 2 else "minh",
                 "addressee": "minh" if i % 2 else "linh"}
                for i in range(1, 14)
            ],
        }]
        plan = create_plan(source, "srt", meta)
        a, b = plan["scenes"][0]["batches"]
        self.assertEqual([x["id"] for x in a["target"]], list(range(1, 13)))
        self.assertEqual([x["id"] for x in b["target"]], [13])
        self.assertEqual([x["id"] for x in b["read_only_before"]], [11, 12])
        self.assertEqual([x["id"] for x in a["read_only_after"]], [13])

    def test_duplicate_json_keys_and_nonfinite_are_rejected(self):
        for raw in (b'{"source_sha256":"a","source_sha256":"b"}',
                    b'{"bad": NaN}', b'{"bad": Infinity}', b'\xff'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                _strict_json(raw)

    def test_cli_prepare_requires_consent_and_is_exclusive_no_text_stdout(self):
        with TemporaryDirectory() as d:
            destination = Path(d) / "context-plan.json"
            args = ["context", "prepare", "--input", str(SOURCE),
                    "--context", str(MANIFEST), "--out", str(destination)]
            with patch.object(sys, "argv", args), self.assertRaises(SystemExit):
                main()
            self.assertFalse(destination.exists())
            with patch.object(sys, "argv", [*args, "--confirm", CONFIRM]):
                with redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(main(), 0)
            self.assertIn("CONTEXT_V2A_PLAN_PREPARED scenes=2 cues=12 no_model_call", out.getvalue())
            self.assertNotIn(str(SOURCE), out.getvalue())
            self.assertNotIn("rainy station", out.getvalue())
            self.assertEqual(json.loads(destination.read_text(encoding="utf-8"))["total_cues"], 12)
            with patch.object(sys, "argv", [*args, "--confirm", CONFIRM]), self.assertRaises(SystemExit):
                main()

    def test_cli_inspect_is_read_only_and_redacts_local_source_text(self):
        source, meta = fixture()
        with TemporaryDirectory() as d:
            t = Path(d) / "translations.json"
            t.write_text(json.dumps(translations()), encoding="utf-8")
            before_source, before_manifest, before_map = SOURCE.read_bytes(), MANIFEST.read_bytes(), t.read_bytes()
            with patch.object(sys, "argv", ["context", "inspect", "--input", str(SOURCE),
                    "--context", str(MANIFEST), "--translations", str(t)]):
                with redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(main(), 0)
            report = json.loads(out.getvalue())
            self.assertEqual(report["cue_count"], 12)
            self.assertNotIn("Đã đến", out.getvalue())
            self.assertNotIn(str(SOURCE), out.getvalue())
            self.assertEqual((SOURCE.read_bytes(), MANIFEST.read_bytes(), t.read_bytes()),
                             (before_source, before_manifest, before_map))

    def test_source_has_no_network_or_model_launch(self):
        import inspect
        import context_engine_v2
        source = inspect.getsource(context_engine_v2)
        for forbidden in ("subprocess.", "requests.", "urllib.request", "socket.",
                          "openai.", "agy -p", "generateContent(", "api_key"):
            self.assertNotIn(forbidden, source)


if __name__ == "__main__":
    unittest.main()
