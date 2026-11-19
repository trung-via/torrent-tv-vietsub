"""Source-only contract for Owner-once P2 -> existing sanitized HostOps receipt.

No Windows session, P2 data, task, network or provider is touched by this test.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "hostops/setup/owner-p2-snapshot-once.ps1"
CONSUMER = ROOT / "hostops/jobs/owner-diagnostic-snapshot.ps1"
SOURCE = ROOT / "poc/p2-sub-discovery"


class OwnerP2OneShotContractTests(unittest.TestCase):
    def test_pinned_python_sources_are_exact_reviewed_git_bytes(self) -> None:
        script = SETUP.read_text(encoding="utf-8")
        expected = {
            "owner_hostops_snapshot.py": "91e1c3400cfdca347c0cd15c5da9ee942d2a189a095e4ab7cb583a1d7664eb4f",
            "owner_p3_p4_diagnostics.py": "eca75e1f29f98cf8df356f5bf9e29e1f30ffa0ea4205a4be93ffabe55e36f524",
            "p3_ingress_telemetry.py": "d09c8503ab13577b3102f943e402cf98e2e78b4192f61597e9eb0a6d9c63b67d",
        }
        for name, digest in expected.items():
            # Windows checkout may use CRLF; raw GitHub source is LF.
            raw = (SOURCE / name).read_bytes().replace(b"\r\n", b"\n")
            self.assertEqual(hashlib.sha256(raw).hexdigest(), digest)
            self.assertIn("'" + name + "' = '" + digest + "'", script)

    def test_owner_only_writer_never_restarts_or_replays(self) -> None:
        script = SETUP.read_text(encoding="utf-8")
        self.assertIn("OWNER_P2_SNAPSHOT_INTERACTIVE_OWNER_REQUIRED", script)
        self.assertIn("OWNER_P2_SNAPSHOT_WRONG_WINDOWS_OWNER", script)
        self.assertIn("SOURCE_HASH_MISMATCH", script)
        self.assertIn("publish_owner_snapshot(owner_root=root)", script)
        self.assertNotIn("-ApplyQuarantine", script)
        self.assertNotIn("Start-ScheduledTask", script)
        self.assertNotIn("Stop-ScheduledTask", script)

    def test_hostops_p2_capture_does_not_require_live_p3_tick(self) -> None:
        consumer = CONSUMER.read_text(encoding="utf-8")
        self.assertIn("$p2CaptureRecent = $age -ge 0 -and $age -le 900", consumer)
        self.assertIn("if (($isV2 -or $isV3) -and $p2CaptureRecent)", consumer)
        self.assertIn("HOSTOPS_OWNER_P2_RECEIPT_AGE_SECONDS", consumer)
        self.assertIn("HOSTOPS_OWNER_P2_RESTART_OR_REPLAY_AUTHORIZED=NO", consumer)
        self.assertNotIn("if ($isV2 -and $status -ceq 'READY_FRESH')", consumer)


if __name__ == "__main__":
    unittest.main()
