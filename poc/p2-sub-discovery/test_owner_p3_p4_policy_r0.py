"""R0 selected-file inspection avoids redundant TorrServer reads (synthetic)."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import time
import unittest

from owner_p3_p4_policy_r0 import R0PrivateP3P4Policy
from owner_torrserver_readonly import OwnerTorrServerReader, OwnerLocalTorrServer
from owner_selected_file_resolver import TorrServerSelectedFile
from p3_owner_current_redmi import OwnerCurrentRedmiReader
from p3_redmi_current_state import SignedRedmiStateCache, sign_synthetic_state

KEY = bytes(range(32))
HASH = "a" * 40
NAME = "Synthetic.2017.1080p.WEB-DL-GRP.mkv"
PATH = "Fixture/" + NAME


class R0PolicySingleReadTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        self.owner = root / "OwnerBridge"
        self.media = root / "media"
        self.owner.mkdir()
        self.media.mkdir()
        manifest = self.owner / "p3-p4-policy.json"
        manifest.write_text(json.dumps({
            "schema": "TTV-P3-P4-OWNER-POLICY-V1", "enabled": True,
            "profile_id": "fixture", "torrserver_port": 8090,
            "private_media_root": str(self.media), "media": [],
        }))
        self.ts_reads = 0
        self.track_probe_calls = 0
        def transport(url, payload, timeout):
            self.ts_reads += 1
            selected_hash = json.loads(payload)["hash"]
            selected_path = ("Fixture/Second.Movie.2026.1080p.mkv"
                             if selected_hash == "b" * 40 else PATH)
            return json.dumps({"hash": selected_hash, "file_stats": [{
                "id": 2, "path": selected_path, "length": 1000}]}).encode()
        reader = OwnerTorrServerReader(
            OwnerLocalTorrServer("fixture", 8090), transport=transport)
        def track_probe(*_):
            self.track_probe_calls += 1
            return "UNKNOWN"
        self.policy = R0PrivateP3P4Policy(
            manifest=manifest, owner_root=self.owner, private_media_root=self.media,
            torrserver=reader, stream_probe=track_probe)
        cache = SignedRedmiStateCache(KEY)
        cache.receive(sign_synthetic_state(
            KEY, boot_id="1" * 32, sequence=1,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id="2" * 32,
            torrent_hash=HASH, file_index=2, active=True,
            subtitle_choice="REQUESTED", sent_at_ms=int(time.time() * 1000),
            nonce="3" * 32))
        self.current = OwnerCurrentRedmiReader(
            state_cache=cache, torrserver=reader,
            owner_auto_allowed=self.policy.owner_auto_allowed,
            media_rights_allowed=self.policy.media_rights_allowed,
            verified_local_vi_state=self.policy.verified_local_vi_state)
        self.current.bind_selected_file_inspector(self.policy.inspect_verified_file)

    def test_one_metadata_post_per_current_snapshot(self):
        state = self.current.read_playback()
        self.assertTrue(state.media_rights_approved)
        self.assertEqual(state.local_vi_state, "ABSENT")
        self.assertEqual(self.ts_reads, 1)
        self.current.read_v3()
        self.assertEqual(self.ts_reads, 2)
        self.assertEqual(self.track_probe_calls, 0)

    def test_switch_to_new_film_works_even_when_embedded_tracks_unavailable(self):
        # The previous code returned WAIT/CHECK_LOCAL_VI_TRACKS here because
        # the /ffp probe returned UNKNOWN for the newly selected torrent.
        from activation_gate import evaluate_playback
        state = self.current.read_playback()
        self.assertEqual(evaluate_playback(state).status, "DISPATCH")
        self.assertEqual(self.track_probe_calls, 0)

    def test_existing_vi_tracks_do_not_suppress_explicit_ai_request(self):
        from activation_gate import evaluate_playback
        self.policy._stream_probe = lambda *_: "PRESENT"
        state = self.current.read_playback()
        self.assertEqual(state.local_vi_state, "ABSENT")
        self.assertEqual(evaluate_playback(state).status, "DISPATCH")

    def test_a_to_b_new_signed_session_can_dispatch_while_a_stays_cached(self):
        from activation_gate import ActivationDeduplicator
        gate = ActivationDeduplicator()
        a = self.current.read_playback()
        self.assertEqual(gate.consider(a).status, "DISPATCH")
        self.current._cache.receive(sign_synthetic_state(
            KEY, boot_id="1" * 32, sequence=2,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id="4" * 32,
            torrent_hash="b" * 40, file_index=2, active=True,
            subtitle_choice="REQUESTED", sent_at_ms=int(time.time() * 1000),
            nonce="5" * 32))
        b = self.current.read_playback()
        self.assertEqual(b.video_name, "Second.Movie.2026.1080p.mkv")
        self.assertNotEqual(a.torrent_hash, b.torrent_hash)
        self.assertEqual(gate.consider(b).status, "DISPATCH")
        self.assertEqual(self.track_probe_calls, 0)

    def test_invalid_file_record_cannot_grant_rights(self):
        rights, vi = self.policy.inspect_verified_file(
            "fixture", HASH, 2,
            TorrServerSelectedFile(2, "Fixture/not-a-video.txt", 1000))
        self.assertEqual((rights, vi), (False, "UNKNOWN"))
