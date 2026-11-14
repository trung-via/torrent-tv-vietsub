"""LOCAL_EN_DIRECT offline tests. Fake tracks, fake extractor, fake provider/model."""
from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions
from automatic_lean120_worker import AutomaticLean120Worker
from lean120_api import ModelProfile
from opensubtitles import OpenSubtitles
from local_en_direct import (
    LocalMediaSelection, LocalSourceError, find_local_english,
)
from test_automatic_vietsub_flow import FakeProvider, FakeGemini, srt


VIDEO = "Example.Film.2017.1080p.BluRay.x265-GRP.mkv"
SIDECAR = "Example.Film.2017.1080p.BluRay.x265-GRP.en.srt"


class LocalDirectTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.media = self.root / "owner_media"
        self.media.mkdir()
        self.cache = self.root / "owner_cache"
        self.video = self.media / VIDEO
        self.sidecar = self.media / SIDECAR
        self.sidecar.write_bytes(srt(125))
        self.selection = LocalMediaSelection(
            attested=True, active=True, owner_authorized=True,
            viewer_choice="ON", local_vi_state="ABSENT",
            server_id="laptop-torrserver", torrent_hash="a" * 40,
            file_index=4, video_name=VIDEO,
            private_media_root=self.media, en_sidecar_path=self.sidecar,
        )

    def selected(self, **kwargs):
        vals = dict(self.selection.__dict__)
        vals.update(kwargs)
        return LocalMediaSelection(**vals)

    def test_direct_en_srt_bypasses_all_extractor_tools(self):
        def unavailable(*_):
            raise AssertionError("FFMPEG_FFPROBE_NOT_NEEDED")
        found = find_local_english(self.selection, cache_root=self.cache, runner=unavailable)
        self.assertEqual((found.source_kind, found.asset.cues, found.asset.language),
                         ("SIDECAR_SRT", 125, "en"))
        self.assertTrue(found.private_cache_file.is_file())
        self.assertEqual(found.asset.sha256, hashlib.sha256(srt(125)).hexdigest())

    def test_repeated_local_source_no_duplicate_cache_content(self):
        a = find_local_english(self.selection, cache_root=self.cache)
        b = find_local_english(self.selection, cache_root=self.cache)
        self.assertEqual(a.private_cache_file, b.private_cache_file)
        self.assertEqual(len(list(self.cache.glob("*.srt"))), 1)

    def test_different_file_index_and_server_do_not_share_local_asset_path(self):
        one = find_local_english(self.selection, cache_root=self.cache)
        other_ix = find_local_english(self.selected(file_index=5), cache_root=self.cache)
        other_srv = find_local_english(self.selected(server_id="other-laptop"), cache_root=self.cache)
        self.assertEqual(len({one.private_cache_file, other_ix.private_cache_file,
                              other_srv.private_cache_file}), 3)

    def test_empty_selection_can_fall_back_to_d2(self):
        self.assertIsNone(find_local_english(
            self.selected(en_sidecar_path=None), cache_root=self.cache))

    def test_sidecar_name_must_be_exact_english_same_movie(self):
        bad = self.media / "Another.en.srt"
        bad.write_bytes(srt(2))
        with self.assertRaisesRegex(LocalSourceError, "EXACT_EN"):
            find_local_english(self.selected(en_sidecar_path=bad), cache_root=self.cache)
        self.assertFalse(self.cache.exists())

    def test_invalid_srt_cannot_trigger_provider(self):
        self.sidecar.write_bytes(b"not a subtitle")
        with self.assertRaisesRegex(LocalSourceError, "TIMED_QA_FAILED"):
            find_local_english(self.selection, cache_root=self.cache)

    def test_symlink_and_outside_root_rejected(self):
        outside = self.root / SIDECAR
        outside.write_bytes(srt(1))
        with self.assertRaises(LocalSourceError):
            find_local_english(self.selected(en_sidecar_path=outside), cache_root=self.cache)
        alias = self.media / "Example.Film.2017.1080p.BluRay.x265-GRP.eng.srt"
        try:
            alias.symlink_to(self.sidecar)
        except (OSError, NotImplementedError):
            self.skipTest("symlink not available")
        with self.assertRaisesRegex(LocalSourceError, "SYMLINK_REFUSED"):
            find_local_english(self.selected(en_sidecar_path=alias), cache_root=self.cache)

    def test_viewer_off_local_vi_and_unattested_hold(self):
        for changes in ({"viewer_choice": "OFF"},
                        {"viewer_choice": "OTHER"},
                        {"local_vi_state": "PRESENT"},
                        {"local_vi_state": "UNKNOWN"},
                        {"attested": False}, {"active": False},
                        {"owner_authorized": False}):
            with self.subTest(changes=changes):
                with self.assertRaisesRegex(LocalSourceError, "NOT_AUTHORIZED"):
                    find_local_english(self.selected(**changes), cache_root=self.cache)

    def test_wrong_server_file_identity_and_path(self):
        for changes in ({"torrent_hash": "invalid"},
                        {"file_index": -1},
                        {"file_index": True},
                        {"server_id": "../unsafe"},
                        {"video_name": "fake/../movie.mkv"}):
            with self.subTest(changes=changes):
                with self.assertRaisesRegex(LocalSourceError, "IDENTITY_INVALID"):
                    find_local_english(self.selected(**changes), cache_root=self.cache)

    def test_vtt_is_converted_by_offline_ffmpeg_without_network(self):
        vtt = self.media / SIDECAR.replace(".srt", ".vtt")
        vtt.write_bytes(("WEBVTT" + chr(10)*2 + "00:00:01.000 --> 00:00:01.900" + chr(10) + "Synthetic subtitle" + chr(10)).encode("utf-8"))
        commands = []
        def fake(args, sec, cap):
            commands.append(args)
            return srt(2)
        result = find_local_english(self.selected(en_sidecar_path=vtt),
                                    cache_root=self.cache, runner=fake)
        self.assertEqual(result.source_kind, "SIDECAR_VTT")
        self.assertEqual(result.asset.cues, 2)
        self.assertEqual(len(commands), 1)
        self.assertIn("-protocol_whitelist", commands[0])
        self.assertEqual(commands[0][0], "ffmpeg")
        self.assertNotIn("http", ",".join(commands[0]))

    def test_embedded_text_track_from_complete_local_movie(self):
        self.video.write_bytes(b"synthetic local video placeholder")
        calls = []
        def fake(args, sec, cap):
            calls.append(args)
            if args[0] == "ffprobe":
                return json.dumps({"streams": [
                    {"index": 2, "codec_type": "subtitle", "codec_name": "hdmv_pgs_subtitle",
                     "tags": {"language": "eng"}},
                    {"index": 4, "codec_type": "subtitle", "codec_name": "subrip",
                     "tags": {"language": "eng", "title": "English"}},
                ]}).encode()
            return srt(3)
        found = find_local_english(
            self.selected(en_sidecar_path=None, video_path=self.video,
                          video_file_complete=True),
            cache_root=self.cache, runner=fake)
        self.assertEqual(found.source_kind, "EMBEDDED_TEXT")
        self.assertEqual(found.asset.cues, 3)
        self.assertEqual(len(calls), 2)
        self.assertIn("0:4", calls[1])
        self.assertIn("-protocol_whitelist", calls[1])

    def test_image_only_subtitle_returns_fallback_not_ocr(self):
        self.video.write_bytes(b"synthetic local video")
        calls = []
        def fake(args, _, __):
            calls.append(args)
            return json.dumps({"streams": [
                {"index": 4, "codec_type": "subtitle", "codec_name": "hdmv_pgs_subtitle",
                 "tags": {"language": "en"}}]}).encode()
        found = find_local_english(
            self.selected(en_sidecar_path=None, video_path=self.video,
                          video_file_complete=True),
            cache_root=self.cache, runner=fake)
        self.assertIsNone(found)
        self.assertEqual(len(calls), 1)

    def test_incomplete_movie_does_not_run_ffprobe_or_ffmpeg(self):
        self.video.write_bytes(b"still downloading")
        def forbidden(*_):
            raise AssertionError("NO_PROBE_FOR_INCOMPLETE_MOVIE")
        result = find_local_english(
            self.selected(en_sidecar_path=None, video_path=self.video,
                          video_file_complete=False),
            cache_root=self.cache, runner=forbidden)
        self.assertIsNone(result)

    def test_multiple_english_tracks_are_held_for_review(self):
        self.video.write_bytes(b"synthetic")
        def fake(args, *_):
            if args[0] == "ffprobe":
                return json.dumps({"streams": [
                    {"index": 1, "codec_type": "subtitle", "codec_name": "ass",
                     "tags": {"language": "eng"}},
                    {"index": 2, "codec_type": "subtitle", "codec_name": "subrip",
                     "tags": {"language": "eng"}},
                ]}).encode()
            raise AssertionError("NO_EXTRACT")
        with self.assertRaisesRegex(LocalSourceError, "MULTIPLE_TEXT_TRACKS"):
            find_local_english(
                self.selected(en_sidecar_path=None, video_path=self.video,
                              video_file_complete=True),
                cache_root=self.cache, runner=fake)

    def test_fail_to_extract_never_returns_partial_subtitles(self):
        self.video.write_bytes(b"synthetic")
        def fake(args, *_):
            if args[0] == "ffprobe":
                return json.dumps({"streams": [
                    {"index": 0, "codec_type": "subtitle", "codec_name": "ass",
                     "tags": {"language": "eng"}}]}).encode()
            raise LocalSourceError("LOCAL_SUBTITLE_TOOL_UNAVAILABLE_OR_TIMEOUT")
        with self.assertRaisesRegex(LocalSourceError, "TOOL_UNAVAILABLE"):
            find_local_english(
                self.selected(en_sidecar_path=None, video_path=self.video,
                              video_file_complete=True),
                cache_root=self.cache, runner=fake)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),
                         "FFmpeg/FFprobe not available")
    def test_real_ffmpeg_embedded_english_mkv_from_generated_tiny_fixture(self):
        """Exercise actual offline tool syntax; generate fictional 64x64 media."""
        self.sidecar.write_bytes(srt(2))
        cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-v", "error",
               "-f", "lavfi", "-i", "color=c=black:s=64x64:r=1:d=4",
               "-i", str(self.sidecar), "-map", "0:v:0", "-map", "1:s:0",
               "-c:v", "mpeg4", "-c:s", "srt",
               "-metadata:s:s:0", "language=eng", "-shortest",
               "-y", str(self.video)]
        subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       check=True, timeout=30)
        out = find_local_english(
            self.selected(en_sidecar_path=None, video_path=self.video,
                          video_file_complete=True),
            cache_root=self.cache)
        self.assertEqual(out.source_kind, "EMBEDDED_TEXT")
        self.assertEqual(out.asset.cues, 2)
        self.assertEqual(out.asset.language, "en")
        self.assertTrue(out.private_cache_file.exists())

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"),
                         "FFmpeg/FFprobe not available")
    def test_real_ffmpeg_vtt_to_srt_from_generated_fixture(self):
        """A real local VTT can flow to existing SRT-only LEAN120 receipt."""
        vtt = self.media / SIDECAR.replace(".srt", ".vtt")
        vtt.write_bytes(b"WEBVTT\\n\\n00:00:01.000 --> 00:00:01.900\\nSynthetic subtitle\\n")
        out = find_local_english(self.selected(en_sidecar_path=vtt),
                                 cache_root=self.cache)
        self.assertEqual(out.source_kind, "SIDECAR_VTT")
        self.assertEqual(out.asset.cues, 1)
        self.assertIn(b"00:00:01,000 --> 00:00:01,900", out.asset.contents)

    def test_direct_local_en_enters_existing_p2_lean120_no_opensubtitles_calls(self):
        provider = FakeProvider()
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "worker",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={}, api_key="synthetic-key", transport=gemini,
        )
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.cache,
            permissions=AutoPermissions(True, True),
        )
        with mock.patch("builtins.input", side_effect=AssertionError("NO_HUMAN_PROMPTS")):
            done = flow.selected_media(VIDEO, local_source=self.selection)
            again = flow.selected_media(VIDEO, local_source=self.selection)
        self.assertEqual((done.status, done.translated_cues, done.download_posts),
                         ("VIETSUB_READY", 125, 0))
        self.assertEqual(again.status, "VIETSUB_READY")
        self.assertEqual(provider.calls, [])
        self.assertEqual([len(x) for x in gemini.calls], [120, 5])
        self.assertEqual(len(list(self.root.rglob("vi-final.srt"))), 1)

    def test_when_local_missing_uses_existing_vi_fast_d2_fallback(self):
        provider = FakeProvider()
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "worker",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={}, api_key="synthetic-key", transport=gemini,
        )
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.cache,
            permissions=AutoPermissions(True, True),
        )
        out = flow.selected_media(VIDEO, local_source=self.selected(en_sidecar_path=None))
        self.assertEqual(out.status, "VIETSUB_READY")
        self.assertEqual([m for m, _ in provider.calls], ["GET", "GET", "POST", "GET_BINARY"])

    def test_invalid_local_source_must_not_fall_back_to_paid_post(self):
        provider = FakeProvider()
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "worker",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={}, api_key="synthetic-key", transport=gemini,
        )
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.cache,
            permissions=AutoPermissions(True, True),
        )
        wrong = self.media / "Wrong.en.srt"
        wrong.write_bytes(srt(2))
        with self.assertRaisesRegex(LocalSourceError, "EXACT_EN"):
            flow.selected_media(VIDEO, local_source=self.selected(
                en_sidecar_path=wrong))
        self.assertEqual(provider.calls, [])
        self.assertEqual(gemini.calls, [])


if __name__ == "__main__":
    unittest.main()
