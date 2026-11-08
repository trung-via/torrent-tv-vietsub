"""P2-AISUB.2i synthetic-only tests. Never include real private VI inputs."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from context_challenge_v2i import TARGET_IDS, SCHEMA, validate, write_receipt_new
from test_brain_semantic_review_v2h import fake_records


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sample():
    fx = list(fake_records())
    # Recreate the prior nine-candidate route using fictional, non-user text.
    for row in fx[5]["case_reviews"]:
        if row["id"] in TARGET_IDS:
            row["priority"] = "high"
            row["hallucination_assessment"] = "uncertain"
            row["unresolved_context"] = "Recipient not recorded in synthetic scene."
    fx[5]["summary"]["priority_counts"] = {"high": 9, "low": 27}
    fx[5]["summary"]["hallucination_assessment_counts"] = {"uncertain": 9, "false": 27}
    fx[4] = json.dumps(fx[5], ensure_ascii=False).encode()
    corpus_raw, corpus, export_raw, exported, review_raw, reviewed = fx
    rows = []
    for case_id in TARGET_IDS:
        source = corpus["cases"][case_id - 1]
        vi = exported["translations"][case_id - 1]["vi"]
        prior = reviewed["case_reviews"][case_id - 1]
        rows.append({
            "id": case_id,
            "source_english_sha256": sha(source["source_english"]),
            "vietnamese_sha256": sha(vi),
            "prior_brain_reason_sha256": sha(prior["brain_reason"]),
            "decision": "CONTEXT_PENDING",
            "route": "BRAIN_CONTEXT_ENRICHMENT_FIRST",
            "risk_tags": ["PRONOUN", "UNKNOWN_RECIPIENT"],
            "evidence_fields": ["speaker", "scene_context", "source_english"],
            "unknowns": ["RECIPIENT"],
            "brain_reason": "The source gives no explicit addressee.",
            "candidate_revision": None,
            "recipient_verified": False,
            "independent_review": "NOT_PERFORMED",
            "human_approved": False,
            "quality_certified": False,
            "exception_rationale": None,
        })
    challenge = {
        "schema": SCHEMA,
        "authorship": "AI_BRAIN_SINGLE_REVIEW",
        "source_corpus_canonical_lf_sha256": hashlib.sha256(corpus_raw).hexdigest(),
        "input_export_sha256": hashlib.sha256(export_raw).hexdigest(),
        "input_review_sha256": hashlib.sha256(review_raw).hexdigest(),
        "quality_certified": False,
        "independent_semantic_review": "NOT_PERFORMED",
        "real_timecodes_verified": False,
        "human_approval_claimed": False,
        "case_challenges": rows,
    }
    challenge_raw = json.dumps(challenge, ensure_ascii=False).encode()
    return fx + [challenge_raw, challenge]


class ContextChallengeTests(unittest.TestCase):
    def check(self, fx):
        return validate(*fx, enforce_original=False)

    def test_nine_source_bound_cases_are_not_certification(self):
        fx = sample()
        result = self.check(fx)
        self.assertEqual(result["case_count"], 9)
        self.assertEqual(result["decision_counts"], {"CONTEXT_PENDING": 9})
        self.assertFalse(result["quality_certified"])
        self.assertEqual(result["independent_semantic_review"], "NOT_PERFORMED")
        self.assertEqual([r["id"] for r in result["case_receipts"]], list(TARGET_IDS))
        self.assertNotIn("Chào", json.dumps(result, ensure_ascii=False))
        self.assertNotIn("fictional", json.dumps(result, ensure_ascii=False).lower())

    def test_original_export_pin_fails_closed_for_synthetic_translation(self):
        with self.assertRaisesRegex(ValueError, "ORIGINAL_CORPUS_PIN_MISMATCH"):
            validate(*sample())

    def test_changed_vi_and_source_hash_rejected(self):
        fx = sample()
        fx[3]["translations"][1]["vi"] += "?"
        with self.assertRaisesRegex(ValueError, "REVIEW_CASE_BINDING_MISMATCH"):
            self.check(fx)
        fx = sample()
        fx[7]["case_challenges"][0]["source_english_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "CASE_BINDING_MISMATCH"):
            self.check(fx)

    def test_wrong_prior_review_sha_rejected(self):
        fx = sample()
        fx[7]["input_review_sha256"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "SOURCE_IDENTITY_MISMATCH"):
            self.check(fx)

    def test_missing_duplicate_or_reordered_id_rejected(self):
        for mutate in (
            lambda c: c["case_challenges"].pop(),
            lambda c: c["case_challenges"].__setitem__(0, c["case_challenges"][1]),
            lambda c: c["case_challenges"].reverse(),
        ):
            fx = sample()
            mutate(fx[7])
            with self.assertRaisesRegex(ValueError, "CHALLENGE_COUNT|ID_ORDER_MISMATCH"):
                self.check(fx)

    def test_unverified_recipient_and_fabricated_approval_rejected(self):
        for key, value, pattern in (
            ("recipient_verified", True, "UNGROUNDED_RECIPIENT"),
            ("human_approved", True, "FABRICATED_REVIEW_OR_APPROVAL"),
            ("independent_review", "PASS", "FABRICATED_REVIEW_OR_APPROVAL"),
            ("quality_certified", True, "FABRICATED_REVIEW_OR_APPROVAL"),
        ):
            fx = sample()
            fx[7]["case_challenges"][0][key] = value
            with self.assertRaisesRegex(ValueError, pattern):
                self.check(fx)

    def test_human_exception_needs_brain_assessment_evidence(self):
        fx = sample()
        fx[7]["case_challenges"][0]["route"] = "HUMAN_EXCEPTION_DECISION"
        with self.assertRaisesRegex(ValueError, "PREMATURE_HUMAN_ROUTING"):
            self.check(fx)
        fx[7]["case_challenges"][0].update(decision="BRAIN_ASSESSED",
                                           candidate_revision="Tôi sẽ chờ bạn.",
                                           exception_rationale="A character relationship decision remains.")
        result = self.check(fx)
        self.assertEqual(result["route_counts"]["HUMAN_EXCEPTION_DECISION"], 1)
        self.assertFalse(result["human_exception_approved"])

    def test_context_pending_requires_explicit_unknown_code(self):
        fx = sample()
        fx[7]["case_challenges"][0]["unknowns"] = []
        with self.assertRaisesRegex(ValueError, "PENDING_REQUIRES_EXPLICIT_UNKNOWN"):
            self.check(fx)

    def test_brain_assessed_requires_revision(self):
        fx = sample()
        fx[7]["case_challenges"][0]["decision"] = "BRAIN_ASSESSED"
        with self.assertRaisesRegex(ValueError, "ASSESSED_WITHOUT_REVISION"):
            self.check(fx)

    def test_bad_route_and_unrequested_human_escalation_rejected(self):
        fx = sample()
        fx[7]["case_challenges"][0]["exception_rationale"] = "I demand approval."
        with self.assertRaisesRegex(ValueError, "UNROUTED_HUMAN_EXCEPTION"):
            self.check(fx)
        fx = sample()
        fx[7]["case_challenges"][0]["route"] = "HUMAN_EXCEPTION_APPROVED"
        with self.assertRaisesRegex(ValueError, "DECISION_ROUTE_INVALID"):
            self.check(fx)

    def test_prior_high_priority_set_drifts_fail_closed(self):
        fx = sample()
        fx[5]["case_reviews"][4]["priority"] = "low"
        fx[5]["summary"]["priority_counts"] = {"high": 8, "low": 28}
        with self.assertRaisesRegex(ValueError, "PRIOR_EXCEPTION_SET_CHANGED"):
            self.check(fx)

    def test_receipt_exclusive_write_and_redacted_content(self):
        report = self.check(sample())
        with tempfile.TemporaryDirectory() as folder:
            out = Path(folder) / "receipt.json"
            write_receipt_new(out, report)
            raw = out.read_text(encoding="utf-8")
            self.assertNotIn("Chào", raw)
            self.assertNotIn("Fictional", raw)
            with self.assertRaises(FileExistsError):
                write_receipt_new(out, report)


if __name__ == "__main__":
    unittest.main()
