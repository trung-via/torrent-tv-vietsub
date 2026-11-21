"""Offline /subs companion-file tests; no real TorrServer, provider or TV."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from automatic_lean120_worker import AutomaticLean120Worker
from cue_pipeline import parse_cues, render
from lean120_api import ModelProfile
from matcher import Media
from opensubtitles import OpenSubtitles
from owner_selected_file_resolver import _fingerprint
from owner_torrserver_readonly import OwnerLocalTorrServer
from owner_torrserver_subs import (
    OwnerTorrServerSubtitleReader, TorrServerSubsUnavailable,
)
from test_automatic_vietsub_flow import FakeGemini, FakeProvider, VIDEO, srt


class SidecarTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.media = Media("owner-ts", "a" * 40, 3, VIDEO)
        self.config = OwnerLocalTorrServer("owner-ts", 8090)
        self.requests = []
        self.vi_payload = render(parse_cues(srt(2), "srt"), "vtt")
        self.en_payload = render(parse_cues(srt(125), "srt"), "vtt")
        self.entries = [
            {"index": 4, "name": VIDEO + ".en.srt", "format": "srt",
             "lang": "en", "url": "http://bad.example/steal"},
        ]

    def transport(self, url, timeout, cap):
        self.requests.append((url, timeout, cap))
        if "?track=" not in url:
            return json.dumps(self.entries).encode()
        if "track=4" in url:
            return self.en_payload
        if "track=5" in url:
            return self.vi_payload
        raise AssertionError("UNEXPECTED_TRACK")

    def reader(self):
        return OwnerTorrServerSubtitleReader(self.config, transport=self.transport)

    def test_external_en_is_downloaded_as_srt_without_trusting_returned_url(self):
        reader = self.reader()
        inventory = reader.list_for_media(self.media)
        self.assertIsNone(inventory.vi)
        self.assertEqual(inventory.en.index, 4)
        result = reader.download(inventory, inventory.en)
        self.assertEqual((result.language, result.fmt, result.cues), ("en", "srt", 125))
        self.assertTrue(result.contents.startswith(b"1\n00:00:01,000 -->"))
        self.assertEqual(len(self.requests), 2)
        for url, _, _ in self.requests:
            self.assertTrue(url.startswith("http://127.0.0.1:8090/subs/"))
            self.assertNotIn("bad.example", url)

    def test_vi_und_detected_by_explicit_filename_suffix(self):
        self.entries = [{"index": 5, "name": VIDEO + ".vi.srt",
                         "format": "srt", "lang": "und"}]
        inventory = self.reader().list_for_media(self.media)
        self.assertIsNone(inventory.en)
        self.assertEqual(inventory.vi.index, 5)
        self.assertEqual(self.reader().download(inventory, inventory.vi).cues, 2)

    def test_ambiguous_multiple_en_and_mkv_only_skip(self):
        self.entries.append({"index": 6, "name": VIDEO + ".eng.ass",
                             "format": "ass", "lang": "en"})
        self.assertIsNone(self.reader().list_for_media(self.media).en)
        self.entries = []  # Embedded English MKV tracks are never in /subs.
        self.assertIsNone(self.reader().list_for_media(self.media).en)
        self.assertEqual(len(self.requests), 2)  # No MKV or /ffp request.

    def test_wrong_server_never_contacts_torrserver(self):
        with self.assertRaises(TorrServerSubsUnavailable):
            self.reader().list_for_media(Media("other", "a" * 40, 3, VIDEO))
        self.assertEqual(self.requests, [])

    def test_flow_prefers_torrent_vi_without_remote_provider_or_ai(self):
        self.entries = [{"index": 5, "name": VIDEO + ".vi.srt",
                         "format": "srt", "lang": "und"}]
        flow, provider, gemini = self.build_flow()
        found = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=self.fingerprint())
        self.assertEqual((found.status, found.cue_count), ("VI_READY", 2))
        self.assertEqual(provider.calls, [])
        self.assertEqual(gemini.calls, [])
        again = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=self.fingerprint())
        self.assertEqual(again.status, "VI_READY")
        self.assertEqual(len(self.requests), 2)  # Cache reuses the first result.

    def test_flow_prefers_os_vi_then_torrent_en_and_translates_once(self):
        flow, provider, gemini = self.build_flow()
        found = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=self.fingerprint())
        self.assertEqual((found.status, found.cue_count, found.download_posts),
                         ("VIETSUB_READY", 125, 0))
        self.assertEqual([method for method, _ in provider.calls], ["GET"])
        self.assertEqual([len(cues) for cues in gemini.calls], [120, 5])
        again = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=self.fingerprint())
        self.assertEqual(again.status, "VIETSUB_READY")
        self.assertEqual(len(gemini.calls), 2)
        self.assertEqual(len(self.requests), 2)

    def test_download_failure_uses_existing_opensubtitles_en_once(self):
        self.en_payload = b"broken webvtt"
        flow, provider, gemini = self.build_flow()
        found = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=self.fingerprint())
        self.assertEqual(found.status, "VIETSUB_READY")
        self.assertEqual([method for method, _ in provider.calls],
                         ["GET", "GET", "POST", "GET_BINARY"])
        self.assertEqual([len(cues) for cues in gemini.calls], [120, 5])

    def fingerprint(self):
        return _fingerprint(self.media.server_profile_id,
                            self.media.torrent_hash, self.media.file_index)

    def build_flow(self):
        provider = FakeProvider()
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "worker",
            profile=ModelProfile("antigravity", "gemini-4-hydrogen-high", "high"),
            glossary={}, runner=gemini)
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.root / "cache",
            permissions=AutoPermissions(True, True))
        flow.set_torrent_sidecars(self.reader())
        return flow, provider, gemini
