"""Offline safety and receipt contract for the P2 batch-2 root-cause probe."""
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OP = ROOT / "hostops/laptop-ops/operations/owner-p2-block-rootcause-v1.ps1"
READER = ROOT / "hostops/jobs/owner-p2-block-rootcause-readonly.ps1"


class P2RootCauseSafety(unittest.TestCase):
    def test_no_state_or_task_mutation(self):
        source = OP.read_text(encoding="utf-8")
        for mutation in (
            "Move-Item", "Remove-Item", "Stop-Process", "Stop-ScheduledTask",
            "Start-ScheduledTask", "Enable-ScheduledTask", "Disable-ScheduledTask",
            "Invoke-WebRequest", "Invoke-RestMethod", "agy --model",
        ):
            self.assertNotIn(mutation, source)
        self.assertIn("batch-0001.json", source)
        self.assertIn("batch-0002.inflight", source)
        self.assertIn("owner-full.log", source)
        self.assertIn("'AGY_TIMEOUT_RESULT_UNKNOWN'", source)

    def test_reader_never_opens_owner_private_data(self):
        source = READER.read_text(encoding="utf-8")
        self.assertNotIn("$env:LOCALAPPDATA", source)
        self.assertIn("P2_ROOTCAUSE_READER_STALE", source)
        self.assertIn("P2_ROOTCAUSE_PRIVATE_DATA=NOT_READ_BY_RUNNER", source)
        self.assertIn("S-1-5-20", source)


if __name__ == "__main__":
    unittest.main()
