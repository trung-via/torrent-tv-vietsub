"""Tests for attended scoring helper using ONLY synthetic test scores, not Human ratings."""
from __future__ import annotations

from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import benchmark36_human as h
from benchmark36 import (
    SCHEMA_TRANSLATIONS, SCORE_FIELDS, batch_cases, corpus, rating_template,
    score_review,
)


def invented_translation(batch: int = 1, label: str = "A") -> dict:
    _, sha = corpus()
    return {
        "schema": SCHEMA_TRANSLATIONS,
        "corpus_sha256": sha,
        "batch": batch,
        "blind_label": label,
        "translations": [
            {"id": x["id"], "vi": f"Câu giả lập số {x['id']}."}
            for x in batch_cases(batch)
        ],
        "usage": {"input_tokens": 100},
        "source": "human_attended_cli_receipt",
        "machine_readability_not_semantic_pass": True,
    }


def complete_draft(batch: int = 1, label: str = "A") -> dict:
    draft = rating_template(batch, label)
    for case in batch_cases(batch):
        draft = h.mark_case(draft, batch, label, case["id"], "5 4 3 2 1 n")
    return draft


class FakeTTY(io.StringIO):
    def isatty(self):
        return True


class HumanScoringTests(unittest.TestCase):

    def test_accept_exact_attended_imported_synthetic_receipt(self):
        for batch in (1, 2, 3):
            art = invented_translation(batch)
            actual, label, rows = h._translation_info(art)
            self.assertEqual((actual, label, len(rows)), (batch, "A", 12))

    def test_blank_draft_is_zero_and_status_has_no_text(self):
        draft = rating_template(1, "A")
        self.assertEqual(h._draft_status(draft, batch=1, label="A"), 0)
        text = h._status(1, draft, "A")
        self.assertEqual(text, "BENCHMARK36_HUMAN_PROGRESS batch=1 scored=0/12 remaining=12 human_input_only")
        self.assertNotIn("Câu giả lập", text)

    def test_manual_line_requires_all_five_ints_and_boolean(self):
        data = h.parse_manual_line("5 4 3 2 1 y")
        self.assertEqual([data[k] for k in SCORE_FIELDS], [5, 4, 3, 2, 1])
        self.assertIs(data["hallucination"], True)
        self.assertIs(h.parse_manual_line("1 1 1 1 1 N")["hallucination"], False)

    def test_bad_manual_score_lines_never_generate_default_values(self):
        for raw in ("", "q", "s", "5 5 5", "5 5 5 5 5", "5 5 5 5 5 maybe",
                    "5 5 5 5 0 n", "0 5 5 5 5 n", "6 5 5 5 5 y",
                    "5 5.0 5 5 5 n", "True 5 5 5 5 y", "5 5 5 5 5 n extra"):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                h.parse_manual_line(raw)

    def test_mark_one_case_does_not_touch_other_blank_rows(self):
        draft = rating_template(1, "A")
        scored = h.mark_case(draft, 1, "A", 1, "4 3 5 2 1 n")
        self.assertEqual(h._draft_status(scored, batch=1, label="A"), 1)
        self.assertEqual(h._draft_status(draft, batch=1, label="A"), 0)
        self.assertEqual(scored["ratings"][0]["relationship_pronouns"], 5)
        self.assertIsNone(scored["ratings"][1]["hallucination"])

    def test_no_silent_overwrite_already_scored_case(self):
        draft = h.mark_case(rating_template(1, "A"), 1, "A", 1, "5 5 5 5 5 n")
        with self.assertRaisesRegex(ValueError, "ALREADY_RECORDED"):
            h.mark_case(draft, 1, "A", 1, "1 1 1 1 1 y")

    def test_outside_batch_case_fails_even_if_valid_scores(self):
        with self.assertRaisesRegex(ValueError, "OUTSIDE_SELECTED_BATCH"):
            h.mark_case(rating_template(2, "A"), 2, "A", 1, "5 5 5 5 5 n")

    def test_partial_fields_or_wrong_id_and_label_fail(self):
        draft = rating_template(1, "A")
        draft["ratings"][0]["semantic_accuracy"] = 5
        with self.assertRaisesRegex(ValueError, "PARTIAL_OR_INVALID"):
            h._draft_status(draft, batch=1, label="A")
        draft = rating_template(1, "A")
        draft["ratings"][1]["id"] = 1
        with self.assertRaisesRegex(ValueError, "ID_OR_KEYS"):
            h._draft_status(draft, batch=1, label="A")
        draft = rating_template(1, "A")
        with self.assertRaisesRegex(ValueError, "PROVENANCE"):
            h._draft_status(draft, batch=1, label="B")

    def test_new_draft_is_preserved_and_companion_binding_written(self):
        with TemporaryDirectory() as d:
            out = Path(d) / "human-draft.json"
            art = invented_translation()
            draft = h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            self.assertEqual(draft, rating_template(1, "A"))
            self.assertTrue(out.is_file())
            self.assertTrue(h._lock_path(out).is_file())
            self.assertEqual(h._load(out), draft)
            self.assertEqual(h._load(h._lock_path(out)), h._binding(art, 1, "A"))

    def test_checkpoint_after_each_case_and_resume_from_same_translation(self):
        with TemporaryDirectory() as d:
            out = Path(d) / "draft.json"
            art = invented_translation()
            draft = h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            scored = h.mark_case(draft, 1, "A", 1, "4 4 3 4 2 n")
            h._checkpoint(out, scored)
            resumed = h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            self.assertEqual(h._draft_status(resumed, batch=1, label="A"), 1)
            self.assertEqual(resumed["ratings"][0]["semantic_accuracy"], 4)
            self.assertIsNone(resumed["ratings"][1]["semantic_accuracy"])

    def test_resume_rejects_altered_translation_text_or_wrong_label(self):
        with TemporaryDirectory() as d:
            out = Path(d) / "draft.json"
            art = invented_translation()
            h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            modified = deepcopy(art)
            modified["translations"][0]["vi"] = "Nội dung khác."
            with self.assertRaisesRegex(ValueError, "TRANSLATION_CHANGED"):
                h._open_or_resume(out, modified, rating_template(1, "A"), 1, "A")
            different = invented_translation(label="B")
            with self.assertRaisesRegex(ValueError, "TRANSLATION_CHANGED"):
                h._open_or_resume(out, different, rating_template(1, "B"), 1, "B")

    def test_missing_binding_fails_closed_not_create_new_scores(self):
        with TemporaryDirectory() as d:
            out = Path(d) / "draft.json"
            art = invented_translation()
            h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            h._lock_path(out).unlink()
            with self.assertRaisesRegex(ValueError, "BINDING_INCOMPLETE"):
                h._open_or_resume(out, art, rating_template(1, "A"), 1, "A")
            self.assertTrue(out.exists())

    def test_different_non_blank_template_cannot_be_initial_state(self):
        with TemporaryDirectory() as d:
            out = Path(d) / "draft.json"
            art = invented_translation()
            bad = complete_draft()
            with self.assertRaisesRegex(ValueError, "ORIGINAL_BLANK_TEMPLATE"):
                h._open_or_resume(out, art, bad, 1, "A")
            self.assertFalse(out.exists())

    def test_cli_review_without_tty_refuses_before_creating_files(self):
        with TemporaryDirectory() as d:
            p=Path(d)
            artfile = p / "translated.json"
            templatefile = p / "scores.json"
            outfile = p / "draft.json"
            artfile.write_text(h._dump(invented_translation()), encoding="utf-8")
            templatefile.write_text(h._dump(rating_template(1,"A")), encoding="utf-8")
            args=["bench","review","--translations",str(artfile),
                  "--template",str(templatefile),"--out",str(outfile),
                  "--confirm",h.CONFIRM]
            with patch.object(sys,"argv",args), self.assertRaises(SystemExit):
                with redirect_stdout(io.StringIO()):
                    h.main()
            self.assertFalse(outfile.exists())

    def test_real_tty_stub_only_explicit_line_creates_a_single_rating(self):
        with TemporaryDirectory() as d:
            out=Path(d)/"draft.json"
            art=invented_translation()
            data=h._open_or_resume(out,art,rating_template(1,"A"),1,"A")
            fakein=FakeTTY("5 4 3 2 1 n\nq\n")
            fakeout=FakeTTY()
            with patch.object(sys,"stdin",fakein),patch.object(sys,"stdout",fakeout):
                h._terminal_score(art,data,out,1,"A")
            self.assertEqual(h._draft_status(h._load(out),batch=1,label="A"),1)
            self.assertIn("Ngữ cảnh:",fakeout.getvalue())
            self.assertIn("VI:",fakeout.getvalue())

    def test_eof_and_q_do_not_populate_unanswered_case(self):
        with TemporaryDirectory() as d:
            out=Path(d)/"draft.json"
            art=invented_translation()
            data=h._open_or_resume(out,art,rating_template(1,"A"),1,"A")
            fakein=FakeTTY("")
            fakeout=FakeTTY()
            with patch.object(sys,"stdin",fakein),patch.object(sys,"stdout",fakeout):
                h._terminal_score(art,data,out,1,"A")
            self.assertEqual(h._draft_status(h._load(out),batch=1,label="A"),0)

    def test_full_manual_mocked_scores_remain_unverified_quality(self):
        art = invented_translation(3)
        draft = complete_draft(3)
        report=score_review(art,draft)
        self.assertEqual(report["batch"],3)
        self.assertEqual(report["summary"]["overall"]["n"],12)
        self.assertEqual(report["summary"]["overall"]["hallucinations"],0)
        self.assertFalse(report["quality_certified"])
        self.assertTrue(report["human_supplied_scores_not_independently_verified"])

    def test_cli_finish_rejects_incomplete_before_output(self):
        with TemporaryDirectory() as d:
            p=Path(d);art=invented_translation()
            artfile=p/"translation.json";artfile.write_text(h._dump(art),encoding="utf-8")
            draftfile=p/"draft.json"
            h._open_or_resume(draftfile,art,rating_template(1,"A"),1,"A")
            reportfile=p/"report.json"
            argv=["bench","finish","--translations",str(artfile),
                  "--draft",str(draftfile),"--report-out",str(reportfile),
                  "--confirm",h.CONFIRM]
            with patch.object(sys,"argv",argv), self.assertRaisesRegex(
                    ValueError,"BATCH_INCOMPLETE"):
                h.main()
            self.assertFalse(reportfile.exists())

    def test_cli_finish_full_produces_standard_schema_and_no_fabrication(self):
        with TemporaryDirectory() as d:
            p=Path(d);art=invented_translation()
            artfile=p/"translation.json";artfile.write_text(h._dump(art),encoding="utf-8")
            draftfile=p/"draft.json"
            h._open_or_resume(draftfile,art,rating_template(1,"A"),1,"A")
            h._checkpoint(draftfile,complete_draft())
            reportfile=p/"report.json"
            argv=["bench","finish","--translations",str(artfile),
                  "--draft",str(draftfile),"--report-out",str(reportfile),
                  "--confirm",h.CONFIRM]
            with patch.object(sys,"argv",argv),redirect_stdout(io.StringIO()) as out:
                self.assertEqual(h.main(),0)
            self.assertTrue(reportfile.exists())
            self.assertIn("BENCHMARK36_HUMAN_SCORE_RECORDED batch=1 cases=12",out.getvalue())
            self.assertFalse(h._load(reportfile)["quality_certified"])
            with patch.object(sys,"argv",argv),self.assertRaises(FileExistsError):
                h.main()

    def test_status_is_only_counts_not_private_translations(self):
        with TemporaryDirectory() as d:
            p=Path(d);art=invented_translation()
            artfile=p/"translation.json";artfile.write_text(h._dump(art),encoding="utf-8")
            draftfile=p/"draft.json";h._open_or_resume(draftfile,art,rating_template(1,"A"),1,"A")
            argv=["bench","status","--translations",str(artfile),"--draft",str(draftfile)]
            with patch.object(sys,"argv",argv),redirect_stdout(io.StringIO()) as output:
                self.assertEqual(h.main(),0)
            self.assertIn("scored=0/12 remaining=12",output.getvalue())
            self.assertNotIn("Câu giả lập",output.getvalue())

    def test_duplicate_json_key_and_nonfinite_refused(self):
        with TemporaryDirectory() as d:
            p=Path(d)/"bad.json"
            for raw in (b'{"a":1,"a":2}',b'{"t":Infinity}',b'\xff'):
                p.write_bytes(raw)
                with self.subTest(raw=raw),self.assertRaises(ValueError):
                    h._load(p)

    def test_no_network_model_subprocess_or_auto_score_defaults(self):
        import inspect
        code=inspect.getsource(h)
        for word in ("subprocess.", "requests.", "socket.", "urllib.request",
                     "generateContent(", "agy -p", "api_key", "openai."):
            self.assertNotIn(word,code)


if __name__ == "__main__":
    unittest.main()
