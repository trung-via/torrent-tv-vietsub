"""Synthetic-only R3.2 tests: no media, secrets, model or network."""
from __future__ import annotations

import threading
import unittest

from r3_2_continuous_queue import QueueBlocked, run_continuous


def run(ids, *, cached=(), invoke=None, verify_cached=None, verify_result=None,
        commit=None, owner_guard=None, workers=3):
    commits = []
    report = run_continuous(
        ids, cached_ids=cached, max_workers=workers,
        owner_guard=(owner_guard if owner_guard is not None else lambda: True),
        verify_cached=(verify_cached if verify_cached is not None else lambda i: True),
        invoke_provider=(invoke if invoke is not None else lambda i: {"id": i}),
        verify_result=(verify_result if verify_result is not None
                       else lambda i, x: x["id"] == i),
        commit_checkpoint=(commit if commit is not None
                           else lambda i, x: (commits.append(i) or True)),
    )
    return report, commits


class ContinuousQueueTests(unittest.TestCase):
    def test_all_cached_never_calls_provider(self):
        report, committed = run(range(1, 21), cached=range(1, 21),
                                invoke=lambda i: self.fail("provider invoked"))
        self.assertEqual(report.submitted, ())
        self.assertEqual(committed, [])
        self.assertEqual(len(report.reused), 20)

    def test_legacy_8_of_20_reused_no_retranslation(self):
        report, _ = run(range(1, 21), cached=range(1, 9), workers=4)
        self.assertEqual(report.submitted, tuple(range(9, 21)))
        self.assertEqual(report.committed, tuple(range(9, 21)))
        self.assertEqual(report.retry_count, 0)

    def test_no_wave_barrier_refills_before_slow_peer_completes(self):
        release_second = threading.Event()
        third_started = threading.Event()
        seen = []
        lock = threading.Lock()
        errors = []
        reports = []

        def provider(batch):
            with lock:
                seen.append(batch)
            if batch == 2:
                if not release_second.wait(3):
                    raise RuntimeError("synthetic timeout")
            if batch == 3:
                third_started.set()
            return {"id": batch}

        def worker():
            try:
                reports.append(run(range(1, 5), invoke=provider, workers=2)[0])
            except Exception as error:
                errors.append(error)

        t = threading.Thread(target=worker, daemon=True)
        t.start()
        try:
            self.assertTrue(third_started.wait(2),
                            "batch 3 should start before batch 2 completes")
            self.assertIn(3, seen)
        finally:
            release_second.set()
            t.join(4)
        self.assertFalse(t.is_alive())
        self.assertFalse(errors)
        self.assertEqual(reports[0].committed, (1, 2, 3, 4))

    def test_first_provider_failure_stops_new_dispatch_but_drains_inflight(self):
        second_started = threading.Event()
        release_second = threading.Event()
        fail_observed = threading.Event()
        seen = []
        lock = threading.Lock()

        def provider(i):
            with lock:
                seen.append(i)
            if i == 1:
                self.assertTrue(second_started.wait(3))
                return {"id": -1, "private": "PRIVATE_PROVIDER_PAYLOAD_MUST_NOT_LEAK"}
            if i == 2:
                second_started.set()
                self.assertTrue(release_second.wait(3))
            return {"id": i}

        def verify(i, result):
            if i == 1:
                fail_observed.set()  # deterministic: scheduler sees invalid result before 2 finishes
                return False
            return result["id"] == i

        def task():
            try:
                run(range(1, 6), workers=2, invoke=provider,
                    verify_result=verify)
            except QueueBlocked as e:
                return e
            return None

        result = []
        t = threading.Thread(target=lambda: result.append(task()), daemon=True)
        t.start()
        try:
            self.assertTrue(second_started.wait(2))
            self.assertTrue(fail_observed.wait(2))
        finally:
            release_second.set()
            t.join(4)
        self.assertFalse(t.is_alive())
        self.assertIsInstance(result[0], QueueBlocked)
        self.assertNotIn("PRIVATE", str(result[0]))
        self.assertEqual(result[0].code, "R32_INVALID_PROVIDER_RESULT")
        self.assertEqual(result[0].report.failed, (1,))
        self.assertEqual(result[0].report.unsubmitted, (3, 4, 5))
        self.assertEqual(result[0].report.retry_count, 0)
        self.assertEqual(result[0].report.committed, (2,))
        self.assertEqual(sorted(seen), [1, 2])

    def test_provider_exception_message_is_sanitized_without_replay(self):
        invoked = []

        def provider(i):
            invoked.append(i)
            raise RuntimeError("PRIVATE_PROVIDER_PAYLOAD_MUST_NOT_LEAK")

        with self.assertRaises(QueueBlocked) as ctx:
            run((1, 2), workers=1, invoke=provider)
        self.assertEqual(ctx.exception.code, "R32_PROVIDER_FAILURE")
        self.assertNotIn("PRIVATE", str(ctx.exception))
        self.assertEqual(ctx.exception.report.unsubmitted, (2,))
        self.assertEqual(invoked, [1])

    def test_invalid_cache_refuses_provider_and_preserves_original(self):
        with self.assertRaisesRegex(QueueBlocked, "R32_CACHED_CHECKPOINT_INVALID"):
            run((1, 2), cached=(1,), verify_cached=lambda i: False,
                invoke=lambda i: self.fail("must not call provider"))

    def test_commit_failure_stops_new_dispatch(self):
        with self.assertRaisesRegex(QueueBlocked, "R32_CHECKPOINT_COMMIT_FAILED") as ctx:
            run((1,), commit=lambda i, x: False, workers=1)
        self.assertEqual(ctx.exception.report.failed, (1,))

    def test_missing_owner_refuses_any_calls(self):
        with self.assertRaisesRegex(QueueBlocked, "R32_OWNER_LOCK_NOT_PROVEN"):
            run((1,), owner_guard=lambda: False,
                invoke=lambda i: self.fail("owner lock missing"))

    def test_provider_bad_result_fail_closed(self):
        with self.assertRaisesRegex(QueueBlocked, "R32_INVALID_PROVIDER_RESULT"):
            run((1,), invoke=lambda i: {"id": 777}, workers=1)

    def test_batch_id_validation_no_duplicate_reordering_or_bool(self):
        for ids in [[], [1, 1], [2, 1], [1, True], [0, 1], [1, -2]]:
            with self.subTest(ids=ids), self.assertRaises(QueueBlocked):
                run(ids)
        with self.assertRaisesRegex(QueueBlocked, "R32_UNKNOWN_CACHED_BATCH"):
            run((1, 2), cached=(3,))

    def test_parallelism_bounds(self):
        for val in [0, 5, True, -1]:
            with self.subTest(workers=val), self.assertRaisesRegex(QueueBlocked, "R32_WORKERS_OUT_OF_RANGE"):
                run((1,), workers=val)

    def test_verify_cached_before_provider(self):
        events = []
        report, _ = run((1, 2, 3), cached=(1, 2),
                        verify_cached=lambda i: (events.append(("cache", i)) or True),
                        invoke=lambda i: (events.append(("provider", i)) or {"id": i}),
                        workers=2)
        self.assertEqual(events, [("cache", 1), ("cache", 2), ("provider", 3)])
        self.assertEqual(report.committed, (3,))

    def test_commit_only_validated_outputs(self):
        committed = []
        with self.assertRaisesRegex(QueueBlocked, "R32_INVALID_PROVIDER_RESULT"):
            run((1,), verify_result=lambda i, x: False,
                commit=lambda i, x: committed.append(i) or True)
        self.assertEqual(committed, [])


if __name__ == "__main__":
    unittest.main()
