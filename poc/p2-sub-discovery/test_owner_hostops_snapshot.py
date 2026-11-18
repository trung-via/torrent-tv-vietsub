"""#174: offline Owner/HostOps boundary, no runner, TV or model execution."""
from pathlib import Path
from types import SimpleNamespace
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
