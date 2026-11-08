"""P2-AISUB.2h: synthetic-only tests for Brain-owned review contract."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from brain_semantic_review_v2h import verify, _load, DIMENSIONS


def fake_records():
    cases = []
    translations = []
    reviews = []
    for i in range(1, 37):
        genre = ("action", "romance", "comedy", "mystery", "historical", "family")[(i-1)//6]
        case = {"id": i, "genre": genre, "scene_context": f"Fictional scene {i}",
                "speaker": "Fictional speaker", "source_english": "Hello.",
                "risk_focus": "pronoun"}
        cases.append(case)
        translated = {"id": i, "vi": f"Chào bạn {i}."}
        translations.append(translated)
        reviews.append({
            "id": i, "genre": genre, "scene_context": case["scene_context"],
            "risk_focus": case["risk_focus"], "english": case["source_english"],
            "vietnamese": translated["vi"],
            "scores": {k: 4 for k in DIMENSIONS},
            "hallucination_assessment": "uncertain" if i == 2 else "false",
            "priority": "high" if i == 2 else "low",
            "brain_reason": "Fictional bilingual editorial observation.",
            "suggested_revision": "Chào!",
            "unresolved_context": "Unknown listener." if i == 2 else None,
            "hypothetical_readability": {"real_timestamps_supplied": False},
        })
    corpus = {"corpus": "P2-AISUB.2a-original-synthetic-context-v1", "cases": cases}
    corpus_raw = json.dumps(corpus, ensure_ascii=False).encode()
    export = {
        "schema": "P2-AISUB.2f-brain-input-v1", "corpus_sha256": hashlib.sha256(corpus_raw).hexdigest(),
        "blind_label": "A", "machine_readability_not_semantic_pass": True, "translations": translations
    }
    export_raw = json.dumps(export, ensure_ascii=False).encode()
    review = {
        "schema": "P2-AISUB.2f-brain-editorial-score-v1",
        "source_corpus_sha256": export["corpus_sha256"],
        "input_export_sha256": hashlib.sha256(export_raw).hexdigest(),
        "input_blind_label": "A", "input_schema": export["schema"],
        "authorship": "AI_BRAIN_AUTHORED_NOT_HUMAN",
        "ratings_are_subjective": True, "quality_certified": False,
        "no_independent_model_review_performed": True,
        "case_reviews": reviews,
        "summary": {
            "total": 36, "quality_certified": False, "all_ids_covered": True,
            "score_means": {k: 4.0 for k in DIMENSIONS},
            "hallucination_assessment_counts": {"uncertain": 1, "false": 35},
            "priority_counts": {"high": 1, "low": 35},
        },
    }
    review_raw = json.dumps(review, ensure_ascii=False).encode()
    return corpus_raw, corpus, export_raw, export, review_raw, review


class BrainSemanticReviewV2HTests(unittest.TestCase):
    def call_verify(self, fixture):
        return verify(*fixture)

    def test_36_source_bound_brain_review_is_not_certification(self):
        result = self.call_verify(fake_records())
        self.assertEqual(result["reviewed_cases"], 36)
        self.assertEqual(result["review_owner"], "AI_BRAIN")
        self.assertFalse(result["quality_certified"])
        self.assertEqual(result["independent_semantic_review"], "NOT_PERFORMED")
        self.assertEqual(result["score_means"]["semantic_accuracy"], 4.0)
        self.assertEqual(result["exception_candidates"][0]["id"], 2)
        self.assertEqual(result["exception_candidates"][0]["route"], "BRAIN_CONTEXT_ENRICHMENT_FIRST")
        self.assertTrue(result["legacy_human_scores_unchanged"])
        self.assertNotIn("Chào", json.dumps(result, ensure_ascii=False))

    def test_case_text_tampering_requires_new_brain_review(self):
        fx = list(fake_records())
        fx[3]["translations"][0]["vi"] += "?"
        with self.assertRaisesRegex(ValueError, "CASE_BINDING"):
            self.call_verify(fx)

    def test_changed_export_bytes_fail_even_if_meaning_unchanged(self):
        fx = list(fake_records())
        fx[2] += b" "
        with self.assertRaisesRegex(ValueError, "REVIEW_SOURCE_MISMATCH"):
            self.call_verify(fx)

    def test_human_scores_cannot_be_relabelled_as_brain_or_certified(self):
        for key, value in (
            ("authorship", "HUMAN_REVIEWED"),
            ("quality_certified", True),
            ("ratings_are_subjective", False),
            ("no_independent_model_review_performed", False),
        ):
            fx = list(fake_records())
            fx[5][key] = value
            with self.assertRaisesRegex(ValueError, "PROVENANCE_OR_CERTIFICATION"):
                self.call_verify(fx)

    def test_score_boolean_and_summary_tampering_rejected(self):
        fx = list(fake_records())
        fx[5]["case_reviews"][0]["scores"]["semantic_accuracy"] = True
        with self.assertRaisesRegex(ValueError, "SCORES_INVALID"):
            self.call_verify(fx)
        fx = list(fake_records())
        fx[5]["summary"]["score_means"]["semantic_accuracy"] = 3.5
        with self.assertRaisesRegex(ValueError, "SUMMARY_TAMPERED"):
            self.call_verify(fx)

    def test_malformed_summary_scores_fail_closed(self):
        # A wrong-typed summary must fail with a domain error, not AttributeError.
        for malformed in (None, [], "4.0", {"semantic_accuracy": 4.0}):
            fx = list(fake_records())
            fx[5]["summary"]["score_means"] = malformed
            with self.assertRaisesRegex(ValueError, "SUMMARY_SHAPE_INVALID"):
                self.call_verify(fx)
        for malformed in (True, "4.0", 4.0001):
            fx = list(fake_records())
            fx[5]["summary"]["score_means"]["semantic_accuracy"] = malformed
            with self.assertRaisesRegex(ValueError, "SUMMARY_TAMPERED"):
                self.call_verify(fx)

    def test_forged_boolean_or_string_aggregate_count_rejected(self):
        for name, key in (("hallucination_assessment_counts", "uncertain"),
                          ("priority_counts", "high")):
            for malformed in (True, "1"):
                fx = list(fake_records())
                fx[5]["summary"][name][key] = malformed
                with self.assertRaisesRegex(ValueError, "AGGREGATE_TAMPERED"):
                    self.call_verify(fx)

    def test_context_uncertainty_does_not_forge_human_exception_approval(self):
        fx = list(fake_records())
        fx[5]["case_reviews"][1]["priority"] = "low"
        fx[5]["summary"]["priority_counts"] = {"low": 36}
        result = self.call_verify(fx)
        self.assertEqual(result["exception_candidates"], [])
        self.assertIn("CONTEXT_PENDING", result["status_counts"])
        self.assertNotIn("HUMAN_EXCEPTION_APPROVED", result["status_counts"])

    def test_wrong_corpus_and_forged_real_timestamps_rejected(self):
        fx = list(fake_records())
        fx[3]["corpus_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "EXPORT_SOURCE_OR_SCHEMA"):
            self.call_verify(fx)
        fx = list(fake_records())
        fx[5]["case_reviews"][0]["hypothetical_readability"]["real_timestamps_supplied"] = True
        with self.assertRaisesRegex(ValueError, "TIMING_CLAIM"):
            self.call_verify(fx)

    def test_duplicate_json_keys_and_nan_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "invalid.json"
            for content, pattern in (
                (b'{"x":1,"x":2}', "DUPLICATE_JSON_KEY"),
                (b'{"x":NaN}', "NONFINITE_JSON_VALUE"),
            ):
                path.write_bytes(content)
                with self.assertRaisesRegex(ValueError, pattern):
                    _load(path)

    def test_cli_emits_no_dialogue_and_cannot_overwrite(self):
        fx = fake_records()
        with tempfile.TemporaryDirectory() as folder:
            paths = [Path(folder) / n for n in ("corpus.json", "export.json", "review.json")]
            for path, raw in zip(paths, (fx[0], fx[2], fx[4])):
                path.write_bytes(raw)
            out = Path(folder) / "report.json"
            command = [sys.executable, str(Path(__file__).with_name("brain_semantic_review_v2h.py")),
                       "--corpus", str(paths[0]), "--export", str(paths[1]),
                       "--brain-review", str(paths[2]), "--out", str(out)]
            proc = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertNotIn("Chào", proc.stdout)
            report = json.loads(out.read_text(encoding="utf-8"))
            self.assertEqual(report["reviewed_cases"], 36)
            proc2 = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(proc2.returncode, 0)
            self.assertEqual(json.loads(out.read_text(encoding="utf-8"))["reviewed_cases"], 36)


if __name__ == "__main__":
    unittest.main()
