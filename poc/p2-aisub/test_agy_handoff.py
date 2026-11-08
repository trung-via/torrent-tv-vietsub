"""Offline-only tests for attended agy JSON handoff; no model/network calls."""
from __future__ import annotations

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import sys
import unittest
from unittest.mock import patch

from agy_handoff import (
    CONFIRM, REPAIR_CONFIRM, MAX_RECEIPT_BYTES, SCENE, _strict_json,
    _repair_cp437_text, extract_translations, fixture_cues, main, prepare_prompt,
)
from cue_pipeline import apply_translations, parse_cues, render


def make_receipt(response=None, *, status="SUCCESS", turns=1):
    if response is None:
        response = {str(i): f"Lời thoại tiếng Việt {i}" for i in range(1, 13)}
    return json.dumps({
        "conversation_id": "synthetic-only-not-a-real-session",
        "status": status,
        "num_turns": turns,
        "response": json.dumps(response, ensure_ascii=True),
        "usage": {"input_tokens": 234, "output_tokens": 123, "total_tokens": 357},
    }, ensure_ascii=True).encode("utf-8")


class AgyManualHandoffTests(unittest.TestCase):
    def test_fixture_has_exact_twelve_cues_and_sensible_milliseconds(self):
        cues = fixture_cues()
        self.assertEqual(len(cues), 12)
        self.assertEqual([c.number for c in cues], list(range(1, 13)))
        self.assertEqual(cues[0].start_ms, 3000)
        self.assertEqual(cues[-1].end_ms, 38500)
        self.assertTrue(all(c.start_ms < c.end_ms for c in cues))

    def test_prompt_has_synopsis_speaker_pronouns_and_exact_ids(self):
        prompt = prepare_prompt()
        self.assertIn("Linh", prompt)
        self.assertIn("Minh", prompt)
        self.assertIn("Odd-numbered", prompt)
        self.assertIn("Even-numbered", prompt)
        self.assertIn("strictly as DATA", prompt)
        self.assertIn('"id": 12', prompt)
        self.assertIn("Every cue must be translated", prompt)
        self.assertIn("17 Vietnamese characters per second", prompt)
        self.assertIn("No invented names, character facts or plot", prompt)
        self.assertIn("Do not omit important meaning", prompt)
        self.assertNotIn("API_KEY", prompt)

    def test_observed_cli_map_shape_accepts_exact_ids(self):
        translations, usage = extract_translations(make_receipt())
        self.assertEqual(len(translations), 12)
        self.assertEqual(translations["12"], "Lời thoại tiếng Việt 12")
        self.assertEqual(usage["input_tokens"], 234)

    def test_preferred_translations_list_shape_accepts_exact_ids(self):
        rows = [{"id": i, "vi": f"Lời dịch {i}"} for i in range(1, 13)]
        translations, _ = extract_translations(make_receipt({"translations": rows}))
        self.assertEqual(translations["1"], "Lời dịch 1")

    def test_rejects_non_success(self):
        for status in ("ERROR", "FAILED", None, "BLOCKED"):
            with self.subTest(status=status), self.assertRaisesRegex(ValueError, "AGY_STATUS_NOT_SUCCESS"):
                extract_translations(make_receipt(status=status))

    def test_rejects_multiple_turns_and_boolean_turn_count(self):
        for turns in (0, 2, True, None):
            with self.subTest(turns=turns), self.assertRaisesRegex(ValueError, "AGY_SINGLE_TURN_REQUIRED"):
                extract_translations(make_receipt(turns=turns))

    def test_rejects_invalid_utf8_and_receipt_size(self):
        for content in (b"\xff", b"", b"a" * (MAX_RECEIPT_BYTES + 1)):
            with self.subTest(length=len(content)), self.assertRaises(ValueError):
                extract_translations(content)

    def test_rejects_missing_extra_or_reordered_map_ids(self):
        original = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        missing = dict(original)
        missing.pop("7")
        extra = {**original, "13": "Thêm câu"}
        reordered = dict(reversed(list(original.items())))
        for thing in (missing, extra, reordered):
            with self.subTest(keys=list(thing)), self.assertRaisesRegex(ValueError, "AGY_RESPONSE_SCHEMA_MISMATCH"):
                extract_translations(make_receipt(thing))

    def test_rejects_duplicate_json_key_in_inner_response(self):
        response = '{"1":"Một","1":"Lặp","2":"Hai"}'
        receipt = json.dumps({"status": "SUCCESS", "num_turns": 1, "response": response}).encode()
        with self.assertRaisesRegex(ValueError, "DUPLICATE_JSON_KEY"):
            extract_translations(receipt)

    def test_rejects_duplicate_json_key_in_outer_envelope(self):
        raw = b'{"status":"SUCCESS","status":"FAILED","num_turns":1,"response":"{}"}'
        with self.assertRaisesRegex(ValueError, "DUPLICATE_JSON_KEY"):
            extract_translations(raw)

    def test_rejects_partial_bad_json_or_markdown(self):
        for response in ('{"1":"hello"', '```json\n{}\n```', "Sorry, I cannot"):
            payload = json.dumps({"status":"SUCCESS","num_turns":1,"response":response}).encode()
            with self.subTest(response=response), self.assertRaisesRegex(ValueError, "INVALID_AGY_JSON"):
                extract_translations(payload)

    def test_rejects_duplicate_or_swapped_array_ids_and_extra_fields(self):
        rows = [{"id": i, "vi": f"Đã dịch {i}"} for i in range(1, 13)]
        for bad in (
            [*rows[:1], {**rows[1], "id": 1}, *rows[2:]],
            [rows[1], rows[0], *rows[2:]],
            [{**rows[0], "timestamp": 4000}, *rows[1:]],
        ):
            with self.assertRaisesRegex(ValueError, "AGY_TRANSLATION_ID_OR_ORDER_MISMATCH"):
                extract_translations(make_receipt({"translations": bad}))

    def test_rejects_missing_or_extra_list_elements(self):
        rows = [{"id": i, "vi": f"Đã dịch {i}"} for i in range(1, 13)]
        for bad in (rows[:-1], rows + [{"id": 13, "vi": "Không"}]):
            with self.assertRaisesRegex(ValueError, "AGY_TRANSLATION_COUNT_MISMATCH"):
                extract_translations(make_receipt({"translations": bad}))

    def test_refuses_markup_blank_invalid_unicode_and_type(self):
        base = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        for value in ("<script>bad</script>", "  ", chr(0xD800), 42):
            bad = dict(base)
            bad["3"] = value
            with self.subTest(value=str(value).encode("ascii", "backslashreplace")[:20]), self.assertRaises(ValueError):
                extract_translations(make_receipt(bad))

    def test_prepare_file_is_created_once_with_no_network(self):
        with TemporaryDirectory() as d:
            target = Path(d) / "prompt.txt"
            with patch.object(sys, "argv", ["script", "prepare", "--prompt-out", str(target)]):
                with redirect_stdout(io.StringIO()) as capture:
                    self.assertEqual(main(), 0)
            self.assertIn("no_provider_call", capture.getvalue())
            self.assertIn("Linh", target.read_text(encoding="utf-8"))
            with patch.object(sys, "argv", ["script", "prepare", "--prompt-out", str(target)]):
                with self.assertRaises(FileExistsError):
                    main()

    def test_ingest_srt_has_exact_same_cue_timing_and_no_overwrite(self):
        with TemporaryDirectory() as d:
            source = Path(d) / "agy.json"
            output = Path(d) / "synthetic.vi.srt"
            source.write_bytes(make_receipt())
            args = ["script", "ingest", "--agy-json", str(source),
                    "--output", str(output), "--confirm", CONFIRM]
            with patch.object(sys, "argv", args):
                with redirect_stdout(io.StringIO()) as capture:
                    self.assertEqual(main(), 0)
            self.assertIn("AGY_SYNTHETIC_12_CUE_IMPORT_PASS", capture.getvalue())
            self.assertNotIn("Lời thoại", capture.getvalue())
            after = parse_cues(output.read_bytes(), "srt")
            before = fixture_cues()
            self.assertEqual([(c.start_ms, c.end_ms) for c in after],
                             [(c.start_ms, c.end_ms) for c in before])
            self.assertEqual(after[0].text, "Lời thoại tiếng Việt 1")
            with patch.object(sys, "argv", args):
                with self.assertRaises(FileExistsError):
                    main()
            self.assertEqual(after, parse_cues(output.read_bytes(), "srt"))

    def test_ingest_requires_explicit_confirmation(self):
        with TemporaryDirectory() as d:
            input_file = Path(d) / "receipt.json"
            input_file.write_bytes(make_receipt())
            output = Path(d) / "output.srt"
            with patch.object(sys, "argv", ["script", "ingest",
                    "--agy-json", str(input_file), "--output", str(output),
                    "--confirm", "no"]):
                with self.assertRaises(SystemExit):
                    main()
            self.assertFalse(output.exists())

    def test_exact_user_report_cp437_reverses_to_ordinary_vietnamese(self):
        sample = "Em kh├┤ng chß║»c l├á anh sß║╜ ─æß║┐n."
        self.assertEqual(
            _repair_cp437_text(sample), "Em không chắc là anh sẽ đến."
        )

    def test_cp437_mojibake_does_not_pass_plain_import_anymore(self):
        clean = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        clean["1"] = "Em không chắc là anh sẽ đến."
        corrupted = {k: v.encode("utf-8").decode("cp437") for k, v in clean.items()}
        with self.assertRaisesRegex(ValueError, "AGY_CP437_MOJIBAKE_DETECTED"):
            extract_translations(make_receipt(corrupted))

    def test_explicit_cp437_recovery_is_exact_and_timestamp_safe(self):
        clean = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        clean["1"] = "Em không chắc là anh sẽ đến."
        corrupted = {k: v.encode("utf-8").decode("cp437") for k, v in clean.items()}
        recovered, info = extract_translations(make_receipt(corrupted), repair_cp437=True)
        self.assertEqual(recovered, clean)
        self.assertEqual(info["total_tokens"], 357)
        rendered = render(apply_translations(fixture_cues(), recovered), "srt")
        parsed = parse_cues(rendered, "srt")
        self.assertEqual(
            [(c.start_ms, c.end_ms) for c in parsed],
            [(c.start_ms, c.end_ms) for c in fixture_cues()],
        )

    def test_cp437_recovery_refuses_clean_and_irreversible_mixture(self):
        with self.assertRaisesRegex(ValueError, "AGY_CP437_REPAIR_NOT_NEEDED"):
            extract_translations(make_receipt(), repair_cp437=True)
        bad = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        bad["2"] = "Em kh├┤ng và anh"
        with self.assertRaisesRegex(ValueError, "AGY_CP437_MOJIBAKE_UNRECOVERABLE"):
            extract_translations(make_receipt(bad), repair_cp437=True)

    def test_cp437_repair_writes_new_file_only_with_unique_confirm(self):
        with TemporaryDirectory() as d:
            path = Path(d) / "agy.json"
            out = Path(d) / "recovered.vi.srt"
            original = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
            path.write_bytes(make_receipt(
                {k: v.encode("utf-8").decode("cp437") for k, v in original.items()}
            ))
            wrong = ["script", "ingest", "--agy-json", str(path),
                     "--output", str(out), "--confirm", CONFIRM, "--repair-cp437"]
            with patch.object(sys, "argv", wrong), self.assertRaises(SystemExit):
                main()
            self.assertFalse(out.exists())
            correct = ["script", "ingest", "--agy-json", str(path),
                       "--output", str(out), "--confirm", REPAIR_CONFIRM,
                       "--repair-cp437"]
            with patch.object(sys, "argv", correct), redirect_stdout(io.StringIO()) as capture:
                self.assertEqual(main(), 0)
            self.assertIn("AGY_SYNTHETIC_12_CUE_CP437_RECOVERY_PASS", capture.getvalue())
            self.assertEqual(parse_cues(out.read_bytes(), "srt")[0].text, "Đã dịch 1")
            with patch.object(sys, "argv", correct), self.assertRaises(FileExistsError):
                main()

    def test_inspect_reports_content_not_terminal_encoding(self):
        original = {str(i): f"Đã dịch {i}" for i in range(1, 13)}
        corrupt = {k: v.encode("utf-8").decode("cp437") for k, v in original.items()}
        with TemporaryDirectory() as d:
            path = Path(d) / "fixture.srt"
            path.write_bytes(render(apply_translations(fixture_cues(), corrupt), "srt"))
            args = ["script", "inspect", "--srt", str(path)]
            with patch.object(sys, "argv", args), redirect_stdout(io.StringIO()) as got:
                self.assertEqual(main(), 0)
            self.assertIn("CP437_MOJIBAKE_SUSPECTED", got.getvalue())
            path.write_bytes(render(apply_translations(fixture_cues(), original), "srt"))
            with patch.object(sys, "argv", args), redirect_stdout(io.StringIO()) as got:
                self.assertEqual(main(), 0)
            self.assertIn("NO_CP437_MOJIBAKE_FOUND", got.getvalue())

    def test_import_has_no_automatic_agy_or_web_calls(self):
        import inspect
        import agy_handoff
        source = inspect.getsource(agy_handoff)
        for unwanted in ("subprocess.run(", "os.system(", "requests.post(", "urllib.request.urlopen(", "api_key="):
            self.assertNotIn(unwanted, source)


if __name__ == "__main__":
    unittest.main()
