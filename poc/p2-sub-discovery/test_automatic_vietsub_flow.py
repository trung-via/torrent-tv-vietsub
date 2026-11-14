"""Pure offline D2 -> P2 automatic owner flow, no Human prompts or live APIs."""
from __future__ import annotations

from contextlib import redirect_stdout
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from opensubtitles import Asset, OpenSubtitles, SubtitleApiError, write_private_cache
from matcher import Media
from automatic_lean120_worker import AutomaticLean120Worker
from lean120_api import ModelProfile

VIDEO = "Example.Film.2017.1080p.BluRay.x265-GRP"
EN = VIDEO + "_eng"
SDH = EN + " SDH"
VI = VIDEO + "_vi"


def srt(count=125):
    blocks = []
    for i in range(1, count + 1):
        total = i
        hh, rem = divmod(total, 3600)
        mm, ss = divmod(rem, 60)
        time = f"{hh:02}:{mm:02}:{ss:02}"
        blocks.append(f"{i}\n{time},000 --> {time},900\nSynthetic English text {i}")
    return ("\n\n".join(blocks) + "\n").encode()


def row(i, release, language):
    return {"attributes": {"release": release, "language": language,
                           "files": [{"file_id": i, "file_name": "source.unknown"}]}}


class FakeProvider:
    def __init__(self, vi=(), en=None, broken_post=False):
        self.vi = tuple(vi)
        self.en = (row(9, SDH, "en"), row(10, EN, "en")) if en is None else tuple(en)
        self.calls = []
        self.broken_post = broken_post

    def __call__(self, method, url, headers, body, cap):
        self.calls.append((method, url))
        if method == "GET":
            lang = parse_qs(urlsplit(url).query)["languages"][0]
            rows = self.vi if lang == "vi" else self.en
            return json.dumps({"data": list(rows),
                               "total_count": len(rows)}).encode()
        if method == "POST":
            if self.broken_post:
                raise SubtitleApiError("API_NETWORK_ERROR")
            request = json.loads(body)
            assert request in (
                {"file_id": 10, "sub_format": "srt"},
                {"file_id": 8, "sub_format": "srt"},
            ), request
            return b'{"link":"https://dl.opensubtitles.com/test.srt"}'
        if method == "GET_BINARY":
            return srt()
        raise AssertionError("unexpected network operation")


class FakeGemini:
    def __init__(self):
        self.calls = []

    def __call__(self, url, headers, body, timeout):
        data = json.loads(body)
        ids = [int(t["id"]) for t in json.loads(
            data["contents"][0]["parts"][0]["text"])["target"]]
        self.calls.append(ids)
        return {"candidates": [{"finishReason": "STOP", "content": {
            "parts": [{"text": json.dumps({
                "translations": [
                    {"id": i, "vi": f"Vietnamese synthetic text {i}"} for i in ids]
            })}]
        }}]}


class AutomaticFlowTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.cache = self.root / "subtitle-trials"
        self.provider = FakeProvider()
        self.gemini = FakeGemini()
        self.worker = AutomaticLean120Worker(
            state_root=self.root / "P2" / "state",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={},
            api_key="synthetic-gemini-key",
            transport=self.gemini,
        )
        self.events = []
        self.client = OpenSubtitles(api_key="synthetic-ost-key",
                                    transport=self.provider)
        self.flow = AutomaticVietsubFlow(
            client=self.client, worker=self.worker, cache_root=self.cache,
            permissions=AutoPermissions(auto_download=True, auto_translate_en=True),
            emit=self.events.append,
        )

    def test_one_video_event_triggers_one_download_then_entire_translation(self):
        # One event, zero input(), zero second OpenSubtitles search, no D3.
        with mock.patch("builtins.input", side_effect=AssertionError("PROMPT_NOT_ALLOWED")):
            result = self.flow.selected_media(VIDEO)
        self.assertEqual(result.status, "VIETSUB_READY")
        self.assertEqual(result.cue_count, 125)
        self.assertEqual(result.translated_cues, 125)
        self.assertEqual(result.get_requests, 2)
        self.assertEqual(result.download_posts, 1)
        self.assertEqual([x[0] for x in self.provider.calls],
                         ["GET", "GET", "POST", "GET_BINARY"])
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)
        self.assertEqual(len(list(self.cache.glob(".en-once-*"))), 1)
        self.assertEqual(len(list(self.root.rglob("vi-final.srt"))), 1)
        self.assertEqual(self.events.count("AUTO_EN_TO_P2=COMPLETE"), 1)
        self.assertFalse(list(self.root.rglob("verified-en-manifest.json")))

    def test_vi_route_skips_gemini_entirely(self):
        self.provider.vi = (row(8, VI, "vi"),)
        result = self.flow.selected_media(VIDEO)
        self.assertEqual(result.status, "VI_READY")
        self.assertEqual(result.cue_count, 125)
        self.assertEqual([x[0] for x in self.provider.calls],
                         ["GET", "POST", "GET_BINARY"])
        self.assertEqual(self.gemini.calls, [])
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)
        self.assertIn("AUTO_GEMINI_REQUESTS=0", self.events)

    def test_no_confident_source_does_not_download_or_translate(self):
        self.provider.en = (row(12, VIDEO.replace("GRP", "OTHER") + "_eng", "en"),)
        result = self.flow.selected_media(VIDEO)
        self.assertEqual(result.status, "REVIEW_REQUIRED")
        self.assertEqual([x[0] for x in self.provider.calls], ["GET", "GET"])
        self.assertEqual(self.gemini.calls, [])
        self.assertFalse(self.cache.exists())

    def test_permissions_off_no_network_or_prompts(self):
        flow = AutomaticVietsubFlow(
            client=self.client, worker=self.worker, cache_root=self.cache,
            permissions=AutoPermissions(auto_download=True))
        with self.assertRaisesRegex(ValueError, "PERMISSIONS_NOT_ENABLED"):
            flow.selected_media(VIDEO)
        self.assertFalse(self.provider.calls)

    def test_repeated_event_does_not_consume_second_provider_post(self):
        self.flow.selected_media(VIDEO)
        with self.assertRaisesRegex(SubtitleApiError, "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
            self.flow.selected_media(VIDEO)
        self.assertEqual([x[0] for x in self.provider.calls].count("POST"), 1)
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])

    def test_uncertain_provider_post_blocks_retry_and_gemini(self):
        self.provider.broken_post = True
        with self.assertRaisesRegex(SubtitleApiError, "API_NETWORK_ERROR"):
            self.flow.selected_media(VIDEO)
        with self.assertRaisesRegex(SubtitleApiError, "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
            self.flow.selected_media(VIDEO)
        self.assertEqual([x[0] for x in self.provider.calls].count("POST"), 1)
        self.assertEqual(self.gemini.calls, [])

    def test_existing_cached_en_event_does_not_query_provider_or_prompt(self):
        # Existing D2, G1 or D3 component can supply this event after save.
        data = srt()
        asset = Asset(10, "en", "srt", data,
                      hashlib.sha256(data).hexdigest(), 125)
        media = Media("synthetic-owner", "a" * 64, 0, VIDEO)
        path = write_private_cache(self.cache, media, asset)
        with mock.patch("builtins.input", side_effect=AssertionError("PROMPT_NOT_ALLOWED")):
            first = self.flow.after_en_cached(asset, path)
            second = self.flow.after_en_cached(asset, path)
        self.assertTrue(first.translation_complete)
        self.assertTrue(second.translation_complete)
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(self.events.count("AUTO_EN_TO_P2=COMPLETE"), 2)
        self.assertEqual(len(list(self.root.rglob("vi-final.srt"))), 1)

    def test_cache_tamper_stops_before_model(self):
        data = srt()
        asset = Asset(10, "en", "srt", data,
                      hashlib.sha256(data).hexdigest(), 125)
        media = Media("synthetic-owner", "a" * 64, 0, VIDEO)
        path = write_private_cache(self.cache, media, asset)
        path.write_bytes(data + b"\nTAMPERED")
        with self.assertRaisesRegex(ValueError, "SHA256_MISMATCH"):
            self.flow.after_en_cached(asset, path)
        self.assertEqual(self.gemini.calls, [])

    def test_sdh_only_never_consumes_download_or_cloud(self):
        self.provider.en = (row(9, SDH, "en"),)
        result = self.flow.selected_media(VIDEO)
        self.assertEqual(result.status, "REVIEW_REQUIRED")
        self.assertEqual([x[0] for x in self.provider.calls], ["GET", "GET"])
        self.assertEqual(self.gemini.calls, [])

    def test_bad_video_name_rejected_before_provider(self):
        for bad in ("../movie.mkv", "", "Movie\n2017", "/tmp/media.mkv"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.flow.selected_media(bad)
        self.assertEqual(self.provider.calls, [])


if __name__ == "__main__":
    unittest.main()
