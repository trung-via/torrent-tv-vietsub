"""Single-pass P3/P2/P4 diagnostic without real host/provider/TV."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from owner_full_flow_snapshot_v4 import (
    SCHEMA, _p2_commits, _p4_from_private_log,
    build_snapshot_v4, publish_owner_snapshot_v4,
)


class FullFlowSnapshotV4Tests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="ttv-v4-synthetic-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.owner = self.root / "OwnerBridge"
        self.owner.mkdir()
        self.diag = self.owner / "diagnostics"
        self.diag.mkdir()
        (self.owner / "agent-health.json").write_text(
            json.dumps({"pid": 1234}), encoding="utf-8")

    def write_log(self, *lines: str):
        (self.diag / "owner-full.log").write_text(
            "\n".join(lines) + "\n", encoding="utf-8")

    def test_missing_log_is_not_a_p4_success_or_failure(self):
        self.assertEqual(_p4_from_private_log(self.owner)["status"],
                         "NOT_OBSERVED")

    def test_current_owner_request_reports_only_fixed_stage_counters(self):
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=1234 epoch=1784700000",
            "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED' {'status': 'DISPATCH', 'reason': 'SEARCH_VI_FAST_THEN_EN'}",
            "OWNER_FULL_TRACE 'P2_EVENT_CLAIMED' {'video': 'PRIVATE_MOVIE_TITLE'}",
            "OWNER_FULL_TRACE 'P2_EVENT_FINISHED' {'event_id': 'secret', 'result': 'VIETSUB_READY'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_ACTIVATE_REJECTED_P3_READY_NO_CURRENT_ACCEPTED_SOURCE'}",
            "OWNER_FULL_TRACE 'P4_ROLLING_STATUS' {'code': 'MEDIA_KEY_MISMATCH'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_ACTIVATE_HTTP_200'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_REVISION_HTTP_200'}",
        )
        result = _p4_from_private_log(self.owner)
        self.assertEqual(result["status"], "CURRENT_REQUEST_OBSERVED")
        self.assertEqual(result["activate_rejected"], 1)
        self.assertEqual(result["source_not_accepted"], 1)
        self.assertEqual(result["activate_ok"], 1)
        self.assertEqual(result["revision_ready"], 1)
        self.assertEqual(result["rolling_status"], "MEDIA_KEY_MISMATCH")
        self.assertEqual(result["p2_outcome"], "VIETSUB_READY")
        self.assertEqual(result["last_delivery"], "REVISION_READY")
        self.assertNotIn("PRIVATE_MOVIE_TITLE", json.dumps(result))

    def test_p2_blocked_or_new_claim_never_reuses_earlier_completed_outcome(self):
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=1234 epoch=1784700000",
            "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED' {'status': 'DISPATCH'}",
            "OWNER_FULL_TRACE 'P2_EVENT_FINISHED' {'result': 'VIETSUB_READY'}",
            "OWNER_FULL_TRACE 'P2_EVENT_CLAIMED' {'event_id': 'private'}",
            "OWNER_FULL_TRACE 'P2_EVENT_BLOCKED' {'event_id': 'private'}",
        )
        self.assertEqual(_p4_from_private_log(self.owner)["p2_outcome"], "BLOCKED")

    def test_old_process_log_is_never_reported_as_new_request(self):
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=1234 epoch=1784700000",
            "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED' {'status': 'DISPATCH'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_ACTIVATE_HTTP_200'}",
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=5678 epoch=1784701200",
        )
        self.assertEqual(_p4_from_private_log(self.owner)["status"],
                         "NOT_OBSERVED")
        (self.owner / "agent-health.json").write_text(
            json.dumps({"pid": 5678}), encoding="utf-8")
        self.assertEqual(_p4_from_private_log(self.owner)["status"],
                         "NO_REQUEST_IN_TAIL")

    def test_only_contiguous_commits_from_single_active_job(self):
        folder = self.root / "P2" / "auto-lean120-state" / ("a" * 64)
        folder.mkdir(parents=True)
        for version in (1, 2, 3):
            (folder / f"batch-{version:04d}.json").write_text("synthetic")
        (folder / "batch-0004.inflight").write_text("synthetic")
        result = _p2_commits(self.owner, now=1784700000)
        self.assertEqual(result["committed_prefix"], 3)
        self.assertEqual(result["final_present"], "NO")
        (folder / "batch-0002.json").unlink()
        self.assertEqual(_p2_commits(self.owner, now=1784700000)[
            "committed_prefix"], -1)

    def test_v4_is_bounded_privacy_only_and_never_mutates_worker(self):
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=1234 epoch=1784700000",
            "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED' {'status': 'DISPATCH'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_ACTIVATE_REJECTED_P3_READY_NO_CURRENT_ACCEPTED_SOURCE'}",
        )
        spool = self.root / "spool"
        spool.mkdir()
        v3 = {
            "schema": "TTV-HOSTOPS-OWNER-SNAPSHOT-V3",
            "p2": {"status": "CLEAR"},
        }
        with patch("owner_full_flow_snapshot_v4.build_snapshot_v3",
                   return_value=v3):
            self.assertTrue(publish_owner_snapshot_v4(
                owner_root=self.owner, shared_dir=spool))
        receipt = (spool / "owner-snapshot.json").read_text("ascii")
        self.assertLessEqual(len(receipt), 4096)
        self.assertIn(SCHEMA, receipt)
        self.assertIn("SOURCE_NOT_ACCEPTED", receipt)
        self.assertNotIn("PRIVATE_MOVIE_TITLE", receipt)
        self.assertFalse((self.root / "P2").exists())

    def test_latest_missing_dispatch_does_not_inherit_earlier_p4(self):
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=1234 epoch=1784700000",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_ACTIVATE_HTTP_200'}",
        )
        outcome = _p4_from_private_log(self.owner)
        self.assertEqual(outcome["status"], "NO_REQUEST_IN_TAIL")
        self.assertEqual(outcome["activate_ok"], 0)

    def test_long_live_owner_log_keeps_bounded_current_request_observation(self):
        import os
        (self.owner / "agent-health.json").write_text(
            json.dumps({"pid": os.getpid()}), encoding="utf-8")
        self.write_log(
            "OWNER_FULL_DIAGNOSTICS_STARTED pid=" + str(os.getpid()) + " epoch=1784700000",
            "X" * (193 * 1024),
            "OWNER_FULL_TRACE 'P3_SELECTION_ACCEPTED' {'status': 'DISPATCH'}",
            "OWNER_FULL_TRACE 'P4_DELIVERY_STATUS' {'code': 'P4_REVISION_HTTP_200'}",
        )
        self.assertEqual(_p4_from_private_log(self.owner)["revision_ready"], 1)
        # If a different process tries to reconstruct the same tail, the
        # private log is insufficient proof of current Owner identity.
        (self.owner / "agent-health.json").write_text(
            json.dumps({"pid": os.getpid() + 1}), encoding="utf-8")
        self.assertEqual(_p4_from_private_log(self.owner)["status"], "NOT_OBSERVED")


if __name__ == "__main__":
    unittest.main()
