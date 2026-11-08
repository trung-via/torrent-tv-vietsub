"""All offline/fictional: 36 independent scenes, attended agy receipt, human ratings."""
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

from benchmark36 import (
    DATASET, GENRES, SCORE_FIELDS,
    NORMAL_CONFIRM, RECOVERY_CONFIRM,
    _parse_json, aggregate, batch_cases, build_prompt, corpus, ingest,
    main, rating_template, score_review,
)


def receipt(rows=None, *, status="SUCCESS", turns=1, array=False):
    if rows is None:
        rows = {str(i): f"Đã dịch mẫu {i}." for i in range(1, 13)}
    if array:
        rows = {"translations": [
            {"id": int(k), "vi": v} for k, v in rows.items()
        ]}
    return json.dumps({
        "status": status,
        "num_turns": turns,
        "response": json.dumps(rows, ensure_ascii=True),
        "usage": {"input_tokens": 500, "output_tokens": 120, "total_tokens": 620},
    }, ensure_ascii=True).encode("utf-8")


def human_scores(batch, label="A"):
    sheet = rating_template(batch, label)
    for row in sheet["ratings"]:
        for field in SCORE_FIELDS:
            row[field] = 4
        row["hallucination"] = False
    return sheet


def translations_for(batch, label="A"):
    ids = [c["id"] for c in batch_cases(batch)]
    return ingest(receipt({str(i): f"Đã dịch mẫu {i}." for i in ids}), batch, label)


def report_for(batch, label="A"):
    return score_review(translations_for(batch, label), human_scores(batch, label))


class Benchmark36OfflineTests(unittest.TestCase):
    def test_original_provenance_36_six_genres_six_each(self):
        cases, sha = corpus()
        self.assertEqual(len(cases), 36)
        self.assertEqual(len(sha), 64)
        self.assertEqual(set(x["genre"] for x in cases), set(GENRES))
        self.assertEqual({g: sum(x["genre"] == g for x in cases) for g in GENRES},
                         {g: 6 for g in GENRES})
        self.assertTrue(all(x["source_english"] and x["scene_context"] and x["speaker"]
                            and x["risk_focus"] for x in cases))

    def test_three_disjoint_twelve_case_batches_preserve_global_ids(self):
        groups = [batch_cases(batch) for batch in (1, 2, 3)]
        self.assertEqual([[c["id"] for c in group] for group in groups],
                         [list(range(1, 13)), list(range(13, 25)), list(range(25, 37))])
        self.assertEqual([group[0]["genre"] for group in groups],
                         ["action", "comedy", "historical"])

    def test_prompt_keeps_each_case_own_context_and_json_schema(self):
        prompt = build_prompt(2)
        self.assertIn("INDEPENDENT fictional situations", prompt)
        self.assertIn("do not infer connections between unrelated cases", prompt)
        self.assertIn("risk_focus is a human-review hint", prompt)
        self.assertIn("17 characters per second", prompt)
        self.assertIn("NEVER omit important meaning", prompt)
        self.assertIn('"id":<integer>', prompt)
        self.assertIn('["cases"', prompt.replace('{"cases"', '["cases"')) if False else self.assertIn('"cases":[', prompt)
        self.assertIn('"id":13', prompt)
        self.assertIn('"id":24', prompt)
        self.assertNotIn('"id":25', prompt)
        self.assertNotIn("API_KEY", prompt)

    def test_invalid_batch_never_silently_wraps(self):
        for batch in (0, 4, None, True, "1"):
            with self.subTest(batch=batch), self.assertRaises(ValueError):
                batch_cases(batch)

    def test_dataset_sha_cannot_ignore_added_or_missing_case(self):
        original = json.loads(DATASET.read_text(encoding="utf-8"))
        with TemporaryDirectory() as d:
            temp = Path(d) / "corpus.json"
            original["cases"].append(deepcopy(original["cases"][0]))
            temp.write_text(json.dumps(original), encoding="utf-8")
            with patch("benchmark36.DATASET", temp), self.assertRaises(ValueError):
                corpus()

    def test_actual_cli_map_shape_for_global_ids(self):
        data = translations_for(2)
        self.assertEqual(data["translations"][0]["id"], 13)
        self.assertEqual(data["translations"][-1]["id"], 24)
        self.assertEqual(data["usage"]["total_tokens"], 620)
        self.assertEqual(data["source"], "human_attended_cli_receipt")

    def test_preferred_structured_translation_array_shape(self):
        rows = {str(i): f"Đã dịch {i}" for i in range(25, 37)}
        got = ingest(receipt(rows, array=True), 3, "A")
        self.assertEqual([r["id"] for r in got["translations"]], list(range(25, 37)))

    def test_failed_aged_cli_or_multiple_turns_refused(self):
        for status, turns in (("FAILED", 1), ("SUCCESS", 2), ("SUCCESS", True), (None, 1)):
            with self.subTest(status=status, turns=turns), self.assertRaises(ValueError):
                ingest(receipt(status=status, turns=turns), 1, "A")

    def test_strict_json_rejects_duplicates_and_nan(self):
        for text in ('{"1":"one","1":"two"}', '{"num":NaN}', '{"num":Infinity}',
                     '```json\n{}\n```'):
            with self.subTest(text=text[:10]), self.assertRaises(ValueError):
                _parse_json(text)

    def test_receipt_duplicate_outer_json_is_rejected(self):
        raw = b'{"status":"SUCCESS","status":"FAILED","num_turns":1,"response":"{}"}'
        with self.assertRaisesRegex(ValueError, "DUPLICATE_JSON_KEY"):
            ingest(raw, 1, "A")

    def test_missing_added_reversed_ids_wrong_batch_and_booleans_refused(self):
        rows = {str(i): f"Đã dịch {i}" for i in range(13, 25)}
        for bad in (
            {k: v for k, v in rows.items() if k != "17"},
            {**rows, "25": "thêm câu"},
            dict(reversed(list(rows.items()))),
            {str(i): f"Đã dịch {i}" for i in range(1, 13)},
        ):
            with self.subTest(keys=list(bad)), self.assertRaises(ValueError):
                ingest(receipt(bad), 2, "A")
        faulty = {"translations": [
            {"id": True if i == 13 else i, "vi": "Thử"} for i in range(13, 25)
        ]}
        with self.assertRaises(ValueError):
            ingest(receipt(faulty), 2, "A")

    def test_no_markdown_html_missing_or_unsafe_unicode_allowed(self):
        good = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        for value in ("", "  ", "<script>bad</script>", "a\rb", chr(0xD800), 123):
            bad = dict(good)
            bad["3"] = value
            with self.subTest(value=repr(value)[:15]), self.assertRaises(ValueError):
                ingest(receipt(bad), 1, "A")

    def test_cp437_false_pass_is_prevented_and_manual_repair_is_exact(self):
        good = {str(i): f"Đã dịch mẫu {i}" for i in range(1, 13)}
        garbled = {key: text.encode("utf-8").decode("cp437") for key, text in good.items()}
        with self.assertRaisesRegex(ValueError, "BENCHMARK_CP437_MOJIBAKE_DETECTED"):
            ingest(receipt(garbled), 1, "A")
        recovered = ingest(receipt(garbled), 1, "A", repair_cp437=True)
        self.assertEqual([r["vi"] for r in recovered["translations"]], list(good.values()))
        with self.assertRaisesRegex(ValueError, "BENCHMARK_CP437_RECOVERY_NOT_NEEDED"):
            ingest(receipt(good), 1, "A", repair_cp437=True)

    def test_repair_refuses_irreversible_mixed_text(self):
        rows = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        rows["2"] = "Em kh├┤ng và anh"
        with self.assertRaises(ValueError):
            ingest(receipt(rows), 1, "A", repair_cp437=True)

    def test_invalid_model_blind_label_refused(self):
        for label in ("", "ab", "agent", "a", "AA", "A1", None):
            with self.subTest(label=label), self.assertRaises(ValueError):
                rating_template(1, label)

    def test_score_template_does_not_fabricate_any_result(self):
        sheet = rating_template(1, "A")
        self.assertEqual(len(sheet["ratings"]), 12)
        self.assertTrue(all(all(row[field] is None for field in (*SCORE_FIELDS, "hallucination"))
                            for row in sheet["ratings"]))
        with self.assertRaisesRegex(ValueError, "BENCHMARK_HUMAN_SCORE_REQUIRED"):
            score_review(translations_for(1), sheet)

    def test_complete_human_scores_produce_an_explicitly_noncertified_report(self):
        result = report_for(1)
        self.assertEqual(result["summary"]["overall"]["n"], 12)
        self.assertEqual(result["summary"]["overall"]["scores_mean"]["semantic_accuracy"], 4.0)
        self.assertEqual(result["summary"]["overall"]["hallucinations"], 0)
        self.assertEqual(result["summary"]["by_genre"]["action"]["n"], 6)
        self.assertTrue(result["human_supplied_scores_not_independently_verified"])
        self.assertFalse(result["quality_certified"])
        self.assertNotIn("source_english", json.dumps(result))

    def test_bad_scores_cannot_be_coerced_to_pass(self):
        good = human_scores(1)
        for invalid in (0, 6, True, 2.5, None, "5"):
            changed = deepcopy(good)
            changed["ratings"][0]["semantic_accuracy"] = invalid
            with self.subTest(value=repr(invalid)), self.assertRaises(ValueError):
                score_review(translations_for(1), changed)
        for wrong in ("no", 0, None):
            changed = deepcopy(good)
            changed["ratings"][0]["hallucination"] = wrong
            with self.assertRaisesRegex(ValueError, "BENCHMARK_HUMAN_HALLUCINATION_BOOLEAN_REQUIRED"):
                score_review(translations_for(1), changed)

    def test_review_rejects_mismatched_label_case_id_and_corpus_digest(self):
        original = translations_for(1)
        sheet = human_scores(1)
        different = deepcopy(sheet)
        different["blind_label"] = "B"
        with self.assertRaises(ValueError):
            score_review(original, different)
        different = deepcopy(sheet)
        different["ratings"][0]["id"] = 2
        with self.assertRaises(ValueError):
            score_review(original, different)
        different = deepcopy(sheet)
        different["corpus_sha256"] = "a" * 64
        with self.assertRaises(ValueError):
            score_review(original, different)

    def test_aggregate_requires_exact_three_batches_same_sha_and_label(self):
        reviews = [report_for(i) for i in (1, 2, 3)]
        result = aggregate(reviews)
        self.assertEqual(result["reviewed_cases"], 36)
        self.assertEqual(set(result["summary"]["by_genre"]), set(GENRES))
        self.assertTrue(all(g["n"] == 6 for g in result["summary"]["by_genre"].values()))
        self.assertFalse(result["quality_certified"])
        for bad in (
            reviews[:2],
            [reviews[0], reviews[0], reviews[2]],
            [reviews[0], report_for(2, "B"), reviews[2]],
        ):
            with self.assertRaises(ValueError):
                aggregate(bad)

    def test_aggregate_detects_forged_stats_and_ids(self):
        good = [report_for(i) for i in (1, 2, 3)]
        altered = deepcopy(good)
        altered[1]["summary"]["overall"]["scores_mean"]["semantic_accuracy"] = 5.0
        with self.assertRaises(ValueError):
            aggregate(altered)
        altered = deepcopy(good)
        altered[1]["case_scores"][1]["id"] = 13
        with self.assertRaises(ValueError):
            aggregate(altered)

    def test_cli_prepare_template_and_score_do_not_call_model_or_overwrite(self):
        with TemporaryDirectory() as d:
            prompt = Path(d) / "prompt.txt"
            sheet = Path(d) / "score.json"
            with patch.object(sys, "argv", ["bench", "prepare", "--batch", "1", "--prompt-out", str(prompt)]):
                with redirect_stdout(io.StringIO()) as out:
                    self.assertEqual(main(), 0)
            self.assertIn("no_model_call", out.getvalue())
            self.assertIn("INDEPENDENT fictional", prompt.read_text(encoding="utf-8"))
            with patch.object(sys, "argv", ["bench", "prepare", "--batch", "1", "--prompt-out", str(prompt)]):
                with self.assertRaises(FileExistsError):
                    main()
            with patch.object(sys, "argv", ["bench", "template", "--batch", "1", "--blind-label", "A", "--out", str(sheet)]):
                self.assertEqual(main(), 0)
            self.assertIsNone(json.loads(sheet.read_text(encoding="utf-8"))["ratings"][0]["semantic_accuracy"])

    def test_cli_ingest_requires_confirmation_before_creating_any_output(self):
        with TemporaryDirectory() as d:
            input_file = Path(d) / "receipt.json"
            output_file = Path(d) / "accepted.json"
            input_file.write_bytes(receipt())
            args = ["bench", "ingest", "--batch", "1", "--blind-label", "A",
                    "--agy-json", str(input_file), "--out", str(output_file),
                    "--confirm", "NO"]
            with patch.object(sys, "argv", args), self.assertRaises(SystemExit):
                main()
            self.assertFalse(output_file.exists())
            args[-1] = NORMAL_CONFIRM
            with patch.object(sys, "argv", args), redirect_stdout(io.StringIO()) as out:
                self.assertEqual(main(), 0)
            self.assertIn("BENCHMARK36_IMPORT_PASS batch=1 ids=12", out.getvalue())
            self.assertNotIn("Đã dịch", out.getvalue())
            self.assertEqual(json.loads(output_file.read_text(encoding="utf-8"))["batch"], 1)

    def test_cli_score_and_aggregate_record_real_supplied_numbers_only(self):
        with TemporaryDirectory() as d:
            reviews = []
            for batch in (1, 2, 3):
                translation_file = Path(d) / f"translations-{batch}.json"
                scores_file = Path(d) / f"scores-{batch}.json"
                report_file = Path(d) / f"report-{batch}.json"
                translation_file.write_text(json.dumps(translations_for(batch)), encoding="utf-8")
                scores_file.write_text(json.dumps(human_scores(batch)), encoding="utf-8")
                with patch.object(sys, "argv", ["bench", "score",
                        "--translations", str(translation_file),
                        "--ratings", str(scores_file), "--report-out", str(report_file)]):
                    with redirect_stdout(io.StringIO()) as output:
                        self.assertEqual(main(), 0)
                self.assertIn("quality_certified=False", output.getvalue())
                reviews.append(report_file)
            combined = Path(d) / "aggregate.json"
            with patch.object(sys, "argv", [
                "bench", "aggregate", "--reports", *[str(p) for p in reviews],
                "--out", str(combined),
            ]), redirect_stdout(io.StringIO()) as output:
                self.assertEqual(main(), 0)
            self.assertIn("cases=36", output.getvalue())
            self.assertFalse(json.loads(combined.read_text(encoding="utf-8"))["quality_certified"])

    def test_source_never_imports_or_invokes_agy_or_network(self):
        import inspect
        import benchmark36
        code = inspect.getsource(benchmark36)
        for prohibited in (
            "subprocess.", "os.system(", "requests.post(", "urllib.request",
            "socket.connect(", "api_key=", "run_aby(", "http.client",
        ):
            self.assertNotIn(prohibited, code)


if __name__ == "__main__":
    unittest.main()
