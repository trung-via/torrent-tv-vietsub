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

from automatic_vietsub_flow import (
    AutomaticVietsubFlow, AutoPermissions, build_owner_auto_flow,
)
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

    def test_repeated_event_reuses_private_cache_and_model_checkpoints(self):
        initial = self.flow.selected_media(VIDEO)
        before = list(self.provider.calls)
        again = self.flow.selected_media(VIDEO)
        self.assertEqual(initial.status, "VIETSUB_READY")
        self.assertEqual(again.status, "VIETSUB_READY")
        self.assertEqual(again.get_requests, 0)
        self.assertEqual(again.download_posts, 0)
        self.assertEqual(self.provider.calls, before)
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])
        self.assertIn("AUTO_EN_CACHED_REUSED=YES", self.events)

    def test_restart_reuses_private_source_index_without_provider(self):
        self.flow.selected_media(VIDEO)
        fresh_client = OpenSubtitles(api_key="synthetic-key", transport=self.provider)
        restarted = AutomaticVietsubFlow(
            client=fresh_client, worker=self.worker, cache_root=self.cache,
            permissions=AutoPermissions(True, True), emit=self.events.append)
        before = list(self.provider.calls)
        result = restarted.selected_media(VIDEO)
        self.assertEqual(result.status, "VIETSUB_READY")
        self.assertEqual(self.provider.calls, before)
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])

    def test_vi_repeat_skips_download_and_all_models(self):
        self.provider.vi = (row(8, VI, "vi"),)
        initial = self.flow.selected_media(VIDEO)
        prior = list(self.provider.calls)
        repeated = self.flow.selected_media(VIDEO)
        self.assertEqual(initial.status, "VI_READY")
        self.assertEqual(repeated.status, "VI_READY")
        self.assertEqual(repeated.get_requests, 0)
        self.assertEqual(self.provider.calls, prior)
        self.assertEqual(self.gemini.calls, [])

    def test_tampered_private_index_cannot_fall_through_to_paid_search(self):
        self.flow.selected_media(VIDEO)
        path = next(self.cache.glob(".auto-source-*.json"))
        path.write_text('{"schema":"bad"}', encoding="utf-8")
        count = len(self.provider.calls)
        with self.assertRaisesRegex(SubtitleApiError, "AUTO_SOURCE_CACHE_INDEX_INVALID"):
            self.flow.selected_media(VIDEO)
        self.assertEqual(len(self.provider.calls), count)
        self.assertEqual([len(x) for x in self.gemini.calls], [120, 5])

    def test_tampered_cached_bytes_fail_without_network_retry(self):
        self.flow.selected_media(VIDEO)
        path = next(self.cache.glob("*.srt"))
        path.write_bytes(path.read_bytes() + b"tampered")
        count = len(self.provider.calls)
        with self.assertRaisesRegex(SubtitleApiError, "AUTO_SOURCE_CACHE_DIGEST_MISMATCH"):
            self.flow.selected_media(VIDEO)
        self.assertEqual(len(self.provider.calls), count)


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

    def test_owner_bootstrap_loads_keys_and_profile_once_no_questions(self):
        preflights = []
        with mock.patch.dict("os.environ", {
            "CI": "", "GITHUB_ACTIONS": "",
            "OPENSUBTITLES_API_KEY": "synthetic-open-sub-key",
            "GEMINI_API_KEY": "synthetic-gemini-key",
        }), mock.patch("builtins.input", side_effect=AssertionError("NO_PROMPTS")):
            auto = build_owner_auto_flow(
                enabled=True, cache_root=self.cache,
                state_root=self.root / "owner-state",
                model_preflight=lambda profile, key: preflights.append((profile, key)),
            )
        self.assertTrue(auto.permissions.auto_download)
        self.assertTrue(auto.permissions.auto_translate_en)
        self.assertEqual(len(preflights), 1)
        self.assertEqual(preflights[0][0].model, "gemini-4-hydrogen")
        self.assertEqual(preflights[0][0].thinking_level, "high")
        self.assertEqual(preflights[0][1], "synthetic-gemini-key")
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(self.gemini.calls, [])
        self.assertFalse(self.cache.exists())

    def test_owner_bootstrap_disabled_or_missing_key_fails_without_io(self):
        with mock.patch.dict("os.environ", {
            "CI": "", "GITHUB_ACTIONS": "",
            "OPENSUBTITLES_API_KEY": "", "GEMINI_API_KEY": "",
        }):
            with self.assertRaisesRegex(ValueError, "OWNER_SETTING_DISABLED"):
                build_owner_auto_flow(
                    enabled=False, cache_root=self.cache,
                    state_root=self.root / "owner-state")
            with self.assertRaisesRegex(ValueError, "OWNER_KEYS_NOT_PROVISIONED"):
                build_owner_auto_flow(
                    enabled=True, cache_root=self.cache,
                    state_root=self.root / "owner-state")
        self.assertFalse(self.cache.exists())

    def test_owner_bootstrap_model_preflight_fails_before_any_post(self):
        with mock.patch.dict("os.environ", {
            "CI": "", "GITHUB_ACTIONS": "",
            "OPENSUBTITLES_API_KEY": "test-open",
            "GEMINI_API_KEY": "test-gemini",
        }):
            with self.assertRaisesRegex(ValueError, "MODEL_NOT_AVAILABLE"):
                build_owner_auto_flow(
                    enabled=True, cache_root=self.cache,
                    state_root=self.root / "owner-state",
                    model_preflight=lambda profile, key:
                        (_ for _ in ()).throw(ValueError("MODEL_NOT_AVAILABLE")),
                )
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(self.gemini.calls, [])
        self.assertFalse(self.cache.exists())

    def test_owner_bootstrap_refuses_real_provider_in_github_actions(self):
        with mock.patch.dict("os.environ", {
            "CI": "true", "GITHUB_ACTIONS": "true",
            "OPENSUBTITLES_API_KEY": "test-open",
            "GEMINI_API_KEY": "test-gemini",
        }):
            with self.assertRaisesRegex(ValueError, "LIVE_PROVIDER_FORBIDDEN_IN_CI"):
                build_owner_auto_flow(
                    enabled=True, cache_root=self.cache,
                    state_root=self.root / "owner-state",
                    model_preflight=lambda profile, key: None)
        self.assertFalse(self.cache.exists())

    def test_verified_source_fingerprint_controls_private_cache_identity(self):
        first = "a" * 64
        second = "b" * 64
        result = self.flow.selected_media(VIDEO, source_fingerprint=first)
        self.assertEqual(result.status, "VIETSUB_READY")
        self.assertTrue((self.cache / (".auto-source-" + first + ".json")).exists())
        prior = list(self.provider.calls)
        # Re-selecting exact TorrServer file does not make new provider calls.
        replay = self.flow.selected_media(VIDEO, source_fingerprint=first)
        self.assertEqual(replay.status, "VIETSUB_READY")
        self.assertEqual(self.provider.calls, prior)
        self.assertEqual([len(ids) for ids in self.gemini.calls], [120, 5])
        # Same release filename from another torrent is NOT allowed to
        # reuse the first source as if it were the same movie session.
        with self.assertRaisesRegex(SubtitleApiError, "EN_DOWNLOAD_ALREADY_ATTEMPTED"):
            self.flow.selected_media(VIDEO, source_fingerprint=second)
        self.assertFalse((self.cache / (".auto-source-" + second + ".json")).exists())
        self.assertEqual([x[0] for x in self.provider.calls].count("POST"), 1)

    def test_invalid_opaque_media_fingerprint_rejected_before_search(self):
        for bad in ("not-hash", "A" * 64, "g" * 64, "", 123):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, "SOURCE_FINGERPRINT_INVALID"):
                    self.flow.selected_media(VIDEO, source_fingerprint=bad)
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(self.gemini.calls, [])

    def test_bad_video_name_rejected_before_provider(self):
        for bad in ("../movie.mkv", "", "Movie\n2017", "/tmp/media.mkv"):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                self.flow.selected_media(bad)
        self.assertEqual(self.provider.calls, [])


if __name__ == "__main__":
    unittest.main()
