"""Composed D2 GET/one POST/cache -> existing P2 LEAN120 worker, all synthetic.

Zero actual OpenSubtitles, Gemini or TV connections. This deliberately tests
the entire controller across both previously independent repository branches.
"""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import parse_qs, urlsplit

# The composed controller wires the fixed sibling P2 source path before
# importing the existing P2 modules; the isolated D2 CI only adds D2 to Python.
from owner_vietsub_pipeline import (
    acquire_and_translate_en_once,
    translate_existing_en,
    validate_existing_en,
)
from cached_en_direct_handoff import CachedEnReceipt
from automatic_lean120_worker import AutomaticLean120Worker
from cue_pipeline import parse_cues
from lean120_api import ModelProfile
from opensubtitles import OpenSubtitles

VIDEO = "Example.Film.2017.1080p.BluRay.x265-GRP"
STANDARD = VIDEO + "_eng"
SDH = VIDEO + "_eng SDH"
VI = VIDEO + "_vi"
MODEL = ModelProfile("gemini", "gemini-4-hydrogen", "high")


def _srt(n=125):
    blocks = []
    for i in range(1, n + 1):
        second = i - 1
        hh, remainder = divmod(second, 3600)
        mm, ss = divmod(remainder, 60)
        at = f"{hh:02d}:{mm:02d}:{ss:02d}"
        blocks.append(
            f"{i}\n{at},000 --> {at},900\nSynthetic English cue {i}")
    return ("\n\n".join(blocks) + "\n").encode("utf-8")


def _row(i, release, language):
    return {
        "attributes": {"language": language, "release": release,
                       "files": [{"file_id": i, "file_name": "synthetic.ass"}]}
    }


class FakeOpenSubtitles:
    def __init__(self, *, vi=(), en=None, payload=None):
        self.vi = tuple(vi)
        self.en = tuple(en) if en is not None else (
            _row(9, SDH, "en"), _row(10, STANDARD, "en"))
        self.payload = payload if payload is not None else _srt()
        self.calls = []

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url))
        if method == "GET":
            lang = parse_qs(urlsplit(url).query)["languages"][0]
            rows = self.vi if lang == "vi" else self.en
            return json.dumps({"data": list(rows), "total_count": len(rows)}).encode()
        if method == "POST":
            request = json.loads(body)
            assert request == {"file_id": 10, "sub_format": "srt"}
            return json.dumps({"link": "https://dl.opensubtitles.com/example/a.srt"}).encode()
        if method == "GET_BINARY":
            return self.payload
        raise AssertionError("Unexpected network operation")


class FakeGemini:
    def __init__(self):
        self.calls = []

    def __call__(self, url, headers, body, timeout):
        data = json.loads(body)
        ids = [x["id"] for x in json.loads(
            data["contents"][0]["parts"][0]["text"])["target"]]
        self.calls.append(tuple(ids))
        return {
            "candidates": [{"finishReason": "STOP", "content": {
                "parts": [{"text": json.dumps({"translations": [
                    {"id": i, "vi": f"Câu thử nghiệm {i}"} for i in ids
                ]}, ensure_ascii=False)}]
            }}]
        }


class ComposedPipelineTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.root = Path(t.name).resolve()
        self.cache = self.root / "subtitle-trials"
        self.cache.mkdir()
        self.provider = FakeOpenSubtitles()
        self.gemini = FakeGemini()
        self.client = OpenSubtitles(api_key="synthetic-key", transport=self.provider)
        self.worker = AutomaticLean120Worker(
            state_root=self.root / "p2-checkpoints",
            profile=MODEL, glossary={},
            api_key="synthetic-only", transport=self.gemini)
        self.lines = []

    def _run_fresh(self, *, grant=True, answer="DOWNLOAD ONE"):
        return acquire_and_translate_en_once(
            self.client, video_name=VIDEO, exact_en_release=STANDARD,
            group="GRP", cache_root=self.cache,
            worker=self.worker, cloud_upload_authorized=grant,
            ask=lambda _: answer, emit=self.lines.append)

    def test_real_d2_and_p2_in_process_one_post_two_batches(self):
        result = self._run_fresh()
        self.assertIsNotNone(result)
        self.assertEqual(result.cue_count, 125)
        self.assertTrue(result.translation_complete)
        self.assertEqual(result.translated_cues, 125)
        self.assertEqual([m for m, _ in self.provider.calls],
                         ["GET", "GET", "POST", "GET_BINARY"])
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)
        self.assertEqual(len(list(self.cache.glob(".en-once-*"))), 1)
        self.assertEqual(len(list(self.root.rglob("vi-final.srt"))), 1)
        self.assertFalse(list(self.root.rglob("verified-en-manifest.json")))
        self.assertIn("P2_DIRECT_CACHE_HANDOFF=COMPLETE", self.lines)
        self.assertIn("P4_TV_DELIVERY=NOT_RUN", self.lines)
        self.assertIn("DOWNLOAD_AND_SRT_QA=PASS", self.lines)
        self.assertEqual([x.number for x in parse_cues(
            list(self.root.rglob("vi-final.srt"))[0].read_bytes(), "srt")],
            list(range(1, 126)))

    def test_existing_file_skips_all_d2_calls_and_reuses_checkpoint(self):
        first = self._run_fresh()
        provider_calls = len(self.provider.calls)
        gemini_calls = len(self.gemini.calls)
        file = list(self.cache.glob("*.srt"))[0]
        receipt = CachedEnReceipt(file, hashlib.sha256(file.read_bytes()).hexdigest(),
                                  125, language="en")
        valid = validate_existing_en(receipt, cache_root=self.cache)
        self.assertFalse(valid.translation_complete)
        result = translate_existing_en(
            receipt, cache_root=self.cache, worker=self.worker,
            cloud_upload_authorized=True)
        self.assertEqual(result.source_sha256, first.source_sha256)
        self.assertTrue(result.translation_complete)
        self.assertEqual(len(self.provider.calls), provider_calls)
        self.assertEqual(len(self.gemini.calls), gemini_calls)
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)

    def test_cloud_consent_missing_refuses_even_d2_search(self):
        with self.assertRaisesRegex(ValueError, "CLOUD_UPLOAD_CONSENT_REQUIRED"):
            self._run_fresh(grant=False)
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(self.gemini.calls, [])
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_cancel_d2_quota_post_does_not_invoke_worker(self):
        result = self._run_fresh(answer="CANCEL")
        self.assertIsNone(result)
        self.assertEqual([m for m, _ in self.provider.calls], ["GET", "GET"])
        self.assertEqual(self.gemini.calls, [])
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_confident_vi_is_not_downloaded_under_en_approval(self):
        self.provider.vi = (_row(40, VI, "vi"),)
        result = self._run_fresh()
        self.assertIsNone(result)
        self.assertEqual([m for m, _ in self.provider.calls], ["GET"])
        self.assertEqual(self.gemini.calls, [])

    def test_provider_changed_to_sdh_only_stops_before_post(self):
        self.provider.en = (_row(9, SDH, "en"),)
        result = self._run_fresh()
        self.assertIsNone(result)
        self.assertEqual([m for m, _ in self.provider.calls], ["GET", "GET"])
        self.assertEqual(self.gemini.calls, [])
        self.assertIn("EXPECTED_STANDARD_EN_NOT_SELECTED", self.lines)

    def test_invalid_cached_bytes_fail_before_translation(self):
        self._run_fresh()
        file = list(self.cache.glob("*.srt"))[0]
        original = file.read_bytes()
        receipt = CachedEnReceipt(file, hashlib.sha256(original).hexdigest(), 125)
        file.write_bytes(original + b"\nTAMPERED")
        gemini_count = len(self.gemini.calls)
        with self.assertRaisesRegex(ValueError, "SHA256_MISMATCH"):
            translate_existing_en(receipt, cache_root=self.cache,
                                  worker=self.worker, cloud_upload_authorized=True)
        self.assertEqual(len(self.gemini.calls), gemini_count)

    def test_do_not_repeat_post_on_same_released_source(self):
        self._run_fresh()
        with self.assertRaisesRegex(Exception, "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
            self._run_fresh()
        self.assertEqual([m for m, _ in self.provider.calls].count("POST"), 1)
        self.assertEqual(len(self.gemini.calls), 2)

    def test_cloud_failure_after_cached_download_does_not_retry_post(self):
        class CrashingGemini(FakeGemini):
            def __call__(self, url, headers, body, timeout):
                self.calls.append(("CRASH",))
                raise ValueError("FAKE_GEMINI_FAILED")
        bad = CrashingGemini()
        self.worker = AutomaticLean120Worker(
            state_root=self.root / "p2-checkpoints", profile=MODEL,
            glossary={}, api_key="synthetic-only", transport=bad)
        with self.assertRaisesRegex(ValueError, "FAKE_GEMINI_FAILED"):
            self._run_fresh()
        self.assertEqual([m for m, _ in self.provider.calls].count("POST"), 1)
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)
        self.assertEqual(len(list(self.cache.glob(".en-once-*"))), 1)
        with self.assertRaisesRegex(Exception, "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
            self._run_fresh()
        self.assertEqual([m for m, _ in self.provider.calls].count("POST"), 1)


if __name__ == "__main__":
    unittest.main()
