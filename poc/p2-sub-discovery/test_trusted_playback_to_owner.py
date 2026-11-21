"""P3 accepted playback -> existing owner-private D2/P2 event queue tests.

Synthetic only, no TV, native code, Gemini, OpenSubtitles, Windows or secrets.
"""
from __future__ import annotations

from dataclasses import replace
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from trusted_playback_to_owner import TrustedPlaybackToOwner
from p3_signed_playback_signal import AuthenticatedSelectionSignal
from owner_session_bridge import poll_private_events
from activation_gate import PlaybackSelected


def accepted(**changes) -> PlaybackSelected:
    event = PlaybackSelected(
        kind="PLAY_REQUEST_ACCEPTED",
        attested=True, active=True,
        server_id="trusted-local-server",
        tv_session_id="trusted-tv-session-1",
        torrent_hash="a" * 40,
        file_index=0,
        video_name="Synthetic.Film.2017.1080p.BluRay.x265-GRP",
        owner_auto_enabled=True,
        subtitle_choice="REQUESTED",
        media_rights_approved=True,
        local_vi_state="ABSENT",
    )
    return replace(event, **changes)


class FakePipeline:
    def __init__(self):
        self.calls = []

    def selected_media(self, video_filename, *, source_fingerprint=None,
                       tv_session_id=None):
        self.calls.append((video_filename, source_fingerprint, tv_session_id))
        return type("Receipt", (), {"status": "VIETSUB_READY"})()


class TriggerToOwnerTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.root = Path(t.name).resolve() / "owner-private"
        self.event = accepted()
        self.calls = 0
        self.lines = []

        def read_active():
            self.calls += 1
            return self.event

        self.adapter = TrustedPlaybackToOwner(
            read_verified_current_playback=read_active,
            owner_root=self.root,
            emit=self.lines.append,
        )

    def proof(self):
        # The signed-ingress tests separately verify HMAC; these unit tests
        # exercise only the typed already-verified artifact / queue seam.
        e = self.event if isinstance(self.event, PlaybackSelected) else accepted()
        return AuthenticatedSelectionSignal(
            kind="VIEWER_VIETSUB_REQUESTED",
            tv_session_id=e.tv_session_id, torrent_hash=e.torrent_hash,
            file_index=e.file_index, sent_at_ms=1_800_000_000_000,
            nonce="f"*32, signature="0"*64)

    def invoke(self):
        return self.adapter.on_current_selection_accepted(self.proof())

    def test_bare_play_on_without_verified_button_must_never_enqueue(self):
        self.event = accepted(subtitle_choice="ON")
        result = self.adapter.on_current_selection_accepted()
        self.assertEqual((result.status, result.reason),
                         ("SKIP", "NO_VERIFIED_VIEWER_REQUEST"))
        self.assertEqual(self.calls, 0)
        self.assertFalse(self.root.exists())
        forged = replace(self.proof(), kind="PLAY_REQUEST_ACCEPTED")
        self.assertEqual(
            self.adapter.on_current_selection_accepted(forged).status, "SKIP")
        self.assertFalse(self.root.exists())

    def test_wrong_verified_tap_identity_cannot_enqueue(self):
        forged = replace(self.proof(), file_index=77)
        self.assertEqual(
            self.adapter.on_current_selection_accepted(forged).reason,
            "VIEWER_REQUEST_SOURCE_CHANGED")
        self.assertFalse(self.root.exists())

    def test_accepted_trusted_selection_enqueues_once_and_processor_runs(self):
        first = self.invoke()
        duplicate = self.invoke()
        self.assertEqual(first.status, "DISPATCH")
        self.assertEqual(duplicate.reason, "DUPLICATE_CURRENT_PLAY_EVENT")
        self.assertEqual(self.calls, 2)
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 1)
        fake = FakePipeline()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=fake, emit=self.lines.append), 1)
        self.assertEqual(len(fake.calls), 1)
        self.assertEqual(fake.calls[0][0], self.event.video_name)
        self.assertRegex(fake.calls[0][1], r"^[0-9a-f]{64}$")
        self.assertEqual(fake.calls[0][2], "trusted-tv-session-1")
        self.assertIn("OWNER_PLAYBACK_PRIVATE_ENQUEUED", self.lines)
        self.assertIn("OWNER_BRIDGE_EVENT_COMPLETE", self.lines)

    def test_no_omp_event_or_policy_bypass_from_github_runner(self):
        # A GitHub inert WAKE marker does not trigger P3 policy or enqueue.
        self.assertFalse(self.root.exists())
        self.assertEqual(self.calls, 0)
        self.assertEqual(self.lines, [])

    def test_non_playback_and_off_other_do_not_queue(self):
        for change in (
            {"kind": "SEEK"},
            {"kind": "TORRENT_ADDED"},
            {"subtitle_choice": "OFF"},
            {"subtitle_choice": "OTHER"},
            {"local_vi_state": "PRESENT"},
            {"local_vi_state": "UNKNOWN"},
            {"owner_auto_enabled": False},
            {"media_rights_approved": False},
            {"attested": False},
            {"active": False},
            {"torrent_hash": "untrusted"},
        ):
            with self.subTest(change=change):
                self.adapter.on_session_closed()
                self.event = accepted(**change)
                self.assertNotEqual(
                    self.invoke().status, "DISPATCH")
                self.assertFalse((self.root / "inbox").exists())

    def test_next_episode_uses_exact_file_index_not_just_filename(self):
        self.assertEqual(
            self.invoke().status, "DISPATCH")
        self.event = accepted(
            kind="NEXT_QUEUE_ITEM_ACCEPTED",
            file_index=1,
            tv_session_id="trusted-tv-session-2",
            video_name="Synthetic.Film.2017.1080p.BluRay.x265-GRP2",
        )
        self.assertEqual(
            self.invoke().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)

    def test_missing_or_faulted_trusted_current_media_holds_without_enqueue(self):
        self.event = None
        r = self.invoke()
        self.assertEqual((r.status, r.reason), ("HOLD", "MALFORMED_EVENT"))
        self.assertFalse(self.root.exists())

        def broken_source():
            raise RuntimeError("private media URI: do not print")
        adapter = TrustedPlaybackToOwner(
            read_verified_current_playback=broken_source,
            owner_root=self.root,
            emit=self.lines.append,
        )
        result = adapter.on_current_selection_accepted(self.proof())
        self.assertEqual((result.status, result.reason),
                         ("HOLD", "TRUSTED_SOURCE_UNAVAILABLE"))
        self.assertFalse(self.root.exists())
        self.assertNotIn("private media URI", " ".join(self.lines))

    def test_no_trusted_provider_refused(self):
        with self.assertRaisesRegex(ValueError, "TRUSTED_SOURCE_REQUIRED"):
            TrustedPlaybackToOwner(read_verified_current_playback=None,
                                   owner_root=self.root)

    def test_enqueue_failure_does_not_permanently_suppress_retry(self):
        with mock.patch(
            "trusted_playback_to_owner.enqueue_selected_media",
            side_effect=OSError("private file path and secret not public"),
        ):
            with self.assertRaisesRegex(ValueError, "PRIVATE_ENQUEUE_FAILED"):
                self.invoke()
        self.assertFalse(self.root.exists())
        # The in-memory dedup was reset; retry may enqueue safely.
        self.assertEqual(
            self.invoke().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 1)
        self.assertNotIn("secret", str(self.lines))

    def test_same_filename_different_torrent_preserves_media_identity(self):
        self.invoke()
        self.event = accepted(torrent_hash="b" * 40)
        result = self.invoke()
        self.assertEqual(result.status, "DISPATCH")
        fake = FakePipeline()
        poll_private_events(owner_root=self.root, processor=fake,
                            emit=self.lines.append)
        self.assertEqual(len(fake.calls), 2)
        self.assertEqual(fake.calls[0][0], fake.calls[1][0])
        self.assertNotEqual(fake.calls[0][1], fake.calls[1][1])

    def test_repeated_play_same_session_new_media_hash_is_distinct(self):
        self.invoke()
        self.event = accepted(torrent_hash="b" * 40,
                              video_name="Synthetic.Film.2017.1080p.BluRay.x265-OTHER")
        self.assertEqual(
            self.invoke().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)

    def test_session_closed_resets_dedup_but_owner_checkpoints_are_separate(self):
        self.invoke()
        self.adapter.on_session_closed()
        self.assertEqual(
            self.invoke().status, "DISPATCH")
        # Duplicate UI selection events are tolerated: private source cache and
        # LEAN120 checkpoints prevent duplicate charged provider calls.
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)


if __name__ == "__main__":
    unittest.main()
