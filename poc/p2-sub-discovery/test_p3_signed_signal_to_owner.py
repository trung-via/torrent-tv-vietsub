"""Synthetic HMAC signal -> existing P3 V3 private owner inbox tests."""
from __future__ import annotations

from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest

from activation_gate import PlaybackSelected
from p3_signed_playback_signal import SignedPlaybackVerifier, sign_synthetic_event
from p3_signed_signal_to_owner import SignedP3ToOwner
from owner_session_bridge import _parse_event


KEY = bytes(range(32))
WHEN = 1_800_000_000_000
SESSION = "a" * 32
TORRENT = "b" * 40
NAME = "Synthetic.Movie.2017.1080p.BluRay.x265-GRP.mkv"


def wire(**updates):
    data = dict(kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
                torrent_hash=TORRENT, file_index=2,
                sent_at_ms=WHEN, nonce="c" * 32)
    data.update(updates)
    return sign_synthetic_event(KEY, **data)


def snapshot(**updates):
    e = PlaybackSelected(
        kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
        server_id="owner-windows-server",
        tv_session_id=SESSION, torrent_hash=TORRENT,
        file_index=2, video_name=NAME,
        owner_auto_enabled=True, subtitle_choice="ON",
        media_rights_approved=True, local_vi_state="ABSENT")
    return replace(e, **updates)


class SignedIngressTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve() / "private-owner"
        self.state = snapshot()
        self.read_count = 0
        self.lines = []
        def read():
            self.read_count += 1
            return self.state
        self.adapter = SignedP3ToOwner(
            verifier=SignedPlaybackVerifier(KEY),
            owner_root=self.root,
            read_verified_current_selection=read,
            emit=self.lines.append)

    def inbox(self):
        return list((self.root / "inbox").glob("event-*.json"))

    def test_signed_current_play_enqueues_one_v3_owner_event(self):
        result = self.adapter.on_wire(wire(), now_ms=WHEN)
        self.assertEqual(result.status, "DISPATCH")
        self.assertEqual(self.read_count, 2)
        msg, = self.inbox()
        parsed = _parse_event(msg)
        self.assertEqual(parsed.tv_session_id, SESSION)
        self.assertEqual(parsed.selected_video_filename, NAME)
        self.assertEqual(parsed.source_fingerprint, result.local_fingerprint)
        # Signed TV packet never carries title, IP or server id. Windows
        # trusted metadata resolver supplies the exact filename on its own.
        self.assertNotIn(NAME, wire().decode())
        self.assertNotIn("owner-windows", wire().decode())

    def test_duplicate_replay_not_enqueued(self):
        self.assertEqual(self.adapter.on_wire(wire(), now_ms=WHEN).status, "DISPATCH")
        self.assertEqual(self.adapter.on_wire(wire(), now_ms=WHEN).status, "HOLD")
        self.assertEqual(len(self.inbox()), 1)

    def test_tampered_or_wrong_key_packet_never_reads_owner_sources(self):
        req = json.loads(wire())
        req["file_index"] = 3
        result = self.adapter.on_wire(json.dumps(req).encode(), now_ms=WHEN)
        self.assertEqual(result.reason, "SIGNED_TV_MESSAGE_INVALID")
        self.assertEqual(self.read_count, 0)
        self.assertFalse(self.root.exists())

    def test_signed_but_stale_tv_session_must_not_enqueue(self):
        self.state = snapshot(tv_session_id="d" * 32)
        result = self.adapter.on_wire(wire(), now_ms=WHEN)
        self.assertEqual(result.reason, "TV_SIGNAL_CURRENT_SELECTION_MISMATCH")
        self.assertEqual(self.inbox(), [])

    def test_signed_wrong_file_index_must_not_enqueue(self):
        self.state = snapshot(file_index=7)
        result = self.adapter.on_wire(wire(), now_ms=WHEN)
        self.assertEqual(result.reason, "TV_SIGNAL_CURRENT_SELECTION_MISMATCH")
        self.assertEqual(self.inbox(), [])

    def test_signed_wrong_torrent_hash_must_not_enqueue(self):
        self.state = snapshot(torrent_hash="f" * 40)
        result = self.adapter.on_wire(wire(), now_ms=WHEN)
        self.assertEqual(result.reason, "TV_SIGNAL_CURRENT_SELECTION_MISMATCH")
        self.assertEqual(self.inbox(), [])

    def test_viewer_off_other_or_vi_present_prevents_provider(self):
        for data in ({"subtitle_choice": "OFF"}, {"subtitle_choice": "OTHER"},
                     {"owner_auto_enabled": False}, {"local_vi_state": "PRESENT"},
                     {"media_rights_approved": False}):
            with self.subTest(data=data):
                self.adapter.on_session_closed()
                self.state = snapshot(**data)
                req = wire(nonce=(str(len(self.lines) % 10) * 32))
                status = self.adapter.on_wire(req, now_ms=WHEN)
                self.assertNotEqual(status.status, "DISPATCH")
                self.assertFalse(self.root.exists())

    def test_close_signal_stops_inmemory_session_without_enqueue(self):
        closed = self.adapter.on_wire(
            wire(kind="PLAYBACK_CLOSED"), now_ms=WHEN)
        self.assertEqual((closed.status, closed.reason),
                         ("SKIP", "TV_PLAYBACK_CLOSED"))
        self.assertEqual(self.read_count, 0)
        self.assertFalse(self.root.exists())

    def test_new_session_new_nonce_can_enqueue_again(self):
        self.assertEqual(self.adapter.on_wire(wire(), now_ms=WHEN).status, "DISPATCH")
        self.state = snapshot(tv_session_id="d" * 32)
        result = self.adapter.on_wire(
            wire(tv_session_id="d" * 32, sent_at_ms=WHEN + 300,
                 nonce="e" * 32), now_ms=WHEN + 300)
        self.assertEqual(result.status, "DISPATCH")
        self.assertEqual(len(self.inbox()), 2)


if __name__ == "__main__":
    unittest.main()
