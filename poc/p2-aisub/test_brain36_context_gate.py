"""Source-only tests for Brain36 non-mutating structural/context gate."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from brain36_context_gate import audit


def fixtures():
    cases = [{"id": i, "genre": ("action" if i <= 18 else "family"),
              "scene_context": "Two fictional people talk.", "speaker": "Fictional person",
              "source_english": "A fictional line.", "risk_focus": "pronoun"} for i in range(1, 37)]
    cases[0]["risk_focus"] = "sarcasm"
    corpus = {"corpus": "P2-AISUB.2a-original-synthetic-context-v1", "cases": cases}
    raw = json.dumps(corpus, ensure_ascii=False).encode("utf-8")
    translations = [{"id": i, "vi": "Tôi đang nói chuyện."} for i in range(1, 37)]
    translations[0]["vi"] = "Phu nhân đã đến. Hắn đang chờ. " + "A" * 44
    export = {"schema": "P2-AISUB.2f-brain-input-v1", "blind_label": "A",
              "corpus_sha256": hashlib.sha256(raw).hexdigest(),
              "machine_readability_not_semantic_pass": True, "translations": translations}
    return raw, corpus, export


class Brain36ContextGateTests(unittest.TestCase):
    def test_actual_repo_corpus_lf_and_windows_crlf_sha_are_equivalent(self):
        from brain36_context_gate import _corpus_sha_variants
        source = Path(__file__).with_name("benchmark_synthetic.json").read_bytes()
        lf, crlf = _corpus_sha_variants(source)
        self.assertEqual(lf, "3e367c1544c2614b44b2a99e6d083ddd61272ab0d773c5410cc9b40914476a31")
        self.assertEqual(crlf, "9b1e787c79af7866a81921f57e55f9aa4332e5b316fd122d539dbcff185459ca")

    def test_crlf_declaration_accepted_against_lf_checkout_only(self):
        raw, corpus, export = fixtures()
        lf = (json.dumps(corpus, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        crlf = lf.replace(b"\n", b"\r\n")
        declared = hashlib.sha256(crlf).hexdigest()
        export["corpus_sha256"] = declared
        first = audit(lf, corpus, export)
        second = audit(crlf, corpus, export)
        self.assertEqual(first["source_corpus_sha256"], declared)
        self.assertEqual(first["source_corpus_canonical_lf_sha256"],
                         hashlib.sha256(lf).hexdigest())
        self.assertEqual(first["source_corpus_sha256"], second["source_corpus_sha256"])
        edited = lf.replace(b"Two fictional people", b"Two modified people")
        # Source contents changed; SHA cannot be accepted just for matching layout.
        with self.assertRaisesRegex(ValueError, "PROVENANCE_INVALID"):
            audit(edited, corpus, export)
        with self.assertRaisesRegex(ValueError, "BARE_CR_INVALID"):
            audit(lf.replace(b"\n", b"\r"), corpus, export)

    def test_thirty_six_flags_are_review_only(self):
        raw, corpus, export = fixtures()
        report = audit(raw, corpus, export)
        self.assertEqual(report["evaluated_cases"], 36)
        self.assertFalse(report["semantic_quality_certified"])
        self.assertFalse(report["real_timecodes_verified"])
        flags = report["cases"][0]["flags"]
        self.assertIn("HYPOTHETICAL_SPEED_OVER_17_CPS", flags)
        self.assertIn("TITLE_ASSUMPTION_REVIEW", flags)
        self.assertIn("PEJORATIVE_REGISTER_REVIEW", flags)
        self.assertNotIn("CHARACTER_CONTEXT_REVIEW", flags)
        self.assertIn("CHARACTER_CONTEXT_REVIEW", report["cases"][1]["flags"])
        self.assertNotIn("translations", report)
        self.assertNotIn("Phu nhân", json.dumps(report))

    def test_tampered_sha_and_duplicate_ids_fail_closed(self):
        raw, corpus, export = fixtures()
        export["corpus_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "PROVENANCE"):
            audit(raw, corpus, export)
        export["corpus_sha256"] = hashlib.sha256(raw).hexdigest()
        export["translations"][12]["id"] = 12
        with self.assertRaisesRegex(ValueError, "ROW_INVALID"):
            audit(raw, corpus, export)

    def test_no_unverified_boolean_true_and_no_invalid_duration(self):
        raw, corpus, export = fixtures()
        export["machine_readability_not_semantic_pass"] = False
        with self.assertRaisesRegex(ValueError, "LABEL_OR_STATUS"):
            audit(raw, corpus, export)
        export["machine_readability_not_semantic_pass"] = True
        for duration in (0, -1, float("nan"), float("inf"), True):
            with self.assertRaisesRegex(ValueError, "DURATION_INVALID"):
                audit(raw, corpus, export, assumed_seconds=duration)

    def test_cps_comparison_uses_unrounded_value(self):
        raw, corpus, export = fixtures()
        export["translations"][0]["vi"] = "X" * 43
        # Round(17.004, 2) -> 17.00. A gate using rounded CPS would miss it.
        result = audit(raw, corpus, export, assumed_seconds=43 / 17.004)
        first = result["cases"][0]
        self.assertEqual(first["hypothetical_cps"], 17.0)
        self.assertIn("HYPOTHETICAL_SPEED_OVER_17_CPS", first["flags"])

    def test_canonical_input_digest_changes_if_any_translation_changes(self):
        raw, corpus, export = fixtures()
        original = audit(raw, corpus, export)["input_export_canonical_sha256"]
        export["translations"][1]["vi"] += "!"
        changed = audit(raw, corpus, export)["input_export_canonical_sha256"]
        self.assertNotEqual(original, changed)

    def test_boolean_corpus_id_rejected_even_with_matching_sha(self):
        raw, corpus, export = fixtures()
        corpus["cases"][0]["id"] = True
        raw = json.dumps(corpus, ensure_ascii=False).encode("utf-8")
        export["corpus_sha256"] = hashlib.sha256(raw).hexdigest()
        with self.assertRaisesRegex(ValueError, "CORPUS_IDS_INVALID"):
            audit(raw, corpus, export)

    def test_loader_rejects_duplicate_keys_and_nan(self):
        from brain36_context_gate import _load
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "duplicate.json"
            for raw, expected in (
                (b'{"id":1,"id":2}', "JSON_DUPLICATE_KEY"),
                (b'{"value":NaN}', "JSON_NONFINITE_NUMBER"),
                (b'{"value":Infinity}', "JSON_NONFINITE_NUMBER"),
            ):
                path.write_bytes(raw)
                with self.assertRaisesRegex(ValueError, expected):
                    _load(path)

    def test_output_cannot_overwrite_and_contains_no_dialogue(self):
        raw, corpus, export = fixtures()
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            corp = folder / "corpus.json"
            inp = folder / "brain.json"
            out = folder / "report.json"
            corp.write_bytes(raw)
            inp.write_text(json.dumps(export), encoding="utf-8")
            command = [sys.executable, str(Path(__file__).with_name("brain36_context_gate.py")),
                       "--corpus", str(corp), "--input", str(inp), "--out", str(out)]
            first = subprocess.run(command, text=True, capture_output=True, check=False)
            self.assertEqual(first.returncode, 0, first.stderr)
            report = json.loads(out.read_text())
            self.assertEqual(report["evaluated_cases"], 36)
            self.assertEqual(report["input_export_file_sha256"],
                             hashlib.sha256(inp.read_bytes()).hexdigest())
            self.assertEqual(len(report["input_export_canonical_sha256"]), 64)
            second = subprocess.run(command, text=True, capture_output=True, check=False)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(json.loads(out.read_text())["evaluated_cases"], 36)


if __name__ == "__main__":
    unittest.main()
