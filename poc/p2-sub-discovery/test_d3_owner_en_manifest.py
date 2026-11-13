"""D3 EN manifest safety tests: entirely synthetic, no downloads or model."""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from matcher import Media, SearchResults, Subtitle, choose
from opensubtitles import Asset, Candidate, Discovery, SubtitleApiError
from vi_en_fallback import Route
from d3_owner_en_manifest import OwnerBinding, stage_confirmed_en_manifest


SRT = b"1\n00:00:01,000 --> 00:00:02,000\nOriginal test line\n"


class D3OwnerHandoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.cached = self.root / "licensed-source.en.srt"
        self.cached.write_bytes(SRT)
        self.media = Media("trusted-profile", "a" * 40, 1,
                           "Original.Film.2024.WEB-DL.1080p-GRP.mkv")
        subtitle = Subtitle("7", "Original.Film.2024.WEB-DL.1080p-GRP.srt", "en")
        en_results = SearchResults(self.media.key, (subtitle,))
        en_decision = choose(self.media, en_results)
        self.assertEqual(en_decision.status, "EN_TRANSLATE")
        en = Discovery(self.media.key, en_results, (Candidate(7, subtitle),),
                       en_decision)
        vi_results = SearchResults(self.media.key, ())
        vi = Discovery(self.media.key, vi_results, (),
                       choose(self.media, vi_results))
        self.route = Route("EN_TRANSLATE", "CONFIDENT_EN_RELEASE", "en", 7,
                           vi, en, 2)
        self.asset = Asset(7, "en", "srt", SRT,
                           hashlib.sha256(SRT).hexdigest(), 1)
        self.binding = OwnerBinding("media." + "b" * 64, self.media.key,
                                    True, True, True)

    def stage(self, **changes):
        values = dict(media=self.media, route=self.route, asset=self.asset,
                      cached_file=self.cached, private_root=self.root,
                      binding=self.binding)
        values.update(changes)
        return stage_confirmed_en_manifest(**values)

    def test_manifest_matches_existing_p2_schema(self):
        result = self.stage()
        content = json.loads(result.read_text("utf-8"))
        self.assertEqual(content["schema"], "TTV-P2-OWNER-MATCHED-EN-V1")
        self.assertEqual(len(content["sources"]), 1)
        self.assertEqual(content["sources"][0]["media_key"],
                         self.binding.p4_media_key)
        self.assertEqual(content["sources"][0]["source_sha256"],
                         self.asset.sha256)
        self.assertTrue(content["sources"][0]["owner_confirmed_match"])
        self.assertEqual(Path(content["sources"][0]["source_path"]), self.cached)

    def test_never_overwrite_existing_manifest(self):
        original = self.stage().read_bytes()
        with self.assertRaises(SubtitleApiError):
            self.stage()
        self.assertEqual((self.root / "verified-en-manifest.json").read_bytes(),
                         original)

    def test_reject_unconfirmed_or_cross_media_binding(self):
        variants = (
            replace(self.binding, p4_hmac_observed=False),
            replace(self.binding, torrserver_file_observed=False),
            replace(self.binding, owner_confirmed_release_and_sync=False),
            replace(self.binding, p4_media_key="media." + "Z" * 64),
            replace(self.binding, d1_media_identity=("wrong", "a" * 40, 1)),
        )
        for binding in variants:
            with self.subTest(binding=binding):
                with self.assertRaises(SubtitleApiError):
                    self.stage(binding=binding)

    def test_reject_unverified_local_trial_identity(self):
        media = replace(self.media, server_profile_id="owner-fallback-unverified")
        binding = replace(self.binding, d1_media_identity=media.key)
        with self.assertRaises(SubtitleApiError):
            self.stage(media=media, binding=binding)

    def test_reject_vi_first_ambiguous_and_mismatched_file(self):
        for route in (
            replace(self.route, status="VI_READY", language="vi"),
            replace(self.route, status="REVIEW_REQUIRED"),
            replace(self.route, selected_file_id=8),
        ):
            with self.subTest(route=route.status):
                with self.assertRaises(SubtitleApiError):
                    self.stage(route=route)

    def test_reject_digest_and_changed_cache_bytes(self):
        with self.assertRaises(SubtitleApiError):
            self.stage(asset=replace(self.asset, sha256="0" * 64))
        self.cached.write_bytes(b"1\n00:00:01,000 --> 00:00:02,000\nTampered\n")
        with self.assertRaises(SubtitleApiError):
            self.stage()

    def test_reject_non_private_cache_and_bad_language(self):
        with self.assertRaises(SubtitleApiError):
            self.stage(cached_file=Path("relative.srt"))
        with self.assertRaises(SubtitleApiError):
            self.stage(asset=replace(self.asset, language="vi"))
        with self.assertRaises(SubtitleApiError):
            self.stage(asset=replace(self.asset, cues=2))

    def test_fail_closed_has_no_partial_manifest(self):
        with self.assertRaises(SubtitleApiError):
            self.stage(asset=replace(self.asset, file_id=8))
        self.assertFalse((self.root / "verified-en-manifest.json").exists())
        self.assertEqual(list(self.root.glob(".d3-manifest-*")), [])


if __name__ == "__main__":
    unittest.main()
