"""Static contract for a never-automatic, owner-only R2 offline file transition."""

from __future__ import annotations

import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hostops/setup/owner-r2-release-offline-apply.ps1"
MANIFEST = ROOT / "hostops/releases/owner-r2-stage-v1.json"


class OwnerR2ReleaseOfflineApplyContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text(encoding="utf-8")
        cls.manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))

    def test_script_matches_every_sha_pinned_staged_module(self):
        source = self.script.split("$files = [ordered]@{", 1)[1].split("\n}", 1)[0]
        rows = dict(re.findall(
            r"'(poc/(?:p2-aisub|p2-sub-discovery)/[a-z0-9_]+\.py)'\s*=\s*'([0-9a-f]{64})'",
            source,
        ))
        self.assertEqual(len(rows), 14)
        self.assertEqual(rows, {
            entry["path"]: entry["sha256"]
            for entry in self.manifest["files"]
        })
        self.assertEqual(self.manifest["mode"], "STAGE_ONLY")
        self.assertIn("owner-r2-rolling-175-90b8c18f343f", self.script)
        self.assertIn("90b8c18f343fc37bbfcee8752eec9d6890490d78", self.script)

    def test_inspect_default_and_offline_stop_required(self):
        for forbidden in (
            "Stop-ScheduledTask", "Start-ScheduledTask", "Stop-Process",
            "Start-Process", "Enable-ScheduledTask", "Disable-ScheduledTask",
            "Register-ScheduledTask", "Invoke-WebRequest", "Invoke-RestMethod",
            "adb.exe", "gemini", "opensubtitles.org",
        ):
            self.assertNotIn(forbidden, self.script)
        for required in (
            "[CmdletBinding(DefaultParameterSetName = 'Inspect')]",
            "[Parameter(ParameterSetName = 'Apply')][switch]$ApplyOffline",
            "if (-not $ApplyOffline -and -not $RollbackOffline)",
            "OWNER_R2_OFFLINE=READ_ONLY_INSPECT_PASS",
            "OWNER_TASK_NOT_DISABLED", "OWNER_PROCESS_STILL_RUNNING",
            "PENDING_OWNER_EVENTS", "P2_UNCERTAIN_INFLIGHT",
            "P2_ACTIVE_LOCK", "STAGED_SOURCE_BYTES_DRIFT",
            "BASELINE_CHANGED_DURING_APPLY",
        ):
            self.assertIn(required, self.script)

    def test_private_recovery_and_noreplay(self):
        for required in (
            "function AtomicReplace",
            "[IO.File]::Replace($source,$destination,$displaced)",
            "TTV-OWNER-R2-ROLLBACK-V1",
            "owner-r2-", "PRIVATE_BACKUP_HASH_MISMATCH",
            "$attempted.Add($rel)",
            "OWNER_R2_APPLY=ERROR_ATTEMPTING_ROLLBACK",
            "ROLLBACK_NOT_VERIFIED_MANUAL_RECOVERY",
            "APPLY_FAILED_ROLLBACK_VERIFIED",
            "OWNER_R2_APPLY=INSTALLED_HASH_VERIFIED_OWNER_STOPPED",
            "OWNER_R2_OWNER_RESTART=NOT_RUN",
            "OWNER_R2_PROVIDER_TV=NOT_RUN",
            "OWNER_R2_P2_CHECKPOINTS=NOT_CHANGED",
        ):
            self.assertIn(required, self.script)
        self.assertLess(
            self.script.index("$attempted.Add($rel)"),
            self.script.index("AtomicReplace $temporary $destination 'r2-original'"),
        )
        self.assertNotIn("[IO.File]::Replace($source,$destination,$null)", self.script)

    def test_owner_only_rollback_requires_original_backup_and_exact_r2(self):
        for required in (
            "[Parameter(ParameterSetName = 'Rollback')][switch]$RollbackOffline",
            "[ValidatePattern('^owner-r2-[0-9a-f]{32}$')]",
            "if ($RollbackOffline)",
            "ROLLBACK_LEDGER_SCHEMA_INVALID",
            "ROLLBACK_INSTALLED_R2_DRIFT",
            "ROLLBACK_PRIVATE_BACKUP_DRIFT",
            "ROLLBACK_INSTALLED_R2_CHANGED",
            "ROLLBACK_ORIGINAL_HASH_NOT_RESTORED",
            "OWNER_R2_ROLLBACK=ORIGINAL_BYTES_RESTORED_OWNER_STOPPED",
        ):
            self.assertIn(required, self.script)
        preflight = self.script.split("if ($RollbackOffline) {", 1)[1]
        self.assertLess(
            preflight.index("ROLLBACK_INSTALLED_R2_DRIFT"),
            preflight.index("foreach ($rel in @($files.Keys)[($files.Count-1)..0])"),
        )
        self.assertLess(
            self.script.index("AssertOwnerStopped\nAssertNoOpenP2Work $root"),
            self.script.index("if ($RollbackOffline) {"),
        )


if __name__ == "__main__":
    unittest.main()
