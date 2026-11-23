"""Offline-only Antigravity account gateway tests. No executable/model invoked."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

from progressive_handoff import ProgressiveSubtitleSession
from translator_gateway import (
    _parse_response, _prompt, antigravity_translate,
    preflight_antigravity, translate_window,
)
from lean120_api import ModelProfile
from automatic_lean120_worker import AutomaticLean120Worker
from assumed_source_handoff import AssumedEnglishSubtitle


def _one_window():
    srt = b"1\n00:00:00,000 --> 00:00:01,000\nHello world\n\n"
    return ProgressiveSubtitleSession(srt, "srt", "media." + "a" * 64).windows[0]


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.window = _one_window()
        self.profile = ModelProfile("antigravity", "gemini-4-hydrogen-high", "high")

    def test_stdin_only_and_no_billed_api_environment(self):
        calls = []

        def fake(cmd, **kwargs):
            calls.append((cmd, kwargs))
            self.assertNotIn("Hello world", " ".join(cmd))
            self.assertNotIn("GEMINI_API_KEY", kwargs["env"])
            self.assertNotIn("GOOGLE_API_KEY", kwargs["env"])
            self.assertIn("--sandbox", cmd)
            self.assertEqual(cmd[cmd.index("--model") + 1], "gemini-4-hydrogen-high")
            request = json.loads(kwargs["input"].strip())
            self.assertIn("Hello world", request["message"]["content"])
            event = {"event": "result", "result": {"status": "SUCCESS",
                     "structured_output": {"translations": [{"id": 1, "vi": "Xin chào"}]}}}
            return subprocess.CompletedProcess(cmd, 0, json.dumps(event), "")

        with mock.patch.dict(os.environ, {"GEMINI_API_KEY": "must-never-propagate",
                                           "GOOGLE_API_KEY": "also-billed"}):
            translated = translate_window(self.window, self.profile,
                                          glossary={}, runner=fake)
        self.assertEqual(translated, {1: "Xin chào"})
        self.assertEqual(len(calls), 1)

    def test_no_codex_fallback_without_adapter(self):
        with self.assertRaisesRegex(ValueError, "TRANSLATION_PROVIDER_NOT_ENABLED"):
            translate_window(self.window, ModelProfile("codex", "gpt-test", "high"),
                             glossary={}, runner=lambda *args, **kwargs: None)

    def test_failed_or_tool_using_runs_rejected_without_retry(self):
        cases = [
            (1, "", "AGY_PROCESS_FAILED"),
            (0, json.dumps({"event": "result", "result": {"status": "ERROR"}}),
             "AGY_NO_SUCCESSFUL_RESULT"),
            (0, json.dumps({"event": "step_update", "step_update": {
                "step_type": "tool"}}) + "\n" + json.dumps({
                "event": "result", "result": {"status": "SUCCESS",
                "structured_output": {"translations": [{"id": 1, "vi": "Xin chào"}]}}}),
             "AGY_UNEXPECTED_TOOL_USAGE"),
        ]
        for rc, raw, reason in cases:
            calls = []
            def fake(cmd, **kwargs):
                calls.append(1)
                return subprocess.CompletedProcess(cmd, rc, raw, "private diagnostics")
            with self.subTest(reason=reason), self.assertRaisesRegex(ValueError, reason):
                antigravity_translate(self.window, model=self.profile.model,
                                     thinking_level=self.profile.thinking_level,
                                     glossary={}, runner=fake)
            self.assertEqual(len(calls), 1)

    def test_thinking_level_matches_forwarded_model_alias(self):
        calls = []
        def fake(cmd, **kwargs):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0, "", "")

        mismatch = ModelProfile("antigravity", "gemini-4-hydrogen-high", "medium")
        with self.assertRaisesRegex(ValueError, "AGY_MODEL_THINKING_LEVEL_MISMATCH"):
            translate_window(self.window, mismatch, glossary={}, runner=fake)
        self.assertEqual(calls, [])
        for level in ("low", "medium", "high"):
            profile = ModelProfile("antigravity", f"example-model-{level}", level)
            result = {"event": "result", "result": {"status": "SUCCESS",
                      "structured_output": {"translations": [{"id": 1, "vi": "Xin chào"}]}}}
            def ok(cmd, **kwargs):
                self.assertEqual(cmd[cmd.index("--model") + 1], profile.model)
                return subprocess.CompletedProcess(cmd, 0, json.dumps(result), "")
            self.assertEqual(translate_window(self.window, profile, glossary={}, runner=ok),
                             {1: "Xin chào"})

    def test_wrong_id_not_committed(self):
        payload = {"event": "result", "result": {"status": "SUCCESS",
                   "structured_output": {"translations": [{"id": 2, "vi": "Sai"}]}}}
        with self.assertRaisesRegex(ValueError, "AGY_TRANSLATION_ID_OR_TEXT_INVALID"):
            _parse_response(json.dumps(payload), self.window)

    def test_owner_failure_formatting_is_normalized_before_cue_validation(self):
        def reply(text):
            return json.dumps({"event": "result", "result": {"status": "SUCCESS",
                "structured_output": {"translations": [{"id": 1, "vi": text}]}}})

        self.assertEqual(_parse_response(reply("<i>Xin</i>\r\n<b>chào</b> 2 < 3"),
                                         self.window), {1: "Xin\nchào 2 ‹ 3"})
        self.assertEqual(_parse_response(reply("Bình thường"), self.window),
                         {1: "Bình thường"})
        for value, code in ((" \r\n ", "AGY_TRANSLATION_TEXT_EMPTY"),
                            ("<script>alert(1)</script>",
                             "AGY_TRANSLATION_TEXT_MARKUP_UNSUPPORTED"),
                            ("a" * 2001, "AGY_TRANSLATION_TEXT_TOO_LONG"),
                            ("Chào\x00", "AGY_TRANSLATION_TEXT_NUL"),
                            ("\ud800", "AGY_TRANSLATION_TEXT_UTF8_INVALID")):
            with self.subTest(code=code), self.assertRaisesRegex(ValueError, code):
                _parse_response(reply(value), self.window)

    def test_normalized_window_checkpoints_without_repeat_provider_call(self):
        source = AssumedEnglishSubtitle.from_supplied(
            media_key="media." + "d" * 64, fmt="srt",
            source_bytes=b"1\n00:00:00,000 --> 00:00:01,000\nHello world\n\n")
        calls = []
        def fake(cmd, **kwargs):
            calls.append(1)
            response = {"event": "result", "result": {"status": "SUCCESS",
                        "structured_output": {"translations": [
                            {"id": 1, "vi": "<i>Xin chào</i>\r\n<b>bạn</b>"}]}}}
            return subprocess.CompletedProcess(cmd, 0, json.dumps(response), "")

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            worker = AutomaticLean120Worker(state_root=state, profile=self.profile,
                                            glossary={}, runner=fake)
            first = worker.run(source)
            second = worker.run(source)
            self.assertEqual(first.payload, second.payload)
            self.assertIn("Xin chào\nbạn", first.payload.decode("utf-8"))
            self.assertEqual(len(calls), 1)
            self.assertEqual(len(list(state.rglob("batch-0001.json"))), 1)
            self.assertEqual(list(state.rglob("*.inflight")), [])

    def test_batch_two_markup_and_crlf_commit_after_batch_one(self):
        cues = []
        for i in range(1, 122):
            minute, second = divmod(i - 1, 60)
            cues.append(f"{i}\n00:{minute:02d}:{second:02d},000 --> "
                        f"00:{minute:02d}:{second:02d},900\nEnglish {i}\n")
        source = AssumedEnglishSubtitle.from_supplied(
            media_key="media." + "e" * 64, fmt="srt",
            source_bytes=("\n".join(cues) + "\n").encode())
        batches = []
        def fake(cmd, **kwargs):
            prompt = json.loads(kwargs["input"])["message"]["content"]
            data = json.loads(prompt.split("\n", 1)[1])
            ids = [item["id"] for item in data["target"]]
            batches.append(ids)
            response = {"event": "result", "result": {"status": "SUCCESS",
                "structured_output": {"translations": [
                    {"id": i, "vi": "<i>Xin chào</i>\r\n<b>bạn</b>" if i == 121
                     else f"Tiếng Việt {i}"} for i in ids]}}}
            return subprocess.CompletedProcess(cmd, 0, json.dumps(response), "")

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            worker = AutomaticLean120Worker(state_root=state, profile=self.profile,
                                            glossary={}, runner=fake)
            result = worker.run(source)
            self.assertEqual(result.translated_count, 121)
            self.assertIn("Xin chào\nbạn", result.payload.decode("utf-8"))
            self.assertEqual(list(map(len, batches)), [120, 1])
            self.assertEqual(len(list(state.rglob("batch-0001.json"))), 1)
            self.assertEqual(len(list(state.rglob("batch-0002.json"))), 1)
            self.assertEqual(list(state.rglob("*.inflight")), [])
            worker.run(source)
            self.assertEqual(len(batches), 2)

    def test_no_api_key_or_cloud_account_mode_in_preflight(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            settings = home / ".gemini" / "antigravity-cli" / "settings.json"
            settings.parent.mkdir(parents=True)
            settings.write_text('{"modelProvider":"gemini"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "API_KEY_MODE_REFUSED"):
                preflight_antigravity(env={"USERPROFILE": str(home), "PATH": ""})
            settings.write_text('{"auth":{"type":"agent-platform"}}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "PERSONAL_ACCOUNT_MODE_REQUIRED"):
                preflight_antigravity(env={"USERPROFILE": str(home), "PATH": ""})
            settings.write_text('{"auth":{"type":"gemini-api-key"}}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "PERSONAL_ACCOUNT_MODE_REQUIRED"):
                preflight_antigravity(env={"USERPROFILE": str(home), "PATH": ""})
            settings.write_text('{"auth":{"type":"oauth-personal"}}', encoding="utf-8")
            app = home / ".gemini" / "config" / "config.json"
            app.parent.mkdir(parents=True)
            app.write_text('{"userSettings":{"enableAdc":true}}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "ADC_MODE_REFUSED"):
                preflight_antigravity(env={"USERPROFILE": str(home), "PATH": ""})

    def test_prompt_does_not_contain_media_identity(self):
        p = _prompt(self.window, {"Name": "Tên"})
        self.assertNotIn("media.", p)
        self.assertIn("Hello world", p)

    def test_worker_reuses_checkpoints_and_prior_api_inflight_holds(self):
        def source(n):
            cues = []
            for i in range(1, n + 1):
                minute, second = divmod(i - 1, 60)
                cues.append(f"{i}\n00:{minute:02d}:{second:02d},000 --> "
                            f"00:{minute:02d}:{second:02d},900\nEnglish {i}\n")
            return AssumedEnglishSubtitle.from_supplied(
                media_key="media." + "b" * 64, fmt="srt",
                source_bytes=("\n".join(cues) + "\n").encode())

        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            calls = []
            def fake(cmd, **kwargs):
                request = json.loads(kwargs["input"])
                prompt = request["message"]["content"]
                data = json.loads(prompt.split("\n", 1)[1])
                ids = [item["id"] for item in data["target"]]
                calls.append(ids)
                response = {"event": "result", "result": {"status": "SUCCESS",
                    "structured_output": {"translations": [
                        {"id": i, "vi": f"Tiếng Việt {i}"} for i in ids]}}}
                return subprocess.CompletedProcess(cmd, 0, json.dumps(response), "")

            worker = AutomaticLean120Worker(state_root=state, profile=self.profile,
                                            glossary={}, runner=fake)
            legacy = state / ("f" * 64)
            legacy.mkdir(parents=True)
            (legacy / "batch-0001.inflight").write_text("old-provider-unknown-effect")
            # An uncertain batch belongs to a different film; new independent
            # jobs proceed, while the old marker stays quarantined.
            final = worker.run(source(121))
            self.assertTrue((legacy / "batch-0001.inflight").exists())
            self.assertEqual(final.translated_count, 121)
            self.assertEqual(list(map(len, calls)), [120, 1])
            worker.run(source(121))
            self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
