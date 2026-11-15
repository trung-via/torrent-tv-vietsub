"""No-LAN/no-provider tests of owner-private runtime receipts and observer."""
from pathlib import Path
from types import SimpleNamespace
import json
import os
import tempfile
import time
import unittest
from unittest import mock

from owner_p3_p4_diagnostics import (
    RUNTIME_VERSION, _p3_only_snapshot, _tcp_only_probe,
    read_diagnostic, write_diagnostic,
)
from p3_ingress_telemetry import MAX_COUNT, P3IngressTelemetry


class Cache:
    def diagnostic_freshness(self):
        return "FRESH_OFF", 7


class OwnerP3P4DiagnosticTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory()
        self.addCleanup(t.cleanup)
        self.owner = Path(t.name).resolve() / "OwnerBridge"
        self.owner.mkdir()
        self.wiring = SimpleNamespace(
            cache=Cache(), current=SimpleNamespace(
                _ts=SimpleNamespace(_config=SimpleNamespace(localhost_port=8090))),
            ingress=P3IngressTelemetry())

    def _health(self, observed=None, state="READY", pid=None):
        doc = {"schema": "TTV-OWNER-AGENT-HEALTH-V1", "state": state,
               "pid": os.getpid() if pid is None else pid, "observed_utc_epoch": (
                   int(time.time()) if observed is None else observed)}
        (self.owner / "agent-health.json").write_text(json.dumps(doc))

    def test_actual_owner_tick_has_no_media_or_keys_and_requires_fresh_health(self):
        self.wiring.ingress.record("state_rejected")
        self.wiring.ingress.record("state_accepted")
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection") as socket:
            socket.return_value.__enter__.return_value = object()
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")
            socket.assert_called_once_with(("127.0.0.1", 8090), timeout=0.25)
        path = self.owner / "p3-p4-runtime-diagnostic.json"
        body = path.read_text()
        for forbidden in ("torrent_hash", "file_index", "video_name", "pairing",
                          "OpenSubtitles", "Gemini", "http://"):
            self.assertNotIn(forbidden, body)
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")
        self._health()
        status = read_diagnostic(owner_root=self.owner)
        self.assertEqual(status["OWNER_RUNTIME_MODE"], "INTEGRATED_P3_P4")
        self.assertEqual(status["OWNER_RUNTIME_VERSION"], RUNTIME_VERSION)
        self.assertEqual(status["P3_STATE_FRESH"], "FRESH_OFF")
        self.assertEqual(status["TORRSERVER_READER_READY"],
                         "TCP_REACHABLE_METADATA_UNTESTED")
        self.assertEqual(status["OWNER_HEARTBEAT"], "READY_FRESH")
        self.assertEqual(status["P3_HTTPS_INSTRUMENTED"], "YES")
        self.assertEqual(status["P3_HTTPS_STATE_ACCEPTED"], "1")
        self.assertEqual(status["P3_HTTPS_STATE_REJECTED"], "1")
        self.assertEqual(status["P3_HTTPS_STATE_REJECTED_AUTH"], "0")
        self.assertEqual(status["P3_HTTPS_SELECTION_DISPATCHED"], "0")

    def test_tcp_connect_is_local_only_and_cannot_claim_metadata_verified(self):
        self.assertEqual(_tcp_only_probe(object()), "CONFIG_INVALID")
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection",
                        side_effect=OSError("private connection details")):
            self.assertEqual(_tcp_only_probe(self.wiring.current._ts),
                             "TCP_UNREACHABLE")
        self.assertEqual(_p3_only_snapshot(Cache()), ("FRESH_OFF", 7))

    def test_stale_or_stopped_receipt_never_claims_live(self):
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")
        now = int(time.time())
        self._health(observed=now - 31)
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")
        self._health()
        self.assertEqual(read_diagnostic(owner_root=self.owner, now=now + 6)[
            "OWNER_RUNTIME_MODE"], "NOT_OBSERVED")
        write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="STOPPED")
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")

    def test_recent_receipt_from_previous_process_cannot_match_new_heartbeat(self):
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")
        self._health(pid=os.getpid() + 1)
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")
        # Exact PID permits a live claim only with both fresh, same-process records.
        self._health()
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "INTEGRATED_P3_P4")

    def test_invalid_values_and_symlinks_fail_closed(self):
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")
        self._health()
        path = self.owner / "p3-p4-runtime-diagnostic.json"
        value = json.loads(path.read_text())
        value["p3"] = []
        path.write_text(json.dumps(value))
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")
        path.write_text("x" * 1025)
        self.assertEqual(read_diagnostic(owner_root=self.owner)["OWNER_RUNTIME_MODE"],
                         "NOT_OBSERVED")
        path.unlink()
        try:
            path.symlink_to(self.owner / "agent-health.json")
        except (OSError, NotImplementedError):
            return
        with self.assertRaisesRegex(ValueError, "DIAG_SYMLINK"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")

    def test_private_ingress_receipt_rejects_forged_counts_and_no_instrumentation(self):
        self.wiring.ingress = None
        with mock.patch("owner_p3_p4_diagnostics.socket.create_connection"):
            write_diagnostic(owner_root=self.owner, wiring=self.wiring, state="READY")
        self._health()
        status = read_diagnostic(owner_root=self.owner)
        self.assertEqual(status["P3_HTTPS_INSTRUMENTED"], "NO")
        path = self.owner / "p3-p4-runtime-diagnostic.json"
        body = json.loads(path.read_text())
        body["p3_ingress"]["state_accepted"] = "3"
        path.write_text(json.dumps(body))
        self.assertEqual(read_diagnostic(owner_root=self.owner)[
            "OWNER_RUNTIME_MODE"], "NOT_OBSERVED")

    def test_ingress_counters_are_bounded_and_non_identifying(self):
        ingress = P3IngressTelemetry()
        with self.assertRaisesRegex(ValueError, "P3_INGRESS_EVENT_INVALID"):
            ingress.record("private/movie/secret")
        ingress.record("selection_skipped")
        copy = ingress.snapshot()
        copy["selection_skipped"] = 555
        self.assertEqual(ingress.snapshot()["selection_skipped"], 1)
        ingress._counts["state_rejected"] = MAX_COUNT
        ingress.record("state_rejected")
        self.assertEqual(ingress.snapshot()["state_rejected"], MAX_COUNT)


if __name__ == "__main__":
    unittest.main()
