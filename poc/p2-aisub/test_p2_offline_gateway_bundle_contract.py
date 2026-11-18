"""P2-F4 source and Windows syntax gates; never accesses an Owner installation."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hostops/setup/p2-offline-gateway-bundle-upgrade.ps1"
MODULES = (
    "automatic_lean120_worker.py",
    "assumed_source_handoff.py",
    "cue_pipeline.py",
    "lean120_api.py",
    "translator_gateway.py",
    "progressive_handoff.py",
    "translator_profile.json",
    "lan_revision_feed.py",
    "revision_delivery.py",
)


class P2OfflineGatewayBundleContract(unittest.TestCase):
    def test_reviewed_module_hashes_pinned_and_closure_complete(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for name in MODULES:
            source = (ROOT / "poc/p2-aisub" / name).read_text(encoding="utf-8")
            digest = hashlib.sha256(source.replace("\r\n", "\n").encode()).hexdigest()
            self.assertIn(f"'{name}' = '{digest}'", script)
        # A missed direct import here creates a mixed runtime on Windows.
        for filename in MODULES:
            if not filename.endswith(".py"):
                continue
            contents = (ROOT / "poc/p2-aisub" / filename).read_text(encoding="utf-8")
            for module in re.findall(r"^from ([a-z_]+) import ", contents, re.MULTILINE):
                if (ROOT / "poc/p2-aisub" / f"{module}.py").exists():
                    self.assertIn(f"{module}.py", MODULES, (filename, module))

    def test_inspect_only_and_quiescence_are_explicit(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for expected in (
            "P2_F4_RESULT=INSPECT_ONLY_NO_CHANGES",
            "P2_F4_OWNER_NOT_QUIESCENT",
            "P2_F4_TASK_IDENTITY_MISMATCH",
            "P2_F4_EXPECTED_INVENTORY_HASH_MISMATCH",
            "P2_F4_INSTALLED_INVENTORY_SHA256=",
            "P2_F4_UNCERTAIN_BATCH=UNCHANGED",
            "P2_F4_INTERACTIVE_OWNER_REQUIRED",
        ):
            self.assertIn(expected, script)
        for prohibited in (
            "Start-ScheduledTask", "Stop-ScheduledTask", "Disable-ScheduledTask",
            "Enable-ScheduledTask", "Invoke-WebRequest", "Invoke-RestMethod",
            "Invoke-Expression", "agy --model", "Remove-Item",
        ):
            self.assertNotIn(prohibited, script)

    def test_backup_missing_file_and_partial_restore_contract(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for expected in (
            "P2_F4_BACKUP_FOLDER=", "P2_F4_BACKUP_CORRUPT",
            "P2_F4_INSTALL_INTERRUPTED_KEEP_OWNER_DISABLED_RESTORE_OFFLINE",
            "P2_F4_LEGACY_ROLLBACK_AFTER_QUARANTINE_REFUSED",
            "P2_F4_RESULT=ORIGINAL_BUNDLE_RESTORED_OWNER_STILL_DISABLED",
            "[IO.File]::Move($staged, $target)",
            "[IO.File]::Delete($target)",
            "if ($row.present)",
        ):
            self.assertIn(expected, script)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 is absent")
    def test_windows_powershell_parser_accepts_exact_script(self):
        escaped = str(SCRIPT).replace("'", "''")
        command = (
            "$tokens=$null; $errors=$null; "
            "[System.Management.Automation.Language.Parser]::ParseFile("
            f"'{escaped}',[ref]$tokens,[ref]$errors) | Out-Null; "
            "if ($errors.Count -gt 0) { $errors | Out-String | Write-Error; exit 1 }"
        )
        result = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-Command", command],
            check=False, capture_output=True, text=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
