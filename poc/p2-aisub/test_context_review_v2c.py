"""P2-AISUB v2c original synthetic continuity/readability QA tests."""
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

from context_review_v2c import (
    SCHEMA, CONFIRM, analyze_review, build_review_template, main,
)
from context_memory_v2b import _stable_digest
from context_engine_v2 import _canonical_source_sha256
from cue_pipeline import parse_cues, render

FIX = Path(__file__).with_name("fixtures")
SRT = FIX / "agy_scene12_en.srt"
CONTEXT = FIX / "context_v2_synthetic.json"
MEMORY = FIX / "context_memory_v2b_synthetic.json"
VI = FIX / "context_review_v2c_translations.json"


def fixture():
    return (SRT.read_bytes(),
            json.loads(CONTEXT.read_text(encoding="utf-8")),
            json.loads(MEMORY.read_text(encoding="utf-8")),
            json.loads(VI.read_text(encoding="utf-8")))


def template():
    source, meta, memory, vi = fixture()
    return build_review_template(source, "srt", meta, memory, vi)


def evaluate(review=None, *, source=None, meta=None, memory=None, vi=None,
             fmt="srt"):
    original, base, journal, translations = fixture()
    return analyze_review(
        original if source is None else source, fmt,
        base if meta is None else meta,
        journal if memory is None else memory,
        translations if vi is None else vi,
        template() if review is None else review,
    )


def checked(term):
    return {"status": "explicit", "term": term}


class ContinuityReviewV2CTests(unittest.TestCase):

    def test_template_pins_all_source_context_memory_and_translation(self):
        source, meta, memory, vi = fixture()
        report = template()
        self.assertEqual(report["schema"], SCHEMA)
        self.assertEqual(report["source_sha256"], _canonical_source_sha256(source))
        self.assertEqual(report["base_context_sha256"], _stable_digest(meta))
        self.assertEqual(report["memory_sha256"], _stable_digest(memory))
        self.assertEqual(report["translation_sha256"], _stable_digest(vi))
        self.assertEqual([x["id"] for x in report["rows"]], list(range(1, 13)))
        self.assertTrue(all(x["candidate_vi"] is None for x in report["rows"]))
        self.assertTrue(all(x["self_use"]["status"] == "unchecked" for x in report["rows"]))

    def test_default_unchecked_is_not_misreported_as_wrong_pronouns(self):
        result = evaluate()
        self.assertEqual(result["total_cues"], 12)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"], 0)
        self.assertEqual(result["unchecked_pronoun_fields"], 24)
        self.assertFalse(result["quality_certified"])
        self.assertEqual(result["human_semantic_review"], "REQUIRED")
        self.assertFalse(result["subtitle_rewritten"])
        self.assertFalse(result["model_or_network_call"])

    def test_explicit_scene_2_em_fails_against_v2b_toi_but_scene_1_em_passes(self):
        review = template()
        review["rows"][0]["self_use"] = checked("em")
        review["rows"][0]["other_use"] = checked("anh")
        review["rows"][6]["self_use"] = checked("em")
        review["rows"][6]["other_use"] = checked("anh")
        result = evaluate(review)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"], 1)
        rows = {x["id"]: x for x in result["rows"]}
        self.assertNotIn(1, rows)  # A clean cue is intentionally omitted from warning-only rows.
        self.assertIn("SELF_PRONOUN_MISMATCH_REVIEW", rows[7]["codes"])
        self.assertNotIn("OTHER_PRONOUN_MISMATCH_REVIEW", rows[7]["codes"])

    def test_scene_two_toi_approved_as_declared_term_not_semantics(self):
        review = template()
        review["rows"][6]["self_use"] = checked("tôi")
        review["rows"][6]["other_use"] = checked("anh")
        result = evaluate(review)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"], 0)
        self.assertFalse(result["quality_certified"])
        self.assertEqual(result["human_semantic_review"], "REQUIRED")

    def test_reciprocal_direction_does_not_inherit_reverse_transition(self):
        review=template()
        review["rows"][7]["self_use"]=checked("anh")
        review["rows"][7]["other_use"]=checked("em")
        result=evaluate(review)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"],0)
        review["rows"][7]["self_use"]=checked("tôi")
        result=evaluate(review)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"],1)

    def test_omitted_pronouns_are_not_false_mismatches(self):
        review=template()
        review["rows"][6]["self_use"]={"status":"omitted","term":None}
        review["rows"][6]["other_use"]={"status":"omitted","term":None}
        result=evaluate(review)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"],0)
        flags={x["id"]:x["codes"] for x in result["rows"]}
        self.assertIn("SELF_PRONOUN_OMITTED_NEEDS_HUMAN_CONTEXT",flags[7])

    def test_unknown_rule_never_claims_any_observed_term_is_wrong(self):
        source,meta,memory,vi=fixture()
        meta["address_rules"]=[]
        memory["base_context_sha256"]=_stable_digest(meta)
        review=build_review_template(source,"srt",meta,memory,vi)
        review["rows"][0]["self_use"]=checked("mình")
        result=evaluate(review,meta=meta,memory=memory)
        self.assertEqual(result["explicit_pronoun_mismatch_cues"],0)
        row={x["id"]:x for x in result["rows"]}[1]
        self.assertIn("SELF_DECLARED_WITHOUT_CONFIRMED_RULE",row["codes"])
        self.assertIn("UNCONFIRMED_PRONOUN_PAIR",row["codes"])

    def test_baseline_real_2500ms_detects_original_overlong_cue_7(self):
        report=evaluate()
        self.assertEqual(report["baseline_readability"]["total_cues"],12)
        issues={x["id"]:x["codes"] for x in report["baseline_readability"]["flags"]}
        self.assertIn(7,issues)
        self.assertIn("READING_SPEED",issues[7])

    def test_candidate_shorter_and_fits_cps_but_no_semantic_certification(self):
        review=template()
        review["rows"][6]["candidate_vi"]="Tôi đâu cho anh quyền chọn thay tôi."
        review["rows"][6]["candidate_meaning_reviewed"]=True
        result=evaluate(review)
        row={x["id"]:x for x in result["rows"]}[7]
        metrics=row["candidate_metrics"]
        self.assertTrue(metrics["shorter"])
        self.assertLess(metrics["candidate_cps_x10"],metrics["original_cps_x10"])
        self.assertEqual(metrics["candidate_readability_codes"],[])
        self.assertTrue(metrics["human_meaning_claim"])
        self.assertTrue(metrics["human_meaning_claim_not_verified"])
        self.assertTrue(metrics["never_auto_applied"])
        self.assertIn("CANDIDATE_MEANING_REVIEW_REQUIRED",row["codes"])
        self.assertFalse(result["quality_certified"])

    def test_candidate_not_shorter_is_flagged(self):
        review=template()
        review["rows"][0]["candidate_vi"]="Đây thực sự chính là một câu rất rất dài khác."
        row={x["id"]:x for x in evaluate(review)["rows"]}[1]
        self.assertIn("CANDIDATE_NOT_SHORTER",row["codes"])

    def test_candidate_remaining_over_17_cps_is_flagged(self):
        review=template()
        review["rows"][6]["candidate_vi"]="Tôi không cho phép anh đưa ra quyết định quan trọng này thay cho tôi lúc này."
        row={x["id"]:x for x in evaluate(review)["rows"]}[7]
        self.assertIn("CANDIDATE_READABILITY_WARNING",row["codes"])
        self.assertIn("READING_SPEED",row["candidate_metrics"]["candidate_readability_codes"])

    def test_candidate_missing_human_claim_always_requests_human_review(self):
        review=template()
        review["rows"][6]["candidate_vi"]="Tôi tự quyết chuyện của mình."
        row={x["id"]:x for x in evaluate(review)["rows"]}[7]
        self.assertIsNone(row["candidate_metrics"]["human_meaning_claim"])
        self.assertIn("CANDIDATE_MEANING_REVIEW_REQUIRED",row["codes"])

    def test_meaning_claim_without_proposed_text_rejected(self):
        review=template()
        review["rows"][0]["candidate_meaning_reviewed"]=True
        with self.assertRaisesRegex(ValueError,"REVIEW_MEANING_CLAIM_WITHOUT_CANDIDATE"):
            evaluate(review)

    def test_bad_candidate_markup_empty_cp437_and_surrogate_rejected(self):
        for candidate in ("", "   ", "<script>Hi</script>", "Anh kh├┤ng", "\ud800"):
            review=template()
            review["rows"][0]["candidate_vi"]=candidate
            with self.subTest(candidate=repr(candidate)),self.assertRaises(ValueError):
                evaluate(review)

    def test_nonbool_candidate_meaning_review_rejected(self):
        review=template()
        review["rows"][0]["candidate_vi"]="Em biết anh đã tới."
        review["rows"][0]["candidate_meaning_reviewed"]="yes"
        with self.assertRaisesRegex(ValueError,"REVIEW_CANDIDATE_MEANING_TYPE_INVALID"):
            evaluate(review)

    def test_missing_extra_duplicate_or_reordered_row_fails_closed(self):
        for mutation in ("missing","duplicate","reverse","extra"):
            review=template()
            if mutation=="missing":review["rows"].pop()
            elif mutation=="duplicate":review["rows"][2]["id"]=1
            elif mutation=="reverse":review["rows"].reverse()
            else:review["rows"].append(deepcopy(review["rows"][-1]))
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                evaluate(review)

    def test_invalid_observation_shape_status_or_term_fails(self):
        for method in ("wrong_status","dangling_term","missing_term","newline","decomposed","wrong_shape"):
            review=template()
            cell=review["rows"][0]["self_use"]
            if method=="wrong_status":cell["status"]="model_guessed"
            elif method=="dangling_term":cell["term"]="em"
            elif method=="missing_term":cell["status"]="explicit"
            elif method=="newline":cell.update(status="explicit",term="em\nanh")
            elif method=="decomposed":cell.update(status="explicit",term="e\u0302m")
            else:cell["new"]="extra"
            with self.subTest(method=method),self.assertRaises(ValueError):
                evaluate(review)

    def test_source_changes_cannot_reuse_review_even_if_old_file_is_present(self):
        source,meta,memory,vi=fixture()
        source=source.replace(b"last train",b"next train")
        with self.assertRaises(ValueError):
            evaluate(source=source)

    def test_review_cannot_reuse_changed_vi_with_same_ids(self):
        source,meta,memory,vi=fixture()
        vi["7"]="Tôi đâu cho anh quyền quyết."
        with self.assertRaisesRegex(ValueError,"REVIEW_PROVENANCE_OR_CONTENT_DRIFT"):
            evaluate(vi=vi)

    def test_review_cannot_reuse_edited_event_notes(self):
        source,meta,memory,vi=fixture()
        memory["events"][0]["note"]+=" Updated hypothetical note."
        with self.assertRaisesRegex(ValueError,"REVIEW_PROVENANCE_OR_CONTENT_DRIFT"):
            evaluate(memory=memory)

    def test_context_authority_change_stops_at_v2b_digest_gate(self):
        source,meta,memory,vi=fixture()
        meta["scenes"][0]["summary"]+=" Edited."
        with self.assertRaisesRegex(ValueError,"MEMORY_SOURCE_OR_CONTEXT_DRIFT"):
            evaluate(meta=meta)

    def test_crlf_source_yields_same_review_report_and_source_identity(self):
        source,meta,memory,vi=fixture()
        windows=source.replace(b"\r\n",b"\n").replace(b"\n",b"\r\n")
        a=evaluate()
        b=evaluate(source=windows)
        self.assertEqual(a,b)
        self.assertEqual(a["source_sha256"],_canonical_source_sha256(source))

    def test_vtt_source_needs_matching_source_and_memory_digests(self):
        source,meta,memory,vi=fixture()
        vtt=render(parse_cues(source,"srt"),"vtt")
        meta["source_sha256"]=_canonical_source_sha256(vtt)
        memory["source_sha256"]=_canonical_source_sha256(vtt)
        memory["base_context_sha256"]=_stable_digest(meta)
        original=build_review_template(vtt,"vtt",meta,memory,vi)
        result=analyze_review(vtt,"vtt",meta,memory,vi,original)
        self.assertEqual(result["total_cues"],12)
        self.assertNotEqual(result["source_sha256"],_canonical_source_sha256(source))

    def test_cli_prepare_enforces_consent_new_file_and_private_stdout(self):
        with TemporaryDirectory() as d:
            target=Path(d)/"review.json"
            args=["v2c","prepare","--input",str(SRT),"--context",str(CONTEXT),
                  "--memory",str(MEMORY),"--translations",str(VI),"--out",str(target)]
            with patch.object(sys,"argv",args),self.assertRaises(SystemExit):
                main()
            self.assertFalse(target.exists())
            with patch.object(sys,"argv",[*args,"--confirm",CONFIRM]),redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(),0)
            self.assertIn("CONTEXT_V2C_REVIEW_TEMPLATE_PREPARED cues=12",output.getvalue())
            self.assertNotIn("Em không chắc",output.getvalue())
            self.assertNotIn(str(SRT),output.getvalue())
            self.assertEqual(json.loads(target.read_text(encoding="utf-8"))["schema"],SCHEMA)
            with patch.object(sys,"argv",[*args,"--confirm",CONFIRM]),self.assertRaises(SystemExit):
                main()

    def test_cli_inspect_emits_only_numeric_ids_and_flags_not_dialogue(self):
        with TemporaryDirectory() as d:
            review=template()
            review["rows"][6]["self_use"]=checked("em")
            review["rows"][6]["candidate_vi"]="Tôi đâu cho anh quyền chọn thay tôi."
            path=Path(d)/"review.json"
            path.write_text(json.dumps(review,ensure_ascii=False),encoding="utf-8")
            args=["v2c","inspect","--input",str(SRT),"--context",str(CONTEXT),
                  "--memory",str(MEMORY),"--translations",str(VI),"--review",str(path)]
            with patch.object(sys,"argv",args),redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(),0)
            text=output.getvalue()
            result=json.loads(text)
            self.assertEqual(result["explicit_pronoun_mismatch_cues"],1)
            self.assertEqual(result["human_draft_candidate_count"],1)
            for sensitive in ("Em chưa từng","Tôi đâu","Mây",str(path),str(SRT)):
                self.assertNotIn(sensitive,text)

    def test_invalid_json_duplicate_keys_nonfinite_and_cp437_map_rejected(self):
        from context_engine_v2 import _strict_json
        for bad in (b'{"id":1,"id":2}',b'{"value":NaN}',b'\xff'):
            with self.assertRaises(ValueError):
                _strict_json(bad)
        source,meta,memory,vi=fixture()
        vi["1"]="N├┤i"
        with self.assertRaisesRegex(ValueError,"CONTEXT_TRANSLATION_CP437_SUSPECTED"):
            build_review_template(source,"srt",meta,memory,vi)

    def test_code_does_not_call_models_network_providers_or_tv(self):
        import inspect
        import context_review_v2c
        code=inspect.getsource(context_review_v2c)
        for needle in ("subprocess.", "requests.", "socket.", "urllib.request",
                       "generateContent(", "agy -p", "api_key", "adb "):
            self.assertNotIn(needle,code)


if __name__ == "__main__":
    unittest.main()
