"""Source contract for Owner Task enrollment and one-shot HostOps dispatch.

These tests never register/run a Windows Task or access a real Owner profile.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
ENROLL = ROOT / "hostops/setup/enroll-owner-p2-quarantine-task.ps1"
DISPATCH = ROOT / "hostops/jobs/owner-p2-quarantine-dispatch.ps1"
HELPER = ROOT / "hostops/setup/owner-p2-quarantine-once.ps1"
KNOWN_SOURCE_COMMIT = "50f282a484dd6ad6104587a914b753e1ed467972"
KNOWN_HELPER_SHA256 = "a21ff672e15db0b2efca20909ae88b35957193f99a52a83a3000dfa65f3d7cb3"
OWNER_TASK = "TorrentTV-Vietsub-OwnerAgent"
MAINTENANCE_TASK = "TorrentTV-Vietsub-P2-Quarantine-Once"


class HostOpsOwnerTaskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.enroll = ENROLL.read_text(encoding="utf-8")
        cls.dispatch = DISPATCH.read_text(encoding="utf-8")

    def test_owner_helper_is_immutably_pinned(self):
        blob = HELPER.read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(blob).hexdigest(), KNOWN_HELPER_SHA256)
        self.assertIn(KNOWN_SOURCE_COMMIT, self.enroll)
        self.assertIn(KNOWN_HELPER_SHA256, self.enroll)
        self.assertIn("OWNER_P2_ENROLL_IMMUTABLE_SOURCE_HASH_MISMATCH", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_INSTALLED_HELPER_DRIFT", self.enroll)

    def test_new_task_does_not_repoint_original(self):
        self.assertIn(f"$ownerTaskName = '{OWNER_TASK}'", self.enroll)
        self.assertIn(f"$taskName = '{MAINTENANCE_TASK}'", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_ORIGINAL_TASK_IDENTITY_MISMATCH", self.enroll)
        self.assertIn("Test-TTVOwnerTaskPrincipal", self.enroll)
        self.assertIn("Get-TTVOwnerTaskActionState", self.enroll)
        self.assertIn("New-ScheduledTask -Action", self.enroll)
        self.assertIn("-LogonType Interactive -RunLevel Limited", self.enroll)
        self.assertIn("-MultipleInstances IgnoreNew", self.enroll)
        self.assertIn("$triggerCount = if ($null -eq $Task -or $null -eq $Task.Triggers)", self.enroll)
        self.assertIn("$triggerCount -ne 0", self.enroll)
        self.assertIn("-ExecutionTimeLimit", self.enroll)
        self.assertNotIn("New-ScheduledTaskTrigger", self.enroll)
        self.assertNotIn("-LogonType Password", self.enroll)
        self.assertNotIn("Stop-ScheduledTask", self.enroll)
        self.assertNotIn("Enable-ScheduledTask", self.enroll)
        self.assertNotIn("Start-ScheduledTask", self.enroll)

    def test_service_receives_task_read_execute_only(self):
        self.assertIn("$identity = [Security.Principal.WindowsIdentity]::GetCurrent()", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_INTERACTIVE_OWNER_REQUIRED", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_WRONG_SIGNED_IN_OWNER", self.enroll)
        self.assertIn("(A;;GRGX;;;NS)", self.enroll)
        self.assertIn("-1610612736", self.enroll)
        self.assertIn("SetSecurityDescriptor", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_NETWORKSERVICE_RX_NOT_VERIFIED", self.enroll)
        self.assertIn("'Maintenance'", self.enroll)
        self.assertIn("/inheritance:r /grant:r", self.enroll)
        self.assertNotIn("LOCALAPPDATA\\TorrentTVVietsub\\OwnerBridge\\secrets", self.enroll)

    def test_revoke_is_scoped_and_does_not_delete_owner_agent(self):
        self.assertIn("param([switch]$Revoke)", self.enroll)
        self.assertIn("AssertDedicatedTask $existingForRevoke", self.enroll)
        self.assertIn("Disable-ScheduledTask -TaskName $taskName", self.enroll)
        self.assertIn("Unregister-ScheduledTask -TaskName $taskName", self.enroll)
        self.assertNotIn("Unregister-ScheduledTask -TaskName $ownerTaskName", self.enroll)
        self.assertIn("OWNER_P2_ENROLL_ORIGINAL_TASK=NOT_MUTATED", self.enroll)

    def test_dispatch_is_trusted_single_fire_only(self):
        for guard in (
            "HOSTOPS_P2_QUARANTINE_TRUSTED_NETWORKSERVICE_REQUIRED",
            "S-1-5-20", "HOSTOPS_P2_QUARANTINE_ORIGINAL_OWNER_TASK_NOT_RUNNING",
            "HOSTOPS_P2_QUARANTINE_DEDICATED_TASK_NOT_ACCESSIBLE",
            "HOSTOPS_P2_QUARANTINE_OWNER_PRINCIPAL_MISMATCH",
            "HOSTOPS_P2_QUARANTINE_TASK_IDENTITY_DRIFT",
            "HOSTOPS_P2_QUARANTINE_FIXED_ACTION_DRIFT",
            "HOSTOPS_P2_QUARANTINE_ONE_SHOT_ALREADY_ATTEMPTED",
        ):
            self.assertIn(guard, self.dispatch)
        self.assertIn(f"$taskName = '{MAINTENANCE_TASK}'", self.dispatch)
        self.assertIn("Get-ScheduledTaskInfo -TaskName $taskName", self.dispatch)
        self.assertIn("$triggerCount = if ($null -eq $task.Triggers)", self.dispatch)
        self.assertIn("if ($history.LastRunTime -gt", self.dispatch)
        self.assertIn("Start-ScheduledTask -TaskName $taskName", self.dispatch)
        self.assertIn("TRIGGERED_NOT_VERIFIED", self.dispatch)
        for prohibited in (
            "Register-ScheduledTask", "Unregister-ScheduledTask", "Stop-ScheduledTask",
            "Disable-ScheduledTask", "Enable-ScheduledTask", "SetSecurityDescriptor",
            "Invoke-WebRequest", "Invoke-RestMethod", "LOCALAPPDATA", "acy ", "agy ",
        ):
            self.assertNotIn(prohibited, self.dispatch)


if __name__ == "__main__":
    unittest.main()
