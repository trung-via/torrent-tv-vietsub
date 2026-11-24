"""Offline-only acceptance for automatic, resumable LEAN120 EN -> VI -> P4.

All source lines and model responses are synthetic; NEVER contact Gemini,
OpenSubtitles, the TV, a LAN socket or a real user file during CI.
"""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import subprocess
from threading import Barrier, Event, Lock

from automatic_lean120_worker import AutomaticLean120Worker
from assumed_source_handoff import AssumedEnglishSubtitle
from cue_pipeline import parse_cues
from lan_revision_feed import SessionRevisionFeed
from lean120_api import ModelProfile

MEDIA = "media." + "a" * 64
OTHER = "media." + "b" * 64
PROFILE = ModelProfile("antigravity", "gemini-4-hydrogen-high", "high")


def source_srt(n: int) -> bytes:
    lines = []
    for i in range(1, n + 1):
        sec = i - 1
        hours, rem = divmod(sec, 3600)
        mins, seconds = divmod(rem, 60)
        a = f"{hours:02d}:{mins:02d}:{seconds:02d}"
        lines.append(
            f"{i}\n{a},000 --> {a},900\nSynthetic English cue {i}\n"
        )
    return ("\n".join(lines) + "\n").encode("utf-8")


def handoff(n: int = 242, media: str = MEDIA) -> AssumedEnglishSubtitle:
    return AssumedEnglishSubtitle.from_supplied(
        media_key=media, fmt="srt", source_bytes=source_srt(n)
    )


def fake_response(ids) -> dict:
    return {
        "candidates": [{
            "finishReason": "STOP",
            "content": {"parts": [{
                "text": json.dumps({"translations": [
                    {"id": i, "vi": f"Phụ đề kiểm thử {i}"} for i in ids
                ]}, ensure_ascii=False)
            }]}
        }]
    }


class FakeAntigravity:
    def __init__(self):
        self.calls = []
        self.fail_on = None

    def __call__(self, cmd, **kwargs):
        assert "--sandbox" in cmd
        assert "GEMINI_API_KEY" not in kwargs["env"]
        prompt = json.loads(kwargs["input"].strip())["message"]["content"]
        ids = [x["id"] for x in json.loads(prompt.split("\n", 1)[1])["target"]]
        self.calls.append(tuple(ids))
        if self.fail_on == len(self.calls):
            raise ValueError("AGY_PROCESS_FAILED_RESULT_UNKNOWN")
        event = {"event": "result", "result": {"status": "SUCCESS",
            "structured_output": {"translations": [
                {"id": i, "vi": f"Phụ đề kiểm thử {i}"} for i in ids]}}}
        return subprocess.CompletedProcess(cmd, 0, json.dumps(event), "")


class AutoLean120WorkerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "private-state"
        self.provider = FakeAntigravity()

    def worker(self, **kwargs):
        return AutomaticLean120Worker(
            state_root=kwargs.pop("state_root", self.root),
            profile=kwargs.pop("profile", PROFILE),
            glossary=kwargs.pop("glossary", {"Fictional": "Hư cấu"}),
            runner=kwargs.pop("runner", self.provider),
            first_window_cues=kwargs.pop("first_window_cues", None),
            parallel_batches=kwargs.pop("parallel_batches", 1),
            preserve_hydrogen_jobs=kwargs.pop("preserve_hydrogen_jobs", False),
        )

    def folders(self):
        return list(self.root.iterdir())

    def test_first_50_then_120_cumulative_and_reopen_without_duplicate_model(self):
        source = handoff(245)
        worker = self.worker(first_window_cues=50)
        first = worker.run(source, max_new_windows=1)
        self.assertEqual((first.translated_count, first.complete), (50, False))
        self.assertEqual([len(ids) for ids in self.provider.calls], [50])
        seen = []
        final = self.worker(first_window_cues=50).run(
            source, on_revision=seen.append)
        self.assertEqual([r.translated_count for r in seen], [50, 170, 245])
        self.assertTrue(final.complete)
        self.assertEqual([len(ids) for ids in self.provider.calls], [50, 120, 75])
        self.worker(first_window_cues=50).run(source)
        self.assertEqual([len(ids) for ids in self.provider.calls], [50, 120, 75])
        self.assertEqual(len(self.folders()), 1)

    def test_prior_120_cue_checkpoint_resumes_with_no_duplicate_paid_batch(self):
        source = handoff(245)
        legacy = self.worker().run(source, max_new_windows=1)
        self.assertEqual(legacy.translated_count, 120)
        next_worker = self.worker(first_window_cues=50)
        resumed = []
        final = next_worker.run(source, on_revision=resumed.append)
        self.assertEqual([r.translated_count for r in resumed], [120, 240, 245])
        self.assertTrue(final.complete)
        self.assertEqual([len(ids) for ids in self.provider.calls], [120, 120, 5])
        self.assertEqual(len(self.folders()), 1)

    def test_prior_uncertain_batch_holds_before_any_new_model_invocation(self):
        from automatic_lean120_worker import _job_fingerprint
        source = handoff(245)
        worker = self.worker(first_window_cues=50)
        folder = self.root / _job_fingerprint(source, PROFILE, worker.glossary)
        folder.mkdir(parents=True)
        (folder / "batch-0001.inflight").write_text("synthetic unknown")
        with self.assertRaisesRegex(ValueError, "WINDOW_PLAN_UNCERTAIN"):
            worker.run(source)
        self.assertFalse(self.provider.calls)
        self.assertTrue((folder / "batch-0001.inflight").exists())

    def test_first_window_pilot_never_translates_second_window_on_rerun(self):
        source = handoff(242)
        first = self.worker().run(source, max_new_windows=1)
        self.assertFalse(first.complete)
        self.assertEqual(first.translated_count, 120)
        self.assertEqual(first.total_count, 242)
        self.assertEqual([len(ids) for ids in self.provider.calls], [120])
        folder = self.folders()[0]
        self.assertTrue((folder / "batch-0001.json").is_file())
        self.assertFalse((folder / "batch-0002.inflight").exists())
        self.assertFalse((folder / "batch-0002.json").exists())
        self.assertFalse((folder / "vi-final.srt").exists())
        self.assertFalse((folder / "active.lock").exists())

        # Rerunning the PILOT may replay batch 1; it must NOT issue a new
        # billable call for batch 2 (otherwise a forgotten flag is risky).
        replay = self.worker().run(source, max_new_windows=1)
        self.assertFalse(replay.complete)
        self.assertEqual(replay.sha256, first.sha256)
        self.assertEqual(len(self.provider.calls), 1)

        # A separate explicit full-film workflow can reuse the checkpoint.
        full = self.worker().run(source)
        self.assertTrue(full.complete)
        self.assertEqual([len(x) for x in self.provider.calls], [120, 120, 2])
        self.assertTrue((folder / "vi-final.srt").is_file())

    def test_one_window_source_still_produces_complete_file(self):
        source = handoff(50)
        final = self.worker().run(source, max_new_windows=1)
        self.assertTrue(final.complete)
        self.assertEqual(final.translated_count, 50)
        self.assertEqual([len(x) for x in self.provider.calls], [50])
        self.assertTrue((self.folders()[0] / "vi-final.srt").exists())

    def test_pilot_window_limit_invalid_before_disk_and_provider(self):
        source = handoff(242)
        for invalid in (0, 2, True, "1", -1):
            with self.subTest(invalid=invalid):
                with self.assertRaisesRegex(ValueError, "PILOT_WINDOW_LIMIT_INVALID"):
                    self.worker().run(source, max_new_windows=invalid)
        self.assertEqual(self.provider.calls, [])
        self.assertFalse(self.root.exists())

    def test_automatic_120_240_242_private_final_vietsub_and_p4_feed(self):
        source = handoff(242)
        feed = SessionRevisionFeed(
            session_id="SyntheticSession0123456789", media_key=MEDIA,
            source_sha256=source.source_sha256, pairing_secret=b"a" * 32,
        )
        emitted = []
        def publish(revision):
            emitted.append(revision)
            return feed.publish(revision)
        final = self.worker().run(source, on_revision=publish)
        self.assertEqual([r.translated_count for r in emitted], [120, 240, 242])
        self.assertEqual([r.version for r in emitted], [1, 2, 3])
        self.assertTrue(final.complete)
        self.assertEqual(len(self.provider.calls), 3)
        self.assertEqual(len(self.provider.calls[0]), 120)
        self.assertEqual(self.provider.calls[1][0], 121)
        original = parse_cues(source.source_bytes, "srt")
        translated = parse_cues(final.payload, "srt")
        self.assertEqual([c.number for c in original], [c.number for c in translated])
        self.assertEqual([(c.start_ms, c.end_ms) for c in original],
                         [(c.start_ms, c.end_ms) for c in translated])
        self.assertEqual(translated[130].text, "Phụ đề kiểm thử 131")
        self.assertEqual(json.loads(feed.latest())["translated_count"], 242)
        self.assertEqual(len(self.folders()), 1)
        saved = self.folders()[0] / "vi-final.srt"
        self.assertEqual(saved.read_bytes(), final.payload)
        self.assertFalse((self.folders()[0] / "active.lock").exists())
        for f in self.folders()[0].glob("*.json"):
            self.assertNotIn("fake-test-key", f.read_text(encoding="utf-8"))
            self.assertNotIn(MEDIA, f.name)
        self.assertFalse(list(self.folders()[0].glob("*.inflight")))

    def test_reuse_completed_batch_never_calls_provider_again(self):
        source = handoff(241)
        self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 3)
        emit = []
        final = self.worker().run(source, on_revision=emit.append)
        self.assertTrue(final.complete)
        self.assertEqual([r.translated_count for r in emit], [120, 240, 241])
        self.assertEqual(len(self.provider.calls), 3)

    def test_another_film_inflight_does_not_block_independent_job(self):
        """A uncertain batch only blocks A, not an authorized film B."""
        from automatic_lean120_worker import _job_fingerprint
        source_a = handoff(120, media=MEDIA)
        source_b = handoff(121, media=OTHER)
        worker = self.worker()
        key_a = _job_fingerprint(source_a, PROFILE, worker.glossary)
        a_folder = self.root / key_a
        a_folder.mkdir(parents=True)
        (a_folder / "batch-0001.inflight").write_text("synthetic uncertain")
        finished_b = worker.run(source_b)
        self.assertTrue(finished_b.complete)
        self.assertEqual(finished_b.translated_count, 121)
        self.assertTrue((a_folder / "batch-0001.inflight").exists())
        with self.assertRaisesRegex(ValueError, "UNCERTAIN_BATCH_MANUAL_RECONCILE"):
            worker.run(source_a)

    def test_interruption_stops_unknown_provider_effects_no_auto_retry(self):
        source = handoff(241)
        self.provider.fail_on = 2
        emitted = []
        with self.assertRaisesRegex(ValueError, "AGY_PROCESS_FAILED_RESULT_UNKNOWN"):
            self.worker().run(source, on_revision=emitted.append)
        self.assertEqual([r.translated_count for r in emitted], [120])
        self.assertEqual(len(self.provider.calls), 2)
        job = self.folders()[0]
        self.assertTrue((job / "batch-0001.json").is_file())
        self.assertTrue((job / "batch-0002.inflight").is_file())
        self.assertFalse((job / "batch-0002.json").exists())
        self.assertFalse((job / "vi-final.srt").exists())
        with self.assertRaisesRegex(ValueError, "UNCERTAIN_BATCH_MANUAL_RECONCILE"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 2)

    def test_acknowledged_unknown_effect_never_replays_original_job(self):
        source = handoff(1)
        self.provider.fail_on = 1
        with self.assertRaisesRegex(ValueError, "AGY_PROCESS_FAILED_RESULT_UNKNOWN"):
            self.worker().run(source)
        job = self.folders()[0]
        marker = job / "batch-0001.inflight"
        self.assertTrue(marker.is_file())
        # The offline owner tool creates the durable no-retry ledger first,
        # then preserves the marker bytes under a non-inflight extension.
        (job / "batch-0001.abandoned.json").write_text(
            '{"result":"UNKNOWN_EFFECT_NO_RETRY"}', encoding="utf-8")
        # Film B is independent: an uncertain A must never freeze B.
        self.provider.fail_on = None
        different = self.worker().run(handoff(1, OTHER))
        self.assertTrue(different.complete)
        self.assertEqual(len(self.provider.calls), 2)
        marker.rename(job / "batch-0001.quarantined")
        with self.assertRaisesRegex(ValueError, "AUTO_LEAN120_ABANDONED_JOB_HOLD"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 2)
        self.assertTrue((job / "batch-0001.quarantined").exists())
        self.assertFalse((job / "active.lock").exists())
        # Reopening B reuses B's own finished checkpoints, not A's claim.
        different = self.worker().run(handoff(1, OTHER))
        self.assertTrue(different.complete)
        self.assertEqual(len(self.provider.calls), 2)
        different_profile = self.worker(profile=ModelProfile(
            "antigravity", "gemini-4-hydrogen-low", "low")).run(source)
        self.assertTrue(different_profile.complete)
        self.assertEqual(len(self.provider.calls), 3)

    def test_explicit_private_job_archive_allows_new_request_from_window_one(self):
        """A new consented request must not reuse checkpoints from a failed job.

        The Owner-only offline operation moves the *whole* job outside the
        active state tree. This fake-provider test exercises the resulting
        library semantics, not the Windows task/TV/provider deployment.
        """
        source = handoff(241)
        self.provider.fail_on = 2
        with self.assertRaisesRegex(ValueError, "AGY_PROCESS_FAILED_RESULT_UNKNOWN"):
            self.worker().run(source)
        self.assertEqual([len(x) for x in self.provider.calls], [120, 120])
        old_job = self.folders()[0]
        # A regular caught exception removes the lock in finally; emulate
        # abrupt process interruption, which can leave this extra lock.
        self.assertFalse((old_job / "active.lock").exists())
        (old_job / "active.lock").write_bytes(b"TTV-P2-LOCK-V1\n")
        self.assertTrue((old_job / "active.lock").exists())
        self.assertTrue((old_job / "batch-0001.json").exists())
        self.assertTrue((old_job / "batch-0002.inflight").exists())

        private_recovery = self.root.parent / "recovery"
        private_recovery.mkdir()
        archived = private_recovery / "previous-unknown-effect-job"
        old_job.rename(archived)
        self.assertFalse(self.folders())
        self.assertTrue((archived / "batch-0001.json").exists())
        self.assertTrue((archived / "batch-0002.inflight").exists())

        # Only a separately initiated call to run() starts a new paid job;
        # there is no automatic retry just because the old state was moved.
        self.provider = FakeAntigravity()
        final = self.worker().run(source)
        self.assertTrue(final.complete)
        self.assertEqual([len(x) for x in self.provider.calls], [120, 120, 1])
        self.assertEqual(len(self.folders()), 1)
        self.assertNotEqual(self.folders()[0], archived)
        self.assertTrue((archived / "active.lock").exists())

    def test_abandonment_tombstone_alone_fails_closed(self):
        source = handoff(1)
        self.worker().run(source)
        job = self.folders()[0]
        (job / "batch-0001.abandoned.json").write_text(
            "partially written ledger", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "AUTO_LEAN120_ABANDONED_JOB_HOLD"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 1)

    def test_checkpoint_then_publish_failure_is_replayed_without_api(self):
        source = handoff(125)
        def crashed(_):
            raise ValueError("P4_SUBSCRIBER_DISCONNECTED")
        with self.assertRaisesRegex(ValueError, "P4_SUBSCRIBER_DISCONNECTED"):
            self.worker().run(source, on_revision=crashed)
        self.assertEqual(len(self.provider.calls), 1)
        job = self.folders()[0]
        self.assertTrue((job / "batch-0001.json").is_file())
        got = []
        final = self.worker().run(source, on_revision=got.append)
        self.assertTrue(final.complete)
        self.assertEqual([x.translated_count for x in got], [120, 125])
        self.assertEqual(len(self.provider.calls), 2)

    def test_committed_checkpoint_with_old_inflight_marker_is_recoverable(self):
        source = handoff(122)
        self.worker().run(source)
        job = self.folders()[0]
        marker = job / "batch-0001.inflight"
        marker.write_text("TTV-P2-TEST-STALE-INFLIGHT", encoding="utf-8")
        self.worker().run(source)
        self.assertFalse(marker.exists())
        self.assertEqual(len(self.provider.calls), 2)

    def test_corrupt_checkpoint_fails_closed_without_new_billing(self):
        source = handoff(121)
        self.worker().run(source)
        job = self.folders()[0]
        cp = job / "batch-0001.json"
        data = json.loads(cp.read_text(encoding="utf-8"))
        data["translations"][0]["vi"] = "Tampered but well-formed"
        cp.write_text(json.dumps(data), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "CHECKPOINT_DIGEST_MISMATCH"):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 2)

    def test_existing_lock_blocks_second_worker_without_network(self):
        source = handoff(1)
        self.worker().run(source)
        job = self.folders()[0]
        (job / "active.lock").write_text("another process owns lock", encoding="utf-8")
        with self.assertRaises(FileExistsError):
            self.worker().run(source)
        self.assertEqual(len(self.provider.calls), 1)

    def test_bad_handoff_glossary_or_key_cannot_call_api(self):
        src = handoff(2)
        bad = replace(src, source_bytes=source_srt(1))
        with self.assertRaisesRegex(ValueError, "AUTO_LEAN120_SOURCE_CHANGED"):
            self.worker().run(bad)
        with self.assertRaisesRegex(ValueError, "AUTHORIZED_EN_HANDOFF_REQUIRED"):
            self.worker().run(replace(src, source_status="UNVERIFIED_OPEN_SUBTITLE"))
        with self.assertRaisesRegex(ValueError, "LEAN120_GLOSSARY_INVALID"):
            self.worker(glossary={"X": "Y" * 200}).run(src)
        with self.assertRaisesRegex(ValueError, "AUTO_LEAN120_RUNNER_INVALID"):
            self.worker(runner="")
        with self.assertRaisesRegex(ValueError, "ABSOLUTE_PRIVATE_STATE_REQUIRED"):
            self.worker(state_root=Path("relative"))
        self.assertEqual(self.provider.calls, [])
        self.assertFalse(self.root.exists())

    def test_profile_change_and_media_identity_create_isolated_jobs(self):
        src = handoff(1)
        self.worker().run(src)
        low = ModelProfile("antigravity", "gemini-4-hydrogen-low", "low")
        self.worker(profile=low).run(src)
        self.worker().run(handoff(1, OTHER))
        self.assertEqual(len(self.folders()), 3)
        self.assertEqual(len(self.provider.calls), 3)

    def test_owner_profile_transition_reuses_finished_and_partial_jobs(self):
        low = ModelProfile("antigravity", "gemini-4-hydrogen-low", "low")
        completed, partial, fresh = handoff(1), handoff(175), handoff(1, OTHER)
        old = self.worker(first_window_cues=50, preserve_hydrogen_jobs=True)
        old.run(completed)
        old.run(partial, max_new_windows=1)
        new = self.worker(profile=low, first_window_cues=50,
                          preserve_hydrogen_jobs=True)
        self.assertEqual(new.profile_for_source(completed), PROFILE)
        self.assertEqual(new.profile_for_source(partial), PROFILE)
        self.assertEqual(new.job_fingerprint(partial), old.job_fingerprint(partial))
        before = len(self.provider.calls)
        self.assertTrue(new.run(completed).complete)
        self.assertEqual(len(self.provider.calls), before)
        self.assertTrue(new.run(partial).complete)
        self.assertEqual([len(ids) for ids in self.provider.calls[before:]], [120, 5])
        self.assertEqual(new.profile_for_source(fresh), low)
        new.run(fresh)
        self.assertEqual(old.profile_for_source(fresh), low)  # rollback reuses Low
        self.assertEqual(len(self.folders()), 3)

    def test_owner_profile_transition_never_replays_unknown_high_call(self):
        source = handoff(1)
        self.provider.fail_on = 1
        with self.assertRaisesRegex(ValueError, "AGY_PROCESS_FAILED_RESULT_UNKNOWN"):
            self.worker().run(source)
        low = ModelProfile("antigravity", "gemini-4-hydrogen-low", "low")
        candidate = self.worker(profile=low, preserve_hydrogen_jobs=True)
        self.assertEqual(candidate.profile_for_source(source), PROFILE)
        with self.assertRaisesRegex(ValueError, "UNCERTAIN_BATCH_MANUAL_RECONCILE"):
            candidate.run(source)
        self.assertEqual(len(self.provider.calls), 1)
        self.assertEqual(len(self.folders()), 1)

    def test_owner_profile_transition_holds_conflicting_existing_jobs(self):
        source = handoff(1)
        low = ModelProfile("antigravity", "gemini-4-hydrogen-low", "low")
        self.worker().run(source)
        self.worker(profile=low).run(source)  # deliberate isolated test
        with self.assertRaisesRegex(ValueError, "PROFILE_STATE_AMBIGUOUS"):
            self.worker(profile=low, preserve_hydrogen_jobs=True).run(source)
        self.assertEqual(len(self.provider.calls), 2)

    def test_parallel_batches_finish_out_of_order_but_publish_contiguous(self):
        barrier = Barrier(3, timeout=5)
        later_ready = Event()
        finished = []
        guard = Lock()
        calls = []
        def parallel(cmd, **kwargs):
            prompt = json.loads(kwargs["input"].strip())["message"]["content"]
            ids = [x["id"] for x in json.loads(prompt.split("\n", 1)[1])["target"]]
            with guard:
                calls.append(ids[0])
            if ids[0] in (51, 171, 291):
                barrier.wait()
                if ids[0] == 51:
                    if not later_ready.wait(5):
                        raise RuntimeError("later window did not finish")
                if ids[0] == 291:
                    with guard:
                        finished.append(ids[0])
                    later_ready.set()
                else:
                    with guard:
                        finished.append(ids[0])
            return FakeAntigravity()(cmd, **kwargs)

        src = handoff(410)
        seen = []
        result = self.worker(first_window_cues=50, parallel_batches=3, runner=parallel).run(
            src, on_revision=seen.append)
        self.assertTrue(result.complete)
        self.assertEqual([r.translated_count for r in seen], [50, 170, 290, 410])
        self.assertLess(finished.index(291), finished.index(51))
        self.assertEqual(sorted(calls), [1, 51, 171, 291])
        self.assertEqual(list(self.folders()[0].glob("result-*.json")), [])
        self.assertEqual(list(self.folders()[0].glob("*.inflight")), [])

    def test_parallel_failure_preserves_paid_later_result_without_replay(self):
        barrier = Barrier(3, timeout=5)
        calls = []
        def fail_first(cmd, **kwargs):
            prompt = json.loads(kwargs["input"].strip())["message"]["content"]
            ids = [x["id"] for x in json.loads(prompt.split("\n", 1)[1])["target"]]
            calls.append(ids[0])
            if ids[0] != 1:
                barrier.wait()
            if ids[0] == 51:
                raise ValueError("AGY_PROCESS_FAILED_RESULT_UNKNOWN")
            return FakeAntigravity()(cmd, **kwargs)
        src = handoff(410)
        seen = []
        worker = self.worker(first_window_cues=50, parallel_batches=3, runner=fail_first)
        with self.assertRaisesRegex(ValueError, "AGY_PROCESS_FAILED_RESULT_UNKNOWN"):
            worker.run(src, on_revision=seen.append)
        folder = self.folders()[0]
        self.assertEqual([r.translated_count for r in seen], [50])
        self.assertTrue((folder / "batch-0002.inflight").is_file())
        self.assertTrue((folder / "result-0003.json").is_file())
        self.assertTrue((folder / "result-0004.json").is_file())
        self.assertFalse((folder / "batch-0003.json").exists())
        with self.assertRaisesRegex(ValueError, "UNCERTAIN_BATCH_MANUAL_RECONCILE"):
            worker.run(src)
        self.assertEqual(sorted(calls), [1, 51, 171, 291])

    def test_parallel_pilot_still_only_calls_first_window(self):
        self.worker(first_window_cues=50, parallel_batches=3).run(
            handoff(410), max_new_windows=1)
        self.assertEqual([len(x) for x in self.provider.calls], [50])

    def test_many_cues_are_progressive_no_manual_batch_stepping(self):
        src = handoff(1761)
        final = self.worker().run(src)
        self.assertTrue(final.complete)
        self.assertEqual(final.total_count, 1761)
        self.assertEqual(final.translated_count, 1761)
        self.assertEqual(len(self.provider.calls), 15)
        self.assertEqual(len(parse_cues(final.payload, "srt")), 1761)
        self.assertTrue((self.folders()[0] / "vi-final.srt").is_file())


if __name__ == "__main__":
    unittest.main()
