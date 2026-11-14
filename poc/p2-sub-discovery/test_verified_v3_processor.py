"""V3 event -> exact verified media -> existing D1/D2/LOCAL_EN/LEAN120.

All sources below are synthetic, user-private temp fixtures. No real LAN,
subtitles/provider traffic, Windows owner task, TV, or credentials.
"""
from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from matcher import Media
from owner_selected_file_resolver import (
    CurrentPlaying, TorrServerSelectedFile, OwnerPinnedFiles, _fingerprint,
)
from owner_session_bridge import (
    enqueue_selected_media, poll_private_events, _parse_event,
)
from verified_v3_processor import VerifiedV3Processor, V3IdentityError
from automatic_vietsub_flow import AutomaticVietsubFlow, AutoPermissions, AutoResult, select_vi_then_en
from automatic_lean120_worker import AutomaticLean120Worker
from lean120_api import ModelProfile
from opensubtitles import OpenSubtitles
from test_automatic_vietsub_flow import FakeProvider, FakeGemini, srt


VIDEO = "Example.Film.2017.1080p.BluRay.x265-GRP.mkv"
HASH = "a" * 40
SERVER = "trusted-windows-torrserver"
SESSION = "trusted-tv-session-1"


class CapturingFlow:
    def __init__(self):
        self.calls = []

    def selected_media(self, name, *, source_fingerprint=None,
                       verified_media=None, local_source=None):
        self.calls.append((name, source_fingerprint,
                           verified_media, local_source))
        return AutoResult("VI_READY")


class V3CompositionTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.media = self.root / "private-media"
        self.media.mkdir()
        self.video = self.media / VIDEO
        self.video.write_bytes(b"synthetic movie placeholder")
        self.side = self.media / (Path(VIDEO).stem + ".en.srt")
        self.side.write_bytes(srt(125))
        self.owner = self.root / "owner"
        self.state = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=SERVER, tv_session_id=SESSION,
            torrent_hash=HASH, file_index=5, video_name=VIDEO,
            owner_auto_enabled=True, viewer_choice="ON",
            media_rights_approved=True, local_vi_state="ABSENT")
        self.record = TorrServerSelectedFile(
            id=5, path="Authorized/" + VIDEO, length=self.video.stat().st_size)
        self.mapping = OwnerPinnedFiles(
            video_path=self.video, english_sidecar_path=self.side,
            video_file_complete=True)
        self.counter = 0
        self.read_calls = []
        self.capture = CapturingFlow()

    def read_tv(self):
        self.counter += 1
        self.read_calls.append("TV")
        return self.state

    def read_file(self, server, infohash, file_index):
        self.read_calls.append("SERVER")
        self.assertEqual((server, infohash, file_index), (SERVER, HASH, 5))
        return self.record

    def map_local(self, server, infohash, file_index, path):
        self.read_calls.append("OWNER")
        self.assertEqual((server, infohash, file_index, path),
                         (SERVER, HASH, 5, self.record.path))
        return self.mapping

    def processor(self, flow=None, read_tv=None):
        return VerifiedV3Processor(
            flow=flow or self.capture,
            private_media_root=self.media,
            read_verified_current_playback=read_tv or self.read_tv,
            read_verified_torrserver_file=self.read_file,
            locate_owner_pinned_files=self.map_local)

    def dispatch(self, processor=None):
        enqueue_selected_media(
            VIDEO, owner_root=self.owner,
            source_fingerprint=_fingerprint(SERVER, HASH, 5),
            tv_session_id=SESSION)
        lines = []
        count = poll_private_events(
            owner_root=self.owner, processor=processor or self.processor(),
            emit=lines.append)
        return count, lines

    def test_v3_event_payload_exactly_contains_private_session_and_media_key(self):
        enqueue_selected_media(
            VIDEO, owner_root=self.owner,
            source_fingerprint=_fingerprint(SERVER, HASH, 5),
            tv_session_id=SESSION)
        event_file, = list((self.owner / "inbox").glob("event-*.json"))
        raw = json.loads(event_file.read_text())
        self.assertEqual(raw["schema"], "TTV-OWNER-VIDEO-EVENT-V3")
        self.assertEqual(set(raw), {
            "schema", "event_id", "selected_video_filename",
            "source_fingerprint", "tv_session_id"})
        self.assertEqual(_parse_event(event_file).tv_session_id, SESSION)
        self.assertNotIn(HASH, event_file.read_text())
        self.assertNotIn("owner-private-media", event_file.read_text())

    def test_one_v3_event_feeds_same_verified_media_to_d1_and_local_route(self):
        processed, messages = self.dispatch()
        self.assertEqual(processed, 1)
        self.assertEqual(messages, ["OWNER_BRIDGE_EVENT_COMPLETE"])
        self.assertEqual(self.read_calls, ["TV", "SERVER", "OWNER", "TV"])
        self.assertEqual(len(self.capture.calls), 1)
        name, fp, media, local = self.capture.calls[0]
        self.assertEqual(name, VIDEO)
        self.assertEqual(fp, _fingerprint(SERVER, HASH, 5))
        self.assertEqual(media, Media(SERVER, HASH, 5, VIDEO))
        self.assertEqual(local.file_index, media.file_index)
        self.assertEqual(local.torrent_hash, media.torrent_hash)
        self.assertEqual(local.en_sidecar_path, self.side)

    def test_owner_private_event_same_filename_different_session_is_blocked(self):
        enqueue_selected_media(
            VIDEO, owner_root=self.owner,
            source_fingerprint=_fingerprint(SERVER, HASH, 5),
            tv_session_id="stale-previous-tv-session")
        emitted = []
        count = poll_private_events(
            owner_root=self.owner, processor=self.processor(),
            emit=emitted.append)
        self.assertEqual(count, 1)
        self.assertEqual(emitted, ["OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY"])
        self.assertEqual(self.capture.calls, [])
        self.assertFalse(list((self.owner / "inbox").glob("event-*.json")))

    def test_different_torrent_with_same_video_name_never_reuses_fingerprint(self):
        enqueue_selected_media(
            VIDEO, owner_root=self.owner,
            source_fingerprint=_fingerprint(SERVER, "b" * 40, 5),
            tv_session_id=SESSION)
        processed, emitted = self._consume()
        self.assertEqual(processed, 1)
        self.assertEqual(emitted, ["OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY"])
        self.assertEqual(self.read_calls, ["TV"])
        self.assertEqual(self.capture.calls, [])

    def _consume(self, flow=None):
        emitted = []
        count = poll_private_events(
            owner_root=self.owner, processor=self.processor(flow=flow),
            emit=emitted.append)
        return count, emitted

    def test_owner_off_other_missing_vi_unknown_blocks_before_provider(self):
        original = self.state
        for patch in ({"viewer_choice": "OFF"}, {"viewer_choice": "OTHER"},
                      {"owner_auto_enabled": False},
                      {"local_vi_state": "PRESENT"},
                      {"local_vi_state": "UNKNOWN"},
                      {"active": False},
                      {"media_rights_approved": False}):
            with self.subTest(patch=patch):
                self.state = replace(self.state, **patch)
                with self.assertRaises(Exception):
                    self.processor().selected_media(
                        VIDEO, source_fingerprint=_fingerprint(SERVER, HASH, 5),
                        tv_session_id=SESSION)
                self.assertEqual(self.capture.calls, [])
                self.state = original

    def test_playback_changed_on_final_read_is_not_dispatched(self):
        def changes():
            self.counter += 1
            return (self.state if self.counter == 1 else
                    replace(self.state, tv_session_id="next-tv-session"))
        with self.assertRaisesRegex(V3IdentityError, "TV_SELECTION_CHANGED"):
            self.processor(read_tv=changes).selected_media(
                VIDEO, source_fingerprint=_fingerprint(SERVER, HASH, 5),
                tv_session_id=SESSION)
        self.assertEqual(self.capture.calls, [])

    def test_no_local_movie_falls_back_to_exact_d1_d2_identity(self):
        self.mapping = None
        processed, emitted = self.dispatch()
        self.assertEqual(processed, 1)
        self.assertEqual(emitted, ["OWNER_BRIDGE_EVENT_COMPLETE"])
        _, _, media, source = self.capture.calls[0]
        self.assertEqual(media, Media(SERVER, HASH, 5, VIDEO))
        self.assertIsNone(source)

    def test_bad_episode_metadata_and_local_map_hold(self):
        self.record = replace(self.record, id=6)
        with self.assertRaises(Exception):
            self.processor().selected_media(
                VIDEO, source_fingerprint=_fingerprint(SERVER, HASH, 5),
                tv_session_id=SESSION)
        self.assertEqual(self.capture.calls, [])

    def test_real_existing_lean120_worker_with_fake_gemini_zero_provider_get_post(self):
        gemini = FakeGemini()
        provider = FakeProvider()
        worker = AutomaticLean120Worker(
            state_root=self.root / "work",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={}, api_key="synthetic-key", transport=gemini)
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.root / "cache",
            permissions=AutoPermissions(True, True))
        with mock.patch("builtins.input", side_effect=AssertionError("NO_HUMAN_PROMPT")):
            processed, emitted = self.dispatch(processor=self.processor(flow=flow))
        self.assertEqual((processed, emitted),
                         (1, ["OWNER_BRIDGE_EVENT_COMPLETE"]))
        self.assertEqual(provider.calls, [])
        self.assertEqual([len(part) for part in gemini.calls], [120, 5])

    def test_no_local_source_sends_exact_verified_media_to_real_d1_d2_router(self):
        # The release filename, torrent and *selected episode/file index* are
        # the search origin, not an unverified UI title or synthetic hash.
        self.mapping = None
        provider = FakeProvider()
        gemini = FakeGemini()
        worker = AutomaticLean120Worker(
            state_root=self.root / "work-d1",
            profile=ModelProfile("gemini", "gemini-4-hydrogen", "high"),
            glossary={}, api_key="synthetic-key", transport=gemini)
        flow = AutomaticVietsubFlow(
            client=OpenSubtitles(api_key="synthetic", transport=provider),
            worker=worker, cache_root=self.root / "cache-d1",
            permissions=AutoPermissions(True, True))
        with mock.patch(
            "automatic_vietsub_flow.select_vi_then_en",
            wraps=select_vi_then_en,
        ) as router:
            processed, emitted = self.dispatch(processor=self.processor(flow=flow))
        self.assertEqual((processed, emitted),
                         (1, ["OWNER_BRIDGE_EVENT_COMPLETE"]))
        self.assertEqual(router.call_count, 1)
        self.assertEqual(router.call_args.args[1],
                         Media(SERVER, HASH, 5, VIDEO))
        self.assertEqual([method for method, _ in provider.calls],
                         ["GET", "GET", "POST", "GET_BINARY"])
        self.assertEqual([len(part) for part in gemini.calls], [120, 5])

    def test_wrong_or_ambiguous_en_sidecar_prevents_provider_or_model(self):
        self.mapping = replace(self.mapping, english_sidecar_path=self.media / "Missing.en.srt")
        with self.assertRaises(Exception):
            self.processor().selected_media(
                VIDEO, source_fingerprint=_fingerprint(SERVER, HASH, 5),
                tv_session_id=SESSION)
        self.assertEqual(self.capture.calls, [])

    def test_legacy_v1_v2_events_do_not_claim_v3_current_session(self):
        enqueue_selected_media(
            VIDEO, owner_root=self.owner,
            source_fingerprint=_fingerprint(SERVER, HASH, 5))
        payload, = list((self.owner / "inbox").glob("event-*.json"))
        self.assertEqual(_parse_event(payload).tv_session_id, None)
        # No accidental upgrade of an old filename-only local envelope.
        self.assertEqual(_parse_event(payload).source_fingerprint,
                         _fingerprint(SERVER, HASH, 5))

    def test_invalid_v3_session_refused_prior_to_private_inbox_create(self):
        with self.assertRaisesRegex(ValueError, "V3_SESSION_INVALID"):
            enqueue_selected_media(
                VIDEO, owner_root=self.owner,
                source_fingerprint=_fingerprint(SERVER, HASH, 5),
                tv_session_id="../fake-session")
        self.assertFalse(self.owner.exists())


if __name__ == "__main__":
    unittest.main()
