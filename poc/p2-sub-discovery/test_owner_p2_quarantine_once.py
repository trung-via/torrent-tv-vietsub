"""Static safety contract for one authorized Owner-private P2 quarantine.

Never runs PowerShell or touches a scheduled task, Windows state or provider.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "hostops/setup/owner-p2-quarantine-once.ps1"

PINS = {
    "hostops/setup/p2-inflight-reconcile-offline.ps1": "7121616cf9286776400bb0cbfb6ce970121014688ed0175a348f42d4be10b21d",
    "hostops/setup/owner-p2-snapshot-once.ps1": "5ea41dfbcddd4b447dc1bf839a3048654e89f1a2c31a6e50fe3945ae70a753f4",
    "poc/p2-aisub/automatic_lean120_worker.py": "d8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0",
    "poc/p2-sub-discovery/owner-task-principal-identity.ps1": "9fd3c43f10cf9694d6ecc396aae6a3e6fc724a51750c7d51a2d287d431f778d9",
    "poc/p2-sub-discovery/owner-task-action-identity.ps1": "f3c497123af4d38c806aa631684e0a77fa926285c4d31ccba8d88f802cb27caf",
}


class OwnerP2QuarantineOnceTests(unittest.TestCase):
    def test_immutable_exact_source_pins(self) -> None:
        script = TOOL.read_text(encoding="utf-8")
        self.assertIn("cac462c1dd854a7b19fd0eb02018c9bd1aebb7fe", script)
        for path, expected in PINS.items():
            # Windows may check out CRLF; immutable raw GitHub Git blobs use LF.
            raw = (ROOT / path).read_bytes().replace(b"\r\n", b"\n")
            self.assertEqual(hashlib.sha256(raw).hexdigest(), expected, path)
            self.assertIn(f"'{path}' = '{expected}'", script)

    def test_one_batch_and_logged_in_owner_only(self) -> None:
        script = TOOL.read_text(encoding="utf-8")
        self.assertIn("OWNER_P2_QUARANTINE_INTERACTIVE_OWNER_REQUIRED", script)
        self.assertIn("OWNER_P2_QUARANTINE_WRONG_WINDOWS_OWNER", script)
        self.assertIn("OWNER_P2_QUARANTINE_SOURCE_HASH_MISMATCH", script)
        self.assertIn("'P2_RECONCILE_BATCH'] -cne 'batch-0001'", script)
        self.assertIn("302e646ecf30301a9476be737a82f31484c9a25973abedab6da9d6a02999528f", script)
        self.assertIn("'P2_RECONCILE_PENDING_EVENTS'] -cne '0'", script)
        self.assertIn("'P2_RECONCILE_INSTALLED_NO_RETRY_WORKER_MATCH'] -cne 'True'", script)

    def test_read_only_preflight_then_stop_then_tombstone(self) -> None:
        script = TOOL.read_text(encoding="utf-8")
        inspect = script.index("$inspection = @(& pwsh -NoProfile -File $reconcile)")
        disable = script.index("Disable-ScheduledTask")
        stop = script.index("Stop-ScheduledTask")
        apply = script.index("-ApplyQuarantine `")
        after = script.index("$after = @(& pwsh -NoProfile -File $snapshot)")
        self.assertLess(inspect, disable)
        self.assertLess(disable, stop)
        self.assertLess(stop, apply)
        self.assertLess(apply, after)
        self.assertIn("-AcknowledgeUnknownEffect", script)
        self.assertIn("-ExpectedMarkerSha256 $approvedMarkerSha256", script)
        self.assertIn("OWNER_P2_QUARANTINE_RESULT=HOLD_TASK_LEFT_DISABLED", script)

    def test_never_restart_replay_or_delete_owner_data(self) -> None:
        script = TOOL.read_text(encoding="utf-8")
        for forbidden in (
            "Start-ScheduledTask", "Enable-ScheduledTask", "Remove-Item",
            ".inflight' |", "-Force -Recurse", "agy ", "gemini ",
        ):
            self.assertNotIn(forbidden, script)
        self.assertIn("OWNER_P2_QUARANTINE_TASK=LEFT_DISABLED_FOR_REVIEWED_RESTART", script)
        self.assertIn("OWNER_P2_QUARANTINE_PROVIDER_OR_TV=NOT_RUN", script)


if __name__ == "__main__":
    unittest.main()
