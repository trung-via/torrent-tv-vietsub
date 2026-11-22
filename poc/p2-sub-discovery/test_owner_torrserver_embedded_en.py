"""Offline fixtures for /ffp EN selection and /play MKV demux, no live peers."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from automatic_lean120_worker import AutomaticLean120Worker
from dual_subtitle_catalog import DualSubtitleCatalog
from lean120_api import ModelProfile
from matcher import Media
from opensubtitles import OpenSubtitles
from owner_selected_file_resolver import _fingerprint
from owner_torrserver_embedded_en import (
    EmbeddedEnglishUnavailable, OwnerTorrServerEmbeddedEnglishReader,
    _english_text_track, _run_ffmpeg,
)
from owner_torrserver_readonly import OwnerLocalTorrServer
from test_automatic_vietsub_flow import FakeGemini, FakeProvider, VIDEO, srt


def inventory(*tracks):
    return json.dumps({"streams": [
        {"index": 0, "codec_type": "video", "codec_name": "h264"},
        *tracks,
    ]}).encode()


def subtitle(index, language="eng", codec="subrip", default=0):
    return {"index": index, "codec_type": "subtitle", "codec_name": codec,
            "tags": {"language": language},
            "disposition": {"default": default}}


class EmbeddedEnglishTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.media = Media("owner-ts", "a" * 40, 3, VIDEO)
        self.config = OwnerLocalTorrServer("owner-ts", 8090)
        self.calls = []
        self.provider = FakeProvider()

    def make_reader(self, raw, *, output=None, status=0):
        def probe(url, timeout):
            self.calls.append(("PROBE", url, timeout))
            return raw

        def runner(args, timeout):
            self.calls.append(("FFMPEG", args, timeout))
            if output is not None:
                Path(args[-1]).write_bytes(output)
            return status

        return OwnerTorrServerEmbeddedEnglishReader(
            self.config, probe=probe, runner=runner)

    def test_english_global_index_and_default_selection(self):
        self.assertEqual(_english_text_track(inventory(
            subtitle(2, "en"), subtitle(3, "eng", "ass", default=1))), 3)
        self.assertEqual(_english_text_track(inventory(
            subtitle(1, "vi"), subtitle(4, "eng"))), 4)

    def test_no_text_en_or_ambiguous_english_fail_closed(self):
        for tracks, code in (
            ((subtitle(1, "eng", "hdmv_pgs_subtitle"),), "TEXT_TRACK_NOT_FOUND"),
            ((subtitle(1, "und"),), "TEXT_TRACK_NOT_FOUND"),
            ((subtitle(1, "eng"), subtitle(2, "en")), "TRACK_AMBIGUOUS"),
        ):
            with self.subTest(code=code):
                with self.assertRaisesRegex(EmbeddedEnglishUnavailable, code):
                    _english_text_track(inventory(*tracks))
        with self.assertRaisesRegex(EmbeddedEnglishUnavailable, "PROBE_INVALID"):
            _english_text_track(b'{"streams":[{"index":1},{"index":1}]}')

    def test_exact_local_play_url_and_srt_without_provider_call(self):
        reader = self.make_reader(inventory(subtitle(5)), output=srt(125))
        result = reader.extract(self.media, private_root=self.root / "cache")
        self.assertEqual((result.language, result.cues), ("en", 125))
        self.assertEqual(self.calls[0],
                         ("PROBE", "http://127.0.0.1:8090/ffp/" + "a" * 40 + "/3", 3.0))
        args = self.calls[1][1]
        self.assertIn("http://127.0.0.1:8090/play/" + "a" * 40 + "/3", args)
        self.assertEqual(args[args.index("-map") + 1], "0:5")
        self.assertEqual(self.provider.calls, [])
        self.assertFalse(list((self.root / "cache").glob(".embedded-en-*")))

    def test_bounded_unavailable_does_not_keep_partial_srt(self):
        reader = self.make_reader(inventory(subtitle(5)), output=srt(2), status=1)
        with self.assertRaisesRegex(EmbeddedEnglishUnavailable, "EXTRACT_UNAVAILABLE"):
            reader.extract(self.media, private_root=self.root / "cache")
        self.assertFalse(list((self.root / "cache").rglob("*.srt")))
        wrong = Media("other", "a" * 40, 3, VIDEO)
        with self.assertRaisesRegex(EmbeddedEnglishUnavailable, "MEDIA_INVALID"):
            reader.extract(wrong, private_root=self.root / "cache")
        self.assertEqual(len(self.calls), 2)

    def test_complete_owner_translation_from_embedded_en_zero_api(self):
        gemini = FakeGemini(text_prefix="Synthetic Vietnamese")
        worker = AutomaticLean120Worker(
            state_root=self.root / "state",
            profile=ModelProfile("antigravity", "gemini-4-hydrogen-high", "high"),
            glossary={}, runner=gemini)
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="offline", transport=self.provider),
            worker=worker, cache_root=self.root / "cache",
            permissions=AutoPermissions(True, True), dual_mode=True)
        flow.set_torrent_embedded_en(
            self.make_reader(inventory(subtitle(2)), output=srt(125)))
        fingerprint = _fingerprint("owner-ts", "a" * 40, 3)
        first = flow.selected_media(VIDEO, verified_media=self.media,
                                    source_fingerprint=fingerprint)
        repeat = flow.selected_media(VIDEO, verified_media=self.media,
                                     source_fingerprint=fingerprint)
        self.assertEqual((first.status, repeat.status),
                         ("VIETSUB_READY", "VIETSUB_READY"))
        self.assertEqual((first.get_requests, first.download_posts), (0, 0))
        self.assertEqual([len(cues) for cues in gemini.calls], [120, 5])
        self.assertEqual(self.provider.calls, [])
        self.assertEqual([kind for kind, *_ in self.calls], ["PROBE", "FFMPEG"])
        self.assertIsNotNone(DualSubtitleCatalog(self.root / "cache").read(
            self.media, fingerprint, "ai_en"))

    def test_no_embedded_english_never_searches_vi_or_open_subtitles(self):
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "state", profile=ModelProfile(
                "antigravity", "gemini-4-hydrogen-high", "high"),
            glossary={}, runner=gemini)
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="offline", transport=self.provider),
            worker=worker, cache_root=self.root / "cache",
            permissions=AutoPermissions(True, True), dual_mode=True)
        flow.set_torrent_embedded_en(self.make_reader(inventory(subtitle(2, "vi"))))
        result = flow.selected_media(VIDEO, verified_media=self.media,
                                     source_fingerprint=_fingerprint("owner-ts", "a" * 40, 3))
        self.assertEqual(result.status, "REVIEW_REQUIRED")
        self.assertEqual(self.provider.calls, [])
        self.assertEqual(gemini.calls, [])

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),
                         "FFmpeg tools missing")
    def test_real_ffmpeg_demux_on_original_tiny_mkv_fixture(self):
        """Media created locally by the test, never copyrighted or remote."""
        source = self.root / "source.srt"
        source.write_bytes(srt(2))
        movie = self.root / "original-test.mkv"
        subprocess.run([
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i",
            "color=c=black:s=64x64:r=1:d=4", "-f", "srt", "-i", str(source),
            "-map", "0:v", "-map", "1:s", "-c:v", "mpeg4",
            "-c:s", "srt", "-metadata:s:s:0", "language=eng",
            "-shortest", "-y", str(movie),
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        probed = subprocess.run([
            "ffprobe", "-v", "error", "-show_streams", "-of", "json", str(movie),
        ], check=True, capture_output=True).stdout

        def local_only_ffmpeg(args, timeout):
            self.assertIn("/play/", args[args.index("-i") + 1])
            args = args.copy()
            args[args.index("-i") + 1] = str(movie)
            return _run_ffmpeg(args, timeout)

        reader = OwnerTorrServerEmbeddedEnglishReader(
            self.config, probe=lambda url, timeout: probed, runner=local_only_ffmpeg)
        result = reader.extract(self.media, private_root=self.root / "cache")
        self.assertEqual(result.cues, 2)
        self.assertEqual(result.sha256, hashlib.sha256(result.contents).hexdigest())


if __name__ == "__main__":
    unittest.main()
