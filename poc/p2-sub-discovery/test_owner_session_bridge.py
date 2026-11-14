"""Owner-session bridge offline contract tests; no real Windows keys or APIs."""
import json
from pathlib import Path
import tempfile
import unittest

from owner_session_bridge import (
    enqueue_selected_media, poll_private_events, run_owner_agent,
    consume_inert_runner_wakes,
    _owner_process_lock,
)


class FakeProcessor:
    def __init__(self, *, status="VIETSUB_READY", fail=False):
        self.calls = []
        self.status = status
        self.fail = fail

    def selected_media(self, filename):
        self.calls.append(filename)
        if self.fail:
            raise RuntimeError("private API key: NEVER PRINT")
        return type("Result", (), {"status": self.status})()


class OwnerSessionBridgeTests(unittest.TestCase):
    def setUp(self):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        self.root = Path(root.name).resolve() / "owner-private"
        self.lines = []

    def test_trusted_event_one_processing_and_no_automatic_replay(self):
        event_id = enqueue_selected_media(
            "Synthetic.Film.2017.1080p.BluRay.x265-GRP",
            owner_root=self.root,
        )
        self.assertEqual(len(event_id), 32)
        processor = FakeProcessor()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 1)
        self.assertEqual(processor.calls, ["Synthetic.Film.2017.1080p.BluRay.x265-GRP"])
        self.assertTrue((self.root / "inbox" / ("event-" + event_id + ".done")).is_file())
        self.assertTrue((self.root / "inbox" / ("claim-" + event_id)).is_file())
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 0)
        self.assertEqual(len(processor.calls), 1)
        self.assertEqual(self.lines, ["OWNER_BRIDGE_EVENT_COMPLETE"])

    def test_provider_error_fails_closed_and_keeps_claim(self):
        event_id = enqueue_selected_media(
            "Synthetic.Film.2017.1080p.BluRay.x265-GRP", owner_root=self.root)
        processor = FakeProcessor(fail=True)
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 1)
        self.assertTrue((self.root / "inbox" / ("event-" + event_id + ".blocked")).is_file())
        self.assertTrue((self.root / "inbox" / ("claim-" + event_id)).is_file())
        self.assertEqual(len(processor.calls), 1)
        self.assertEqual(self.lines, ["OWNER_BRIDGE_EVENT_BLOCKED_NO_RETRY"])
        self.assertNotIn("private API key", " ".join(self.lines))

    def test_review_is_not_paid_retry(self):
        event_id = enqueue_selected_media(
            "Synthetic.Film.2017.1080p.BluRay.x265-GRP", owner_root=self.root)
        processor = FakeProcessor(status="REVIEW_REQUIRED")
        poll_private_events(owner_root=self.root, processor=processor, emit=self.lines.append)
        self.assertTrue((self.root / "inbox" / ("event-" + event_id + ".review")).is_file())
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 0)

    def test_malformed_or_symlinked_event_not_executed(self):
        folder = self.root / "inbox"
        folder.mkdir(parents=True)
        wrong = folder / ("event-" + "a"*32 + ".json")
        wrong.write_text(json.dumps({
            "schema": "TTV-OWNER-VIDEO-EVENT-V1",
            "event_id": "a"*32,
            "selected_video_filename": "../foreign-media",
        }))
        processor = FakeProcessor()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 0)
        self.assertEqual(processor.calls, [])
        self.assertIn("OWNER_BRIDGE_EVENT_REJECTED", self.lines)
        try:
            link = folder / ("event-" + "b"*32 + ".json")
            link.symlink_to(wrong)
        except (OSError, NotImplementedError):
            return
        poll_private_events(owner_root=self.root, processor=processor, emit=self.lines.append)
        self.assertIn("OWNER_BRIDGE_EVENT_REJECTED_SYMLINK", self.lines)

    def test_stale_inflight_claim_never_replays(self):
        event_id = enqueue_selected_media(
            "Synthetic.Film.2017.1080p.BluRay.x265-GRP", owner_root=self.root)
        (self.root / "inbox" / ("claim-" + event_id)).write_text("uncertain")
        processor = FakeProcessor()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor, emit=self.lines.append), 0)
        self.assertEqual(processor.calls, [])

    def test_enqueue_does_not_accept_path_or_command_input(self):
        for bad in ("../outside", "C:\\movie.mkv", "bad\nshell", "", "/tmp/video"):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, "BAD_VIDEO_NAME"):
                    enqueue_selected_media(bad, owner_root=self.root)

    def test_invalid_max_events_and_processor_refused(self):
        with self.assertRaisesRegex(ValueError, "BAD_PROCESSOR"):
            poll_private_events(owner_root=self.root, processor=object(), max_events=1)
        with self.assertRaisesRegex(ValueError, "BAD_PROCESSOR"):
            poll_private_events(owner_root=self.root, processor=FakeProcessor(),
                                max_events=100)

    def test_distinct_requests_are_processed_with_bounded_limit(self):
        for n in range(5):
            enqueue_selected_media(f"Synthetic.Film.2017.1080p.BluRay.x265-GRP{n}",
                                   owner_root=self.root)
        processor = FakeProcessor()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor,
            emit=self.lines.append, max_events=3), 3)
        self.assertEqual(len(processor.calls), 3)
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=processor,
            emit=self.lines.append, max_events=3), 2)

    def test_runner_wake_carries_no_film_or_command(self):
        # Runner may create WAKE_V1, but owner executes ONLY private events.
        wake = self.root / "public-wake"
        wake.mkdir(parents=True)
        (wake / ("wake-" + "a"*32 + ".txt")).write_bytes(b"WAKE_V1\n")
        (wake / ("wake-" + "b"*32 + ".txt")).write_bytes(b"python evil.py")
        (wake / ("wake-" + "c"*32 + ".txt")).write_bytes(b"WAKE_V1\n")
        self.assertEqual(consume_inert_runner_wakes(shared_wake_root=wake), 2)
        self.assertEqual(len(list(wake.glob("wake-*.txt"))), 1)
        self.assertEqual(consume_inert_runner_wakes(shared_wake_root=wake), 0)
        self.assertFalse((self.root / "inbox").exists())

    def test_symlinked_wake_folder_refused(self):
        outside = self.root / "elsewhere"
        outside.mkdir(parents=True)
        link = self.root / "wake-link"
        try:
            link.symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            return
        self.assertEqual(consume_inert_runner_wakes(shared_wake_root=link), 0)

    def test_bound_event_passes_media_fingerprint_no_name_only_cache(self):
        target = "e" * 64
        event_id = enqueue_selected_media(
            "Synthetic.Film.2017.1080p.BluRay.x265-GRP",
            owner_root=self.root, source_fingerprint=target)
        body = json.loads((self.root / "inbox" /
            ("event-" + event_id + ".json")).read_text())
        self.assertEqual(body["schema"], "TTV-OWNER-VIDEO-EVENT-V2")
        self.assertEqual(body["source_fingerprint"], target)

        class BoundFake:
            def __init__(self):
                self.calls = []
            def selected_media(self, name, *, source_fingerprint):
                self.calls.append((name, source_fingerprint))
                return type("Result", (), {"status": "VIETSUB_READY"})()

        worker = BoundFake()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=worker, emit=self.lines.append), 1)
        self.assertEqual(len(worker.calls), 1)
        self.assertEqual(worker.calls[0][1], target)

    def test_bound_event_invalid_fingerprint_never_processed(self):
        for bad in ("A"*64, "abc", "../bad", "", 123):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, "SOURCE_FINGERPRINT_INVALID"):
                    enqueue_selected_media(
                        "Synthetic.Film.2017.1080p.BluRay.x265-GRP",
                        owner_root=self.root, source_fingerprint=bad)
        self.assertFalse((self.root / "inbox").exists())
        folder = self.root / "inbox"
        folder.mkdir(parents=True)
        bad_id = "a" * 32
        (folder / ("event-" + bad_id + ".json")).write_text(json.dumps({
            "schema": "TTV-OWNER-VIDEO-EVENT-V2",
            "event_id": bad_id,
            "selected_video_filename": "Synthetic.Film.2017.1080p.BluRay.x265-GRP",
            "source_fingerprint": "NOT-SHA",
        }))
        class Probe:
            calls = []
            def selected_media(self, name, *, source_fingerprint):
                self.calls.append(name)
        worker = Probe()
        self.assertEqual(poll_private_events(
            owner_root=self.root, processor=worker, emit=self.lines.append), 0)
        self.assertEqual(worker.calls, [])

    def test_owner_lock_exclusive_but_released_on_exit(self):
        with _owner_process_lock(self.root):
            with self.assertRaisesRegex(ValueError, "ALREADY_RUNNING"):
                with _owner_process_lock(self.root):
                    pass
        # Exiting/crashing the *process lock* does not require a human to
        # manually delete the file; provider claims are handled separately.
        self.assertTrue((self.root / "owner-agent-active.lock").is_file())
        with _owner_process_lock(self.root):
            self.assertTrue((self.root / "owner-agent-active.lock").exists())

    def test_old_stale_pid_marker_is_not_permanent_lock(self):
        self.root.mkdir(parents=True)
        (self.root / "owner-agent-active.lock").write_bytes(b"123456")
        with _owner_process_lock(self.root):
            pass

    def test_owner_process_body_failure_does_not_fake_lock_conflict(self):
        with self.assertRaisesRegex(OSError, "synthetic"):
            with _owner_process_lock(self.root):
                raise OSError("synthetic")
        with _owner_process_lock(self.root):
            pass

    def test_no_live_background_agent_in_ci(self):
        import os
        from unittest import mock
        with mock.patch.dict(os.environ, {"CI": "true"}):
            with self.assertRaisesRegex(ValueError, "NO_OWNER_RUNTIME_IN_CI"):
                run_owner_agent(private_root=self.root,
                                cache_root=self.root / "cache",
                                state_root=self.root / "state")


if __name__ == "__main__":
    unittest.main()
