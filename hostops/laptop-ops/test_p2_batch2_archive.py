"""Source-only regression gates for one old uncertain P2 job archive."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OP = ROOT / "hostops/laptop-ops/operations/owner-p2-batch2-archive-v1.ps1"
READER = ROOT / "hostops/jobs/owner-p2-text-qa-status-readonly.ps1"


class Batch2ArchiveContract(unittest.TestCase):
    def test_single_exact_job_and_recoverable_archive(self):
        content = OP.read_text(encoding="utf-8")
        for required in (
            "batch-0002.inflight", "batch-0001.json", "TTV-P2-INFLIGHT-V1",
            "TTV-P2-LEAN120-CHECKPOINT-V1", "EXACT_BATCH2_NOT_UNIQUE",
            "P2_BUSY_OR_PENDING_EVENT", "PATCH_NOT_INSTALLED", "AssertIdle",
            "[IO.Directory]::Move($folder,$destination)",
            "[IO.Directory]::Move($destination,$folder)",
            "P2_BATCH2_ARCHIVE=ARCHIVED_RECOVERABLY_OWNER_READY",
            "P2_BATCH2_ARCHIVE_PROVIDER=NOT_RUN", "StartOwner $oldPid",
        ):
            self.assertIn(required, content)
        for forbidden in (
            "Invoke-RestMethod", "Invoke-WebRequest", "agy --model",
            "Remove-Item", "Clear-Content", "batch-0002.inflight').Delete",
            "Start-Process agy", "GEMINI_API_KEY",
        ):
            self.assertNotIn(forbidden, content)

    def test_reader_exposes_only_aggregate_status(self):
        content = READER.read_text(encoding="utf-8")
        self.assertIn("P2_TEXT_STATUS_ARCHIVED_BATCH2_COUNT", content)
        self.assertIn("P2_TEXT_STATUS_LAST_ARCHIVE_CODE", content)
        self.assertIn("P2_TEXT_STATUS_PRIVATE_LOG=NOT_EXPORTED", content)
        self.assertNotIn("$env:LOCALAPPDATA", content)


if __name__ == "__main__":
    unittest.main()
