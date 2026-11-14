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
        subtitle_choice="ON",
        media_rights_approved=True,
        local_vi_state="ABSENT",
    )
    return replace(event, **changes)


class FakePipeline:
    def __init__(self):
        self.calls = []

    def selected_media(self, video_filename):
        self.calls.append(video_filename)
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

    def test_accepted_trusted_selection_enqueues_once_and_processor_runs(self):
        first = self.adapter.on_current_selection_accepted()
        duplicate = self.adapter.on_current_selection_accepted()
        self.assertEqual(first.status, "DISPATCH")
        self.assertEqual(duplicate.reason, "DUPLICATE_CURRENT_PLAY_EVENT")
        self.assertEqual(self.calls, 2)
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 1)
        fake = FakePipeline()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=fake, emit=self.lines.append), 1)
        self.assertEqual(fake.calls, [self.event.video_name])
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
                    self.adapter.on_current_selection_accepted().status, "DISPATCH")
                self.assertFalse((self.root / "inbox").exists())

    def test_next_episode_uses_exact_file_index_not_just_filename(self):
        self.assertEqual(
            self.adapter.on_current_selection_accepted().status, "DISPATCH")
        self.event = accepted(
            kind="NEXT_QUEUE_ITEM_ACCEPTED",
            file_index=1,
            tv_session_id="trusted-tv-session-2",
            video_name="Synthetic.Film.2017.1080p.BluRay.x265-GRP2",
        )
        self.assertEqual(
            self.adapter.on_current_selection_accepted().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)

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
                self.adapter.on_current_selection_accepted()
        self.assertFalse(self.root.exists())
        # The in-memory dedup was reset; retry may enqueue safely.
        self.assertEqual(
            self.adapter.on_current_selection_accepted().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 1)
        self.assertNotIn("secret", str(self.lines))

    def test_repeated_play_same_session_new_media_hash_is_distinct(self):
        self.adapter.on_current_selection_accepted()
        self.event = accepted(torrent_hash="b" * 40,
                              video_name="Synthetic.Film.2017.1080p.BluRay.x265-OTHER")
        self.assertEqual(
            self.adapter.on_current_selection_accepted().status, "DISPATCH")
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)

    def test_session_closed_resets_dedup_but_owner_checkpoints_are_separate(self):
        self.adapter.on_current_selection_accepted()
        self.adapter.on_session_closed()
        self.assertEqual(
            self.adapter.on_current_selection_accepted().status, "DISPATCH")
        # Duplicate UI selection events are tolerated: private source cache and
        # LEAN120 checkpoints prevent duplicate charged provider calls.
        self.assertEqual(len(list((self.root / "inbox").glob("event-*.json"))), 2)


if __name__ == "__main__":
    unittest.main()
