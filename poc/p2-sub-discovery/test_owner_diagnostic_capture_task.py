"""Source-only checks for the repeatable Owner-local HostOps capture.

These tests never register tasks or access Owner-private Windows state.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
ENROLL = ROOT / "hostops/setup/enroll-owner-diagnostic-capture.ps1"
DISPATCH = ROOT / "hostops/jobs/owner-diagnostic-capture.ps1"
SNAPSHOT = ROOT / "hostops/jobs/owner-diagnostic-snapshot.ps1"
HELPER = ROOT / "hostops/setup/owner-p2-snapshot-once.ps1"
OWNER = "TorrentTV-Vietsub-OwnerAgent"
CAPTURE = "TorrentTV-Vietsub-Owner-Diagnostic-Capture"


class OwnerCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enroll = ENROLL.read_text(encoding="utf-8")
        cls.dispatch = DISPATCH.read_text(encoding="utf-8")

    def test_helper_immutable_and_minimal(self):
        digest = hashlib.sha256(HELPER.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        self.assertIn(digest, self.enroll)
        self.assertIn("02a8dc3a6a53c6386fe84c22fb7a44348fe37289", self.enroll)
        self.assertIn("OWNER_DIAG_ENROLL_SOURCE_HASH_MISMATCH", self.enroll)
        self.assertIn("OWNER_DIAG_ENROLL_HELPER_DRIFT", self.enroll)
        self.assertIn("OWNER_P2_SNAPSHOT_TASK_OR_PROVIDER=NOT_CHANGED", HELPER.read_text())

    def test_enrollment_no_live_owner_mutation(self):
        self.assertIn(f"$ownerTaskName = '{OWNER}'", self.enroll)
        self.assertIn(f"$taskName = '{CAPTURE}'", self.enroll)
        self.assertIn("Test-TTVOwnerTaskPrincipal", self.enroll)
        self.assertIn("Get-TTVOwnerTaskActionState", self.enroll)
        self.assertIn("-LogonType Interactive -RunLevel Limited", self.enroll)
        self.assertIn("-MultipleInstances IgnoreNew", self.enroll)
        self.assertIn("$triggerCount -ne 0", self.enroll)
        self.assertIn("(A;;GRGX;;;NS)", self.enroll)
        self.assertIn("0x001200A9", self.enroll)
        self.assertIn("OWNER_DIAG_ENROLL_NETWORKSERVICE_RX_NOT_VERIFIED", self.enroll)
        self.assertIn("[Parameter(ParameterSetName = 'Revoke')][switch]$Revoke", self.enroll)
        for forbidden in (
            "Start-ScheduledTask", "Stop-ScheduledTask", "Stop-Process",
            "Unregister-ScheduledTask -TaskName $ownerTaskName",
            "Set-ScheduledTask", "GEMINI_API_KEY", "OpenSubtitles",
        ):
            self.assertNotIn(forbidden, self.enroll)

    def test_hostops_can_only_trigger_fixed_enrolled_task(self):
        self.assertIn(f"$taskName = '{CAPTURE}'", self.dispatch)
        self.assertIn("HOSTOPS_OWNER_CAPTURE_TRUSTED_RUNNER_REQUIRED", self.dispatch)
        self.assertIn("S-1-5-20", self.dispatch)
        self.assertIn("(GetTaskSid $task.Principal) -cne (GetTaskSid $ownerTask.Principal)", self.dispatch)
        self.assertIn("owner-p2-snapshot-once\\.ps1", self.dispatch)
        self.assertIn("Start-ScheduledTask -TaskName $taskName", self.dispatch)
        self.assertIn("HOSTOPS_OWNER_CAPTURE=FRESH_${receiptVersion}_RECEIPT_VERIFIED", self.dispatch)
        self.assertIn("HOSTOPS_OWNER_CAPTURE=TRIGGERED_NOT_VERIFIED", self.dispatch)
        self.assertIn("owner-diagnostic-snapshot.ps1", self.dispatch)
        for forbidden in (
            "Register-ScheduledTask", "Unregister-ScheduledTask", "Stop-ScheduledTask",
            "Disable-ScheduledTask", "Enable-ScheduledTask", "SetSecurityDescriptor",
            "Invoke-WebRequest", "Invoke-RestMethod", "LOCALAPPDATA", "Stop-Process",
            "GEMINI_API_KEY", "OpenSubtitles",
        ):
            self.assertNotIn(forbidden, self.dispatch)

    def test_hostops_exposes_every_fixed_selection_rejection_category(self):
        consumer = SNAPSHOT.read_text(encoding="utf-8")
        for category in (
            "bad_wire", "current_tv_or_torrserver_unavailable",
            "media_mismatch", "owner_policy", "enqueue",
            "http_format", "unknown",
        ):
            self.assertIn("'selection_rejected_" + category + "'", consumer)
        self.assertIn("HOSTOPS_OWNER_", consumer)
        self.assertIn("OWNER_PRIVATE_DATA=NOT_ACCESSED", consumer)


if __name__ == "__main__":
    unittest.main()
