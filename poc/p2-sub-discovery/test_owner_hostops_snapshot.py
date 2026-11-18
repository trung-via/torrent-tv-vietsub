"""#174: offline Owner/HostOps boundary, no runner, TV or model execution."""
from pathlib import Path
from types import SimpleNamespace
import hashlib
import json
import os
import tempfile
import time
import unittest
from unittest import mock

from owner_hostops_snapshot import (
    SCHEMA, build_snapshot, publish_owner_snapshot,
)
from owner_p3_p4_diagnostics import read_diagnostic, write_diagnostic
from owner_p3_p4_runtime import _diagnostic_tick
from p3_ingress_telemetry import P3IngressTelemetry


class HostOpsSnapshotTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.owner = self.root / "private" / "OwnerBridge"
        self.owner.mkdir(parents=True)
        self.shared = self.root / "public" / "Diagnostics"
        self.wiring = SimpleNamespace(
            cache=SimpleNamespace(diagnostic_freshness=lambda: ("FRESH_REQUESTED", 8)),
            current=SimpleNamespace(_ts=SimpleNamespace(
                _config=SimpleNamespace(localhost_port=8090))),
            ingress=P3IngressTelemetry(),
        )

    def _health(self, *, pid=None, state="READY", observed=None):
        doc = {"schema": "TTV-OWNER-AGENT-HEALTH-V1", "state": state,
               "pid": os.getpid() if pid is None else pid,
               "observed_utc_epoch": (int(time.time()) if observed is None
                                       else observed)}
        (self.owner / "agent-health.json").write_text(json.dumps(doc))

    def _diag(self, state="READY"):
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state=state)

    def test_missing_corrupt_stale_and_process_mismatch_are_distinct(self):
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"], "MISSING")
        self._diag()
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"], "MISSING")
        self._health()
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"], "READY_FRESH")
        self._health(pid=os.getpid() + 1)
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"], "PID_MISMATCH")
        self._health(state="BLOCKED")
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"],
                         "OWNER_NOT_RUNNING")
        self._health()
        diag_file = self.owner / "p3-p4-runtime-diagnostic.json"
        diagnostic = json.loads(diag_file.read_text())
        now = int(time.time())
        diagnostic["observed_utc_epoch"] = now - 7
        diag_file.write_text(json.dumps(diagnostic))
        self.assertEqual(build_snapshot(owner_root=self.owner, now=now)["status"],
                         "STALE")
        diag_file.write_text("{BAD")
        self.assertEqual(build_snapshot(owner_root=self.owner)["status"],
                         "INVALID_SCHEMA")

    def test_export_is_opt_in_atomic_sanitized_and_never_creates_spool(self):
        self._health()
        self.wiring.ingress.record("selection_dispatched")
        self._diag()
        self.assertFalse(publish_owner_snapshot(
            owner_root=self.owner, shared_dir=self.shared))
        self.assertFalse(self.shared.exists())
        self.shared.mkdir(parents=True)
        self.assertTrue(publish_owner_snapshot(
            owner_root=self.owner, shared_dir=self.shared))
        data = json.loads((self.shared / "owner-snapshot.json").read_text())
        self.assertEqual(data["schema"], SCHEMA)
        self.assertEqual(data["status"], "READY_FRESH")
        self.assertEqual(data["p2"]["status"], "STATE_MISSING")
        self.assertEqual(data["p2"]["inflight_count"], -1)
        self.assertEqual(data["ingress"]["selection_dispatched"], 1)
        self.assertLessEqual(data["owner_snapshot_age_seconds"], 5)
        self.assertEqual(set(self.shared.iterdir()),
                         {self.shared / "owner-snapshot.json"})
        serialized = json.dumps(data)
        for forbidden in ("video_filename", "tv_session_id", "torrent_hash",
                          "api_key", "secret", str(self.owner), "http://"):
            self.assertNotIn(forbidden, serialized)
        self._health(pid=os.getpid() + 9)
        self.assertTrue(publish_owner_snapshot(
            owner_root=self.owner, shared_dir=self.shared))
        invalid = json.loads((self.shared / "owner-snapshot.json").read_text())
        self.assertEqual(invalid["status"], "PID_MISMATCH")
        self.assertEqual(invalid["ingress"]["selection_dispatched"], -1)

    def test_owner_p2_unknown_effect_is_sanitized_without_replay(self):
        self._health()
        self._diag()
        (self.owner / "inbox").mkdir()
        (self.owner / "inbox" / "event-test.json").write_text(
            '{"movie_title":"PRIVATE_SYNTHETIC"}')
        reviewed = (Path(__file__).resolve().parents[1] / "p2-aisub" /
                    "automatic_lean120_worker.py")
        installed = (self.owner / "app" / "poc" / "p2-aisub" /
                     "automatic_lean120_worker.py")
        installed.parent.mkdir(parents=True)
        installed.write_bytes(reviewed.read_bytes())
        job = "a" * 64
        folder = self.root / "private" / "P2" / "auto-lean120-state" / job
        folder.mkdir(parents=True)
        marker = folder / "batch-0001.inflight"
        marker.write_text(json.dumps({"schema": "TTV-P2-INFLIGHT-V1",
                                      "job": job, "version": 1}))
        original = marker.read_bytes()
        snapshot = build_snapshot(owner_root=self.owner)
        p2 = snapshot["p2"]
        self.assertEqual(snapshot["schema"], SCHEMA)
        self.assertEqual(p2["status"], "UNKNOWN_EFFECT_HOLD")
        self.assertEqual(p2["pending_events"], 1)
        self.assertEqual(p2["inflight_count"], 1)
        self.assertEqual(p2["batch"], "batch-0001")
        self.assertEqual(p2["marker_sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(p2["checkpoint_present"], "NO")
        self.assertEqual(p2["active_lock_present"], "NO")
        self.assertEqual(p2["installed_no_retry_worker_match"], "YES")
        self.shared.mkdir(parents=True)
        self.assertTrue(publish_owner_snapshot(
            owner_root=self.owner, shared_dir=self.shared))
        public = (self.shared / "owner-snapshot.json").read_text()
        self.assertNotIn("PRIVATE_SYNTHETIC", public)
        self.assertNotIn(job, public)
        self.assertNotIn(str(self.owner), public)
        self.assertEqual(marker.read_bytes(), original)
        self.assertFalse((folder / "batch-0001.json").exists())
        self.assertFalse((folder / "active.lock").exists())

        (folder / "active.lock").write_text("synthetic")
        (folder / "batch-0001.json").write_text("synthetic")
        locked = build_snapshot(owner_root=self.owner)["p2"]
        self.assertEqual(locked["checkpoint_present"], "YES")
        self.assertEqual(locked["active_lock_present"], "YES")
        marker.write_text("not-json")
        self.assertEqual(build_snapshot(owner_root=self.owner)["p2"]["status"],
                         "INVALID_MARKER")
        marker.write_text(json.dumps({"schema": "TTV-P2-INFLIGHT-V1",
                                      "job": job, "version": 1}))
        (folder / "batch-0002.inflight").write_text("unknown")
        self.assertEqual(build_snapshot(owner_root=self.owner)["p2"]["status"],
                         "MULTIPLE_HOLD")

    def test_owner_p2_missing_or_invalid_worker_never_claims_match(self):
        state = self.root / "private" / "P2" / "auto-lean120-state"
        state.mkdir(parents=True)
        p2 = build_snapshot(owner_root=self.owner)["p2"]
        self.assertEqual(p2["status"], "CLEAR")
        self.assertEqual(p2["inflight_count"], 0)
        self.assertEqual(p2["installed_no_retry_worker_match"], "NOT_OBSERVED")
        installed = (self.owner / "app" / "poc" / "p2-aisub" /
                     "automatic_lean120_worker.py")
        installed.parent.mkdir(parents=True)
        installed.write_text("# old synthetic worker\n")
        self.assertEqual(build_snapshot(owner_root=self.owner)["p2"]
                         ["installed_no_retry_worker_match"], "NO")

    def test_no_symlink_export_and_not_owner_private_read_from_runner(self):
        self._health()
        self._diag()
        try:
            self.shared.symlink_to(self.owner, target_is_directory=True)
        except (OSError, NotImplementedError):
            return
        self.assertFalse(publish_owner_snapshot(
            owner_root=self.owner, shared_dir=self.shared))
        self.assertFalse((self.owner / "owner-snapshot.json").exists())

    def test_private_legacy_cli_remains_exactly_compatible(self):
        self._health()
        self._diag()
        fields = read_diagnostic(owner_root=self.owner)
        self.assertEqual(fields["P3_HTTPS_SELECTION_DISPATCHED"], "0")
        self.assertEqual(fields["OWNER_HEARTBEAT"], "READY_FRESH")
        self.assertEqual(fields["P3_STATE_FRESH"], "FRESH_REQUESTED")
        self.assertNotIn("OWNER_SNAPSHOT_STATUS", fields)

    def test_runtime_tick_preserves_private_diagnostic_before_optional_export(self):
        with (mock.patch("owner_p3_p4_runtime.write_diagnostic") as private,
              mock.patch("owner_p3_p4_runtime.publish_owner_snapshot") as publish):
            _diagnostic_tick(owner_root=self.owner, wiring=self.wiring, state="READY")
        private.assert_called_once_with(owner_root=self.owner,
                                        wiring=self.wiring, state="READY")
        publish.assert_called_once_with(owner_root=self.owner)


if __name__ == "__main__":
    unittest.main()
