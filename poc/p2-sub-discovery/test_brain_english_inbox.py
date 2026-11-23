"""Offline tests: Brain SRT stage -> exact P3 binding -> existing AGY P2."""
from __future__ import annotations

import hashlib
from pathlib import Path
import tempfile
import unittest

from automatic_lean120_worker import AutomaticLean120Worker
from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from brain_english_inbox import (
    BrainEnglishUnavailable, acquire_brain_english, stage_brain_english,
)
from dual_subtitle_catalog import DualSubtitleCatalog
from fake_antigravity_cli import FakeAntigravity
from lean120_api import ModelProfile
from matcher import Media
from opensubtitles import OpenSubtitles
from owner_selected_file_resolver import _fingerprint


NAME = "Example.Film.2017.1080p.BluRay.x265-GRP.mkv"
MATCH = "Example.Film.2017.1080p.BluRay.x265-GRP_eng.srt"
MEDIA = Media("personal", "a" * 40, 2, NAME)
OTHER = Media("personal", "b" * 40, 2, NAME)
PAGE = "https://www.opensubtitles.org/en/subtitles/14190981/example-film-en"


def srt(count=125):
    return ("\n\n".join(
        f"{i}\n00:{(i // 60):02}:{(i % 60):02},000 --> "
        f"00:{(i // 60):02}:{(i % 60):02},900\nEnglish line {i}"
        for i in range(1, count + 1)) + "\n").encode("utf-8")


class BrainInboxTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.cache = self.root / "owner-cache"
        self.fixture = self.root / "english.srt"
        self.fixture.write_bytes(srt())
        self.fp = _fingerprint(*MEDIA.key)

    def stage(self, *, media=MEDIA, release_name=MATCH):
        return stage_brain_english(
            cache_root=self.cache,
            source_fingerprint=_fingerprint(*media.key),
            video_name=media.filename, release_name=release_name,
            source_page=PAGE, srt_file=self.fixture)

    def test_stage_then_exact_media_reuse_no_network(self):
        folder = self.stage()
        self.assertEqual(folder, self.stage())
        asset = acquire_brain_english(MEDIA, self.cache)
        self.assertEqual((asset.language, asset.fmt, asset.cues),
                         ("en", "srt", 125))
        self.assertEqual(asset.sha256, hashlib.sha256(srt()).hexdigest())
        with self.assertRaisesRegex(BrainEnglishUnavailable, "NOT_STAGED"):
            acquire_brain_english(OTHER, self.cache)

    def test_wrong_release_refused_before_translation(self):
        self.stage(release_name="Another.Film.2017.1080p.BluRay.x265-GRP.srt")
        with self.assertRaisesRegex(BrainEnglishUnavailable, "RELEASE_MISMATCH"):
            acquire_brain_english(MEDIA, self.cache)

    def test_tamper_and_conflicting_restage_fail(self):
        folder = self.stage()
        (folder / "english.srt").write_bytes(srt(124))
        with self.assertRaisesRegex(BrainEnglishUnavailable, "SRT_CHANGED"):
            acquire_brain_english(MEDIA, self.cache)
        with self.assertRaisesRegex(BrainEnglishUnavailable, "STAGE_CONFLICT"):
            self.stage()

    def test_p4_rejects_legacy_cache_without_staged_brain_english(self):
        from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
        from p3_p4_ready_registry import P3ReadyRejected
        self.cache.mkdir(parents=True, exist_ok=True)
        flow = self._flow(FakeAntigravity())
        with self.assertRaisesRegex(P3ReadyRejected, "P4_BRAIN_EN_NOT_READY"):
            R2OwnerProgressiveRegistry._recover_handoff(flow, self.fp, MEDIA)
        self.assertFalse(list((self.root / "state").rglob("batch-*.json")))

    def test_p4_rejects_old_ai_cache_for_new_brain_staged_source(self):
        from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
        from p3_p4_ready_registry import P3ReadyRejected
        from opensubtitles import Asset, write_private_cache
        self.stage()
        old = srt(124)
        digest = hashlib.sha256(old).hexdigest()
        old_asset = Asset(0, "en", "srt", old, digest, 124)
        old_file = write_private_cache(self.cache, MEDIA, old_asset)
        DualSubtitleCatalog(self.cache).record(
            MEDIA, self.fp, "ai_en", old_asset, old_file,
            release_matched=True)
        flow = self._flow(FakeAntigravity())
        with self.assertRaisesRegex(P3ReadyRejected, "P4_BRAIN_EN_CACHE_CONFLICT"):
            R2OwnerProgressiveRegistry._recover_handoff(flow, self.fp, MEDIA)
        self.assertEqual(flow.selected_media(
            NAME, verified_media=MEDIA,
            source_fingerprint=self.fp).status, "REVIEW_REQUIRED")

    def test_owner_cli_preflight_failure_is_retryable_without_model_call(self):
        from owner_session_bridge import PreProviderTransient
        self.stage()
        translated = FakeAntigravity()
        flow = self._flow(translated)
        def owner_cli_missing():
            raise ValueError("AGY_CLI_NOT_INSTALLED_FOR_OWNER")
        flow._model_preflight = owner_cli_missing
        with self.assertRaisesRegex(
                PreProviderTransient, "AGY_OWNER_PREFLIGHT_UNAVAILABLE"):
            flow.selected_media(NAME, verified_media=MEDIA,
                                source_fingerprint=self.fp)
        self.assertEqual(translated.calls, [])
        self.assertFalse(list((self.root / "state").rglob("batch-*.inflight")))
        flow._model_preflight = lambda: None
        self.assertEqual(flow.selected_media(
            NAME, verified_media=MEDIA,
            source_fingerprint=self.fp).status, "VIETSUB_READY")
        self.assertEqual([len(ids) for ids in translated.calls], [50, 75])

    def test_p4_final_ready_ai_cannot_bypass_brain_staged_source(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
        from p3_p4_ready_registry import P3ReadyRejected
        flow = self._flow(FakeAntigravity())
        registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: None)
        registry.bind_existing_flow(flow)
        registry._ready["media"] = SimpleNamespace(
            origin="en", media=MEDIA, source_sha256="0" * 64,
            total_cues=125)
        with self.assertRaisesRegex(P3ReadyRejected, "P4_BRAIN_EN_NOT_READY"):
            registry.resolve_ai_default("media")
        self.stage()
        with self.assertRaisesRegex(P3ReadyRejected, "P4_BRAIN_EN_CACHE_CONFLICT"):
            registry.resolve_ai_default("media")
        registry._ready["media"].source_sha256 = hashlib.sha256(srt()).hexdigest()
        with patch.object(registry, "resolve", return_value="READY") as resolved:
            self.assertEqual(registry.resolve_ai_default("media"), "READY")
            resolved.assert_called_once_with("media")
        registry._ready["media"].origin = "vi"
        with patch.object(registry, "resolve") as resolved:
            self.assertIsNone(registry.resolve_ai_default("media"))
            resolved.assert_not_called()

    def test_stage_requires_verified_local_input(self):
        with self.assertRaisesRegex(BrainEnglishUnavailable, "FINGERPRINT_INVALID"):
            stage_brain_english(
                cache_root=self.cache, source_fingerprint="a" * 40,
                video_name=NAME, release_name=MATCH,
                source_page=PAGE, srt_file=self.fixture)
        self.fixture.write_bytes(b"not a timed subtitle")
        with self.assertRaisesRegex(BrainEnglishUnavailable, "SRT_QA_FAILED"):
            self.stage()

    def _flow(self, translator):
        def no_api(*_args):
            raise AssertionError("NO_OPENSUBTITLES_REST_OR_WEB_AT_TV_TAP")
        worker = AutomaticLean120Worker(
            state_root=self.root / "state",
            profile=ModelProfile("antigravity", "gemini-4-hydrogen-high", "high"),
            glossary={}, runner=translator, first_window_cues=50)
        return AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="unused", transport=no_api),
            worker=worker, cache_root=self.cache,
            permissions=AutoPermissions(True, True), dual_mode=True,
            model_preflight=lambda: None,
            source_acquirer=acquire_brain_english)

    def test_missing_staged_file_does_not_invoke_agy_or_api(self):
        translator = FakeAntigravity()
        flow = self._flow(translator)
        self.assertEqual(
            flow.selected_media(NAME, verified_media=MEDIA,
                                source_fingerprint=self.fp).status,
            "REVIEW_REQUIRED")
        self.assertEqual(translator.calls, [])

    def test_tv_tap_uses_staged_srt_for_lean120_and_cache(self):
        self.stage()
        translator = FakeAntigravity(text_prefix="Vietnamese fixture")
        flow = self._flow(translator)
        first = flow.selected_media(NAME, verified_media=MEDIA,
                                    source_fingerprint=self.fp)
        second = flow.selected_media(NAME, verified_media=MEDIA,
                                     source_fingerprint=self.fp)
        self.assertEqual((first.status, second.status),
                         ("VIETSUB_READY", "VIETSUB_READY"))
        self.assertEqual([len(ids) for ids in translator.calls], [50, 75])
        receipt = DualSubtitleCatalog(self.cache).read(MEDIA, self.fp, "ai_en")
        self.assertTrue(receipt.release_matched)
        self.assertTrue(list((self.root / "state").rglob("vi-final.srt")))


if __name__ == "__main__":
    unittest.main()
