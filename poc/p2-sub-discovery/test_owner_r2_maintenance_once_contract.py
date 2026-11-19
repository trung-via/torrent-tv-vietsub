"""Conservative one-shot Owner interactive upgrade with exact rollback."""

from __future__ import annotations

from pathlib import Path
import hashlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hostops/setup/owner-r2-maintenance-once.ps1"
APPLIER = ROOT / "hostops/setup/owner-r2-release-offline-apply.ps1"


class OwnerR2MaintenanceOnceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text(encoding="utf-8")

    def test_pinned_exact_applier_source(self):
        pin = re.search(r"\$applierSHA\s*=\s*'([0-9a-f]{64})'", self.source)
        self.assertIsNotNone(pin)
        # GitHub checkout is allowed to materialize .ps1 as CRLF even on
        # Linux; raw.githubusercontent serves the exact LF Git blob.
        checkout = APPLIER.read_bytes()
        self.assertNotIn(b"\r", checkout.replace(b"\r\n", b""))
        canonical = checkout.replace(b"\r\n", b"\n")
        self.assertEqual(pin.group(1), hashlib.sha256(canonical).hexdigest())
        self.assertIn("87003ddd1ffa2b2ab2a7a05f95292f8d519a43cc", self.source)

    def test_no_silent_apply_and_no_service_context(self):
        for required in (
            "[switch]$ApplyR2",
            "if (-not $ApplyR2)",
            "INTERACTIVE_OWNER_REQUIRED",
            "OWNER_TASK_IDENTITY_DRIFT",
            "OWNER_R2_MAINTENANCE=INSPECT_ONLY_OWNER_UNCHANGED",
            "NoOpenWork",
            "UNCERTAIN_P2_INFLIGHT",
            "ACTIVE_P2_LOCK",
            "PENDING_EVENTS",
            "OFFLINE_APPLY_FAILED_OWNER_DISABLED",
        ):
            self.assertIn(required, self.source)
        for forbidden in (
            "Remove-ScheduledTask", "Unregister-ScheduledTask",
            "Register-ScheduledTask", "adb.exe", "Gemini", "OpenSubtitles",
            "Invoke-RestMethod", "icacls.exe",
        ):
            self.assertNotIn(forbidden, self.source)

    def test_disabled_resume_only_after_exact_preapply_hold(self):
        for required in (
            "[switch]$ResumeAfterStoppedTaskHold",
            "RESUME_REQUIRES_APPLY_R2",
            "RESUME_REQUIRES_DISABLED_TASK",
            "RESUME_AMBIGUOUS_R2_BACKUP_EXISTS",
            "OWNER_TASK_NOT_RUNNING_USE_EXPLICIT_RESUME_FOR_DISABLED_HOLD",
            "StopOwnerForMaintenance",
        ):
            self.assertIn(required, self.source)
        self.assertLess(
            self.source.index("RESUME_AMBIGUOUS_R2_BACKUP_EXISTS"),
            self.source.index("StopOwnerForMaintenance\nNoOpenWork"),
        )

    def test_residual_python_termination_is_owner_pinned_and_p2_idle(self):
        section = self.source.split("function StopVerifiedResidualOwnerWorkers {", 1)[1].split(
            "\nfunction StopOwnerForMaintenance", 1
        )[0]
        for required in (
            "RESIDUAL_STOP_REQUIRES_DISABLED_TASK",
            "NoOpenWork",
            "RESIDUAL_WORKER_COUNT_UNEXPECTED",
            "owner_p3_p4_entrypoint.py",
            "owner_session_bridge.py",
            "RESIDUAL_WORKER_PATH_OR_CREATION_UNVERIFIED",
            "RESIDUAL_WORKER_OWNER_UNVERIFIED",
            "RESIDUAL_TASK_STATE_CHANGED",
            "RESIDUAL_WORKER_IDENTITY_CHANGED",
            "RESIDUAL_WORKER_OWNER_CHANGED",
            "Invoke-CimMethod -InputObject $live -MethodName GetOwnerSid",
            "Stop-Process -Id ([int]$worker.ProcessId) -Force",
            "OWNER_R2_RESIDUAL_WORKERS_STOPPED=",
        ):
            self.assertIn(required, section)
        self.assertEqual(section.count("Stop-Process"), 1)
        self.assertLess(
            section.index("RESIDUAL_WORKER_PATH_OR_CREATION_UNVERIFIED"),
            section.index("Stop-Process -Id"),
        )
        self.assertLess(
            section.index("RESIDUAL_WORKER_OWNER_CHANGED"),
            section.index("Stop-Process -Id"),
        )
        self.assertLess(
            section.index("NoOpenWork"),
            section.index("Stop-Process -Id"),
        )

    def test_recovery_on_failed_new_owner_heartbeat(self):
        for required in (
            "StopOwnerForMaintenance",
            "HealthyNewOwner",
            "Invoke-CimMethod -InputObject $worker -MethodName GetOwnerSid",
            "StartOwnerAfterMaintenance",
            "Get-ScheduledTask -TaskName $taskName",
            "Disable-ScheduledTask -TaskName $taskName",
            "Stop-ScheduledTask -TaskName $taskName",
            "Enable-ScheduledTask -TaskName $taskName",
            "Start-ScheduledTask -TaskName $taskName",
            "-File $applier -ApplyOffline",
            "-File $applier -RollbackOffline -BackupId $backupId",
            "NEW_OWNER_UNHEALTHY_ROLLBACK_NOT_VERIFIED_TASK_DISABLED",
            "R2_STARTUP_FAILED_OLD_OWNER_RECOVERED",
            "OWNER_R2_MAINTENANCE=R2_ACTIVE_FRESH_OWNER_HEARTBEAT",
            "OWNER_R2_REDMi=NOT_VERIFIED",
        ):
            self.assertIn(required, self.source)
        self.assertLess(
            self.source.index("NoOpenWork\n$oldPid"),
            self.source.index("StopOwnerForMaintenance\nNoOpenWork"),
        )
        self.assertLess(
            self.source.index("OWNER_R2_STAGE_INSPECTION_FAILED"),
            self.source.index("StopOwnerForMaintenance\nNoOpenWork"),
        )


if __name__ == "__main__":
    unittest.main()
