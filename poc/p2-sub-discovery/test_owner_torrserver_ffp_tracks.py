"""Stream-only P3→Owner→D1/D2 tests with exact TorrServer /ffp.

Every test uses only synthetic media metadata. No ADB, paid API, real torrent,
external network, LAN listener, private credentials or user media content.
"""
from __future__ import annotations

import hashlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import unittest
from unittest import mock

_POC = Path(__file__).resolve().parent.parent
for folder in ("p2-aisub", "p3-vietsub-trigger"):
    p = str(_POC / folder)
    if p not in sys.path:
        sys.path.insert(0, p)

from owner_p3_p4_private_policy import (
    PrivateP3P4Policy, OwnerPolicyBlocked,
)
from owner_torrserver_ffp_tracks import (
    TorrServerFfpTrackReader, _vi_embedded_track_state, _read_local_ffp,
)
from owner_selected_file_resolver import CurrentPlaying, _fingerprint
from owner_torrserver_readonly import OwnerTorrServerReader, OwnerLocalTorrServer
from verified_v3_processor import VerifiedV3Processor
from automatic_vietsub_flow import AutoResult

HASH = "a" * 40
NAME = "Synthetic.Authorized.2017.1080p.BluRay-GRP.mkv"
TSPATH = "Synthetic/" + NAME
PROFILE = "owner-test"
SESSION = "b" * 32
VIDEO_ONLY = {"streams": [{"codec_type": "video", "codec_name": "h264"}]}
EN_ONLY = {"streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "subtitle", "tags": {"language": "eng"}},
]}
VI = {"streams": [
    {"codec_type": "video", "codec_name": "h264"},
    {"codec_type": "subtitle", "tags": {"language": "vie"}},
]}


class StreamOnlyPolicyTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory(prefix="ttv-stream-policy-")
        self.addCleanup(t.cleanup)
        self.root = Path(t.name).resolve()
        self.owner = self.root / "OwnerBridge"
        self.owner.mkdir()
        self.media = self.root / "empty-private-media"
        self.media.mkdir()
        self.policy_path = self.owner / "p3-p4-policy.json"
        self.item = {
            "torrent_hash": HASH, "file_index": 2,
            "torrserver_path": TSPATH, "video_path": None,
            "stream_only": True, "rights_approved": True,
        }
        self.cfg = {
            "schema": "TTV-P3-P4-OWNER-POLICY-V1",
            "enabled": True, "profile_id": PROFILE,
            "torrserver_port": 8090,
            "private_media_root": str(self.media),
            "media": [self.item],
        }
        self.selected = TSPATH
        self.meta_calls = 0
        self.inventory_calls = []
        self.probe_data = json.dumps(EN_ONLY).encode()
        self.ts = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE, 8090),
            transport=self.get_metadata)

    def get_metadata(self, url, payload, timeout):
        self.meta_calls += 1
        self.assertEqual(url, "http://127.0.0.1:8090/torrents")
        self.assertEqual(json.loads(payload), {"action": "get", "hash": HASH})
        return json.dumps({
            "hash": HASH,
            "file_stats": [{"id": 2, "path": self.selected, "length": 100_000}],
        }).encode()

    def get_ffp(self, url, timeout):
        self.inventory_calls.append((url, timeout))
        return self.probe_data

    def make_policy(self, *, probe=True):
        self.policy_path.write_text(json.dumps(self.cfg), encoding="utf-8")
        return PrivateP3P4Policy(
            manifest=self.policy_path, owner_root=self.owner,
            private_media_root=self.media, torrserver=self.ts,
            stream_probe=(TorrServerFfpTrackReader(
                self.ts, transport=self.get_ffp) if probe else None))

    def test_approved_exact_stream_with_verified_en_track_routes_to_d1_d2(self):
        policy = self.make_policy()
        self.assertTrue(policy.media_rights_allowed(PROFILE, HASH, 2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE, HASH, 2),
                         "ABSENT")
        self.assertIsNone(policy.locate_owner_pinned_files(
            PROFILE, HASH, 2, TSPATH))
        self.assertEqual(self.inventory_calls, [
            ("http://127.0.0.1:8090/ffp/" + HASH + "/2", 3.0)])
        calls = []
        class SyntheticFlow:
            def selected_media(self, video, *, verified_media,
                               source_fingerprint, local_source):
                calls.append((video, verified_media, source_fingerprint, local_source))
                return AutoResult("REVIEW_REQUIRED")
        current = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=PROFILE, tv_session_id=SESSION,
            torrent_hash=HASH, file_index=2, video_name=NAME,
            owner_auto_enabled=True, viewer_choice="REQUESTED",
            media_rights_approved=policy.media_rights_allowed(PROFILE, HASH, 2),
            local_vi_state=policy.verified_local_vi_state(PROFILE, HASH, 2))
        v3 = VerifiedV3Processor(
            flow=SyntheticFlow(), private_media_root=self.media,
            read_verified_current_playback=lambda: current,
            read_verified_torrserver_file=self.ts,
            locate_owner_pinned_files=policy.locate_owner_pinned_files)
        v3.selected_media(NAME, source_fingerprint=_fingerprint(PROFILE,HASH,2),
                          tv_session_id=SESSION)
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], NAME)
        self.assertEqual(calls[0][1].torrent_hash, HASH)
        self.assertIsNone(calls[0][3])  # Existing D1/D2, not fake local EN.

    def test_incomplete_or_ambiguous_ffp_holds_without_inventing_vi_absence(self):
        policy = self.make_policy()
        for obj in (
            {"streams": []},
            {"streams": [{"codec_type":"subtitle","tags":{"language":"eng"}}]},
            {"streams": [{"codec_type":"video"},
                         {"codec_type":"subtitle","tags":{"language":"und"}}]},
            {"streams": [{"codec_type":"video"},
                         {"codec_type":"subtitle"}]},
            {"streams": [{"codec_type":"video"},
                         {"codec_type":"subtitle","tags":{"language":"zzzz"}}]},
            {"streams": "not-an-array"},
        ):
            with self.subTest(obj=obj):
                self.probe_data = json.dumps(obj).encode()
                self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),
                                 "UNKNOWN")
        self.probe_data = b"not json"
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        self.probe_data = json.dumps(VI).encode()
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"PRESENT")

    def test_no_explicit_stream_mode_or_no_rights_blocks_ffp(self):
        self.item["stream_only"] = False
        with self.assertRaises(OwnerPolicyBlocked):
            self.make_policy()
        self.item["stream_only"] = True
        self.item["rights_approved"] = False
        policy = self.make_policy()
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        self.assertEqual(self.inventory_calls, [])
        self.item["rights_approved"] = True
        policy = self.make_policy(probe=False)
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        self.assertEqual(self.inventory_calls, [])

    def test_wrong_torrserver_path_profile_hash_index_does_not_probe(self):
        policy = self.make_policy()
        self.selected = "Another/" + NAME
        self.assertFalse(policy.media_rights_allowed(PROFILE,HASH,2))
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,2),"UNKNOWN")
        self.selected = TSPATH
        self.assertEqual(policy.verified_local_vi_state(PROFILE,"f"*40,2),"UNKNOWN")
        self.assertEqual(policy.verified_local_vi_state("other",HASH,2),"UNKNOWN")
        self.assertEqual(policy.verified_local_vi_state(PROFILE,HASH,3),"UNKNOWN")
        self.assertFalse(self.inventory_calls)

    def test_get_stream_probe_uses_real_os_loopback_without_public_lan(self):
        expected = "/ffp/" + HASH + "/2"
        class OnlyLocalHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.server.seen.append(self.path)
                if self.path != expected:
                    self.send_error(404)
                    return
                payload = json.dumps(EN_ONLY).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            def log_message(self, *_):
                return
        with HTTPServer(("127.0.0.1", 0), OnlyLocalHandler) as server:
            server.seen = []
            listener = threading.Thread(target=server.serve_forever, daemon=True)
            listener.start()
            try:
                url = "http://127.0.0.1:" + str(server.server_port) + expected
                self.assertEqual(_vi_embedded_track_state(
                    _read_local_ffp(url, 3.0)), "ABSENT")
                self.assertEqual(server.seen, [expected])
            finally:
                server.shutdown()
                listener.join(timeout=3)


class WireParserTests(unittest.TestCase):
    def test_missing_or_bogus_video_or_subtitle_language_is_unknown(self):
        self.assertEqual(_vi_embedded_track_state(b""), "UNKNOWN")
        self.assertEqual(_vi_embedded_track_state(b"{}"), "UNKNOWN")
        self.assertEqual(_vi_embedded_track_state(json.dumps(VIDEO_ONLY).encode()),
                         "ABSENT")
        self.assertEqual(_vi_embedded_track_state(json.dumps(VI).encode()),
                         "PRESENT")
        mixed = {"streams": [{"codec_type":"video"},
                             {"codec_type":"subtitle","tags":{"language":"vie"}},
                             {"codec_type":"subtitle","tags":{"language":"und"}}]}
        self.assertEqual(_vi_embedded_track_state(json.dumps(mixed).encode()),
                         "PRESENT")
        self.assertEqual(_vi_embedded_track_state(b"x" * 65537), "UNKNOWN")

    def test_wrong_scope_never_calls_transport(self):
        fake = mock.Mock(return_value=json.dumps(EN_ONLY).encode())
        ts = OwnerTorrServerReader(OwnerLocalTorrServer(PROFILE,8090),
                                  transport=lambda *_: b"{}")
        probe = TorrServerFfpTrackReader(ts,transport=fake)
        for args in (("other", HASH, 2), (PROFILE, "zzz", 2),
                     (PROFILE, HASH, -1), (PROFILE, HASH, True)):
            self.assertEqual(probe(*args), "UNKNOWN")
        fake.assert_not_called()


if __name__ == "__main__":
    unittest.main()
