"""F6 prevents F4/F5's old Gemini bootstrap from killing the Owner."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hostops/setup/p2-f6-owner-bootstrap-compat-upgrade.ps1"
SUB = ROOT / "poc/p2-sub-discovery"
MODULES = (
    "automatic_vietsub_flow.py",
    "owner_vietsub_pipeline.py",
    "start-owner-session-agent.ps1",
)


class OwnerBootstrapCompatContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.script = SCRIPT.read_text(encoding="utf-8")

    def test_all_three_bootstrap_files_are_pinned_to_exact_bytes(self):
        for name in MODULES:
            with self.subTest(name=name):
                sha = hashlib.sha256((SUB / name).read_bytes()).hexdigest()
                self.assertRegex(
                    self.script,
                    re.escape("'" + name + "' = @{")
                    + r"\s*new = '" + sha + "'",
                )

    def test_legacy_base_is_recognized_but_unknown_source_is_refused(self):
        self.assertEqual(self.script.count("old = '"), 3)
        self.assertIn("P2_F6_INSTALLED_SOURCE_UNRECOGNIZED_HOLD", self.script)
        self.assertIn("P2_F6_SOURCE_PIN_MISMATCH", self.script)
        self.assertIn("P2_F6_DEPENDENCY_DRIFT_HOLD", self.script)

    def test_bootstrap_no_longer_requires_billed_gemini_api_key(self):
        flow = (SUB / "automatic_vietsub_flow.py").read_text(encoding="utf-8")
        launcher = (SUB / "start-owner-session-agent.ps1").read_text(encoding="utf-8")
        pipeline = (SUB / "owner_vietsub_pipeline.py").read_text(encoding="utf-8")
        self.assertNotIn('os.environ.get("GEMINI_API_KEY"', flow)
        self.assertIn("provider_enabled(profile.provider)", flow)
        self.assertNotIn("Get-OwnerSecret (Join-Path $secrets 'gemini.dpapi')", launcher)
        self.assertIn("verify_owner_translation_provider", pipeline)

    def test_single_owner_quiescence_and_uncertain_batch_preserved(self):
        for fragment in (
            "P2_F6_INTERACTIVE_OWNER_REQUIRED",
            "P2_F6_SERVICE_OWNER_FORBIDDEN",
            "P2_F6_TASK_OWNER_MISMATCH",
            "P2_F6_TASK_MUST_BE_DISABLED",
            "P2_F6_OWNER_NOT_QUIESCENT",
            "P2_F6_QUARANTINED_BATCH=UNTOUCHED_NO_RETRY",
        ):
            self.assertIn(fragment, self.script)
        for forbidden in ("Start-ScheduledTask", "Remove-ScheduledTask",
                          "Start-Process", "Invoke-WebRequest", "Invoke-RestMethod"):
            self.assertNotIn(forbidden, self.script)

    def test_installer_has_backup_atomic_replace_and_rollback(self):
        self.assertIn("P2_F6_BACKUP_CREATED=YES", self.script)
        self.assertIn("[IO.File]::Replace", self.script)
        self.assertIn("P2_F6_ROLLBACK=", self.script)
        self.assertIn("P2_F6_INSTALL_FAILED_KEEP_TASK_DISABLED", self.script)


if __name__ == "__main__":
    unittest.main()
