"""No-network acceptance for one AGY-selected English subtitle -> P2 owner."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from agy_opensubtitles_acquisition import (
    AgyEnglishUnavailable, acquire_english,
)
from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from automatic_lean120_worker import AutomaticLean120Worker
from dual_subtitle_catalog import DualSubtitleCatalog
from fake_antigravity_cli import FakeAntigravity
from lean120_api import ModelProfile
from matcher import Media
from opensubtitles import Asset, OpenSubtitles
from owner_selected_file_resolver import _fingerprint


NAME = "Example.Film.2017.1080p.BluRay.x265-GRP.mkv"
MEDIA = Media("personal", "a" * 40, 2, NAME)
MATCH = "Example.Film.2017.1080p.BluRay.x265-GRP_eng.srt"


def srt(count=125):
    return ("\n\n".join(
        f"{i}\n00:{(i // 60):02}:{(i % 60):02},000 --> "
        f"00:{(i // 60):02}:{(i % 60):02},900\nEnglish line {i}"
        for i in range(1, count + 1)) + "\n").encode()


def outcome(**changes):
    data = {"status": "FOUND", "language": "en", "release_name": MATCH,
            "source_page": "https://www.opensubtitles.com/en/subtitles/12345",
            "file_name": "english.srt"}
    data.update(changes)
    return json.dumps({"event": "result", "result": {
        "status": "SUCCESS", "structured_output": data,
    }}) + "\n"


class FakeAgent:
    def __init__(self, *, stdout=None, contents=None, exit_code=0):
        self.stdout = outcome() if stdout is None else stdout
        self.contents = srt() if contents is None else contents
        self.exit_code = exit_code
        self.calls = []

    def __call__(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if self.contents is not False:
            (Path(kwargs["cwd"]) / "english.srt").write_bytes(self.contents)
        return subprocess.CompletedProcess(command, self.exit_code,
                                           stdout=self.stdout, stderr="")


class AgyAcquisitionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()

    def acquire(self, runner):
        return acquire_english(
            MEDIA, cache_root=self.root / "cache",
            model="gemini-4-hydrogen-high", thinking_level="high",
            runner=runner)

    def test_agent_chooses_method_and_downloads_verified_english_srt(self):
        runner = FakeAgent()
        asset = self.acquire(runner)
        self.assertEqual((asset.language, asset.fmt, asset.cues), ("en", "srt", 125))
        self.assertEqual(asset.sha256, hashlib.sha256(srt()).hexdigest())
        command, kwargs = runner.calls[0]
        self.assertIn("--sandbox", command)
        self.assertEqual(command[command.index("--mode") + 1], "auto")
        self.assertNotIn("--dangerously-skip-permissions", command)
        brief = json.loads(kwargs["input"])["message"]["content"]
        self.assertIn("Decide your own", brief)
        self.assertIn("any permitted source", brief)
        self.assertIn("SubDL", brief)
        self.assertNotIn("a" * 40, brief)  # no torrent hash/model-side private key
        self.assertNotIn("GEMINI_API_KEY", kwargs["env"])
        self.assertEqual(list((self.root / "cache").glob(".agy-opensub-*")), [])

    def test_mismatched_release_is_never_translated_or_cached(self):
        runner = FakeAgent(stdout=outcome(
            release_name="Another.Film.2017.1080p.BluRay.x265-GRP_eng.srt"))
        with self.assertRaisesRegex(AgyEnglishUnavailable, "RELEASE_MISMATCH"):
            self.acquire(runner)
        self.assertEqual(list((self.root / "cache").glob("*.srt")), [])

    def test_malformed_provenance_is_rejected(self):
        runner = FakeAgent(stdout=outcome(source_page="invalid\nreference"))
        with self.assertRaisesRegex(AgyEnglishUnavailable, "SOURCE_UNVERIFIED"):
            self.acquire(runner)

    def test_matching_opensubtitles_org_page_is_accepted(self):
        runner = FakeAgent(stdout=outcome(
            source_page="https://www.opensubtitles.org/en/subtitles/14190981/the-odyssey-en"))
        asset = self.acquire(runner)
        self.assertEqual(asset.cues, 125)

    def test_matching_srt_is_accepted_without_provider_restriction(self):
        for source in ("https://subdl.com/s/example",
                       "https://another.example/subtitle",
                       "embedded English track", "local SRT", ""):
            with self.subTest(source=source):
                asset = self.acquire(FakeAgent(stdout=outcome(source_page=source)))
                self.assertEqual(asset.cues, 125)

    def test_other_provider_does_not_bypass_release_matching(self):
        runner = FakeAgent(stdout=outcome(
            source_page="https://subdl.com/s/example",
            release_name="Another.Film.2017.1080p.BluRay.x265-GRP.srt"))
        with self.assertRaisesRegex(AgyEnglishUnavailable, "RELEASE_MISMATCH"):
            self.acquire(runner)

    def test_no_match_cannot_fabricate_english(self):
        runner = FakeAgent(stdout=outcome(
            status="NOT_FOUND", language="", release_name="",
            source_page="", file_name=""), contents=False)
        with self.assertRaisesRegex(AgyEnglishUnavailable, "NO_MATCH"):
            self.acquire(runner)

    def test_bad_timing_and_unknown_provider_effect_fail_closed(self):
        with self.assertRaisesRegex(AgyEnglishUnavailable, "TIMELINE_INVALID"):
            self.acquire(FakeAgent(contents=b"not a subtitle"))
        with self.assertRaisesRegex(AgyEnglishUnavailable, "RESULT_UNKNOWN"):
            self.acquire(FakeAgent(exit_code=7))

    def test_owner_uses_single_agent_source_then_existing_lean120_and_cache(self):
        cache = self.root / "cache"
        translator = FakeAntigravity(text_prefix="Vietnamese fixture")
        worker = AutomaticLean120Worker(
            state_root=self.root / "state",
            profile=ModelProfile("antigravity", "gemini-4-hydrogen-high", "high"),
            glossary={}, runner=translator, first_window_cues=50)
        acquisitions = []
        source = srt()
        asset = Asset(0, "en", "srt", source,
                      hashlib.sha256(source).hexdigest(), 125)

        def fetch(media, folder):
            acquisitions.append((media, folder))
            return asset

        def forbidden_network(*args):
            raise AssertionError("OLD_DISCOVERY_PATH_MUST_NOT_RUN")

        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="disabled", transport=forbidden_network),
            worker=worker, cache_root=cache,
            permissions=AutoPermissions(True, True), dual_mode=True,
            model_preflight=lambda: None, source_acquirer=fetch)
        fp = _fingerprint(*MEDIA.key)
        first = flow.selected_media(NAME, verified_media=MEDIA,
                                    source_fingerprint=fp)
        second = flow.selected_media(NAME, verified_media=MEDIA,
                                     source_fingerprint=fp)
        self.assertEqual((first.status, second.status),
                         ("VIETSUB_READY", "VIETSUB_READY"))
        self.assertEqual((first.cue_count, second.cue_count), (125, 125))
        self.assertEqual(len(acquisitions), 1)
        self.assertEqual([len(ids) for ids in translator.calls], [50, 75])
        receipt = DualSubtitleCatalog(cache).read(MEDIA, fp, "ai_en")
        self.assertTrue(receipt.release_matched)
        self.assertTrue(list((self.root / "state").rglob("vi-final.srt")))


if __name__ == "__main__":
    unittest.main()
