"""Source and optional Windows parser contract for P2-F3 offline upgrade.

No real Owner task, account secret, provider, or Windows state is touched.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "hostops/setup/p2-offline-worker-upgrade.ps1"
WORKER = ROOT / "poc/p2-aisub/automatic_lean120_worker.py"


class P2OfflineUpgradeContractTests(unittest.TestCase):
    def test_exact_reviewed_worker_source_hash_is_pinned(self):
        content = SCRIPT.read_text(encoding="utf-8")
        # Git checkout can materialize CRLF on Windows; the upgrade script
        # normalizes to canonical LF before verifying the reviewed blob.
        worker = WORKER.read_text(encoding="utf-8").replace("\r\n", "\n")
        expected = hashlib.sha256(worker.encode("utf-8")).hexdigest()
        # F3 is an older one-time installer. New concurrent per-film source
        # requires a new reviewed deployment, never a silent F3 pin rewrite.
        self.assertIn(
            "$newSha = 'd8744716ef9d9aa2b0518245310cb8b6235213fa7afb5423d70e521efd2b07a0'",
            content)
        self.assertNotIn("$newSha = '" + expected + "'", content)
        self.assertIn("P2_F3_REVIEWED_WORKER_HASH_MISMATCH", content)
        self.assertIn("P2_F3_INSTALLED_HASH_MISMATCH_BACKUP_RETAINED", content)

    def test_no_owner_provider_or_batch_mutations(self):
        content = SCRIPT.read_text(encoding="utf-8")
        for prohibited in (
            "Start-ScheduledTask", "Stop-ScheduledTask", "Enable-ScheduledTask",
            "Disable-ScheduledTask", "Remove-Item", "Invoke-WebRequest",
            "Invoke-RestMethod", "Invoke-Expression", "agy --model",
        ):
            self.assertNotIn(prohibited, content)
        for required in (
            "P2_F3_RESULT=INSPECT_ONLY_NO_CHANGES",
            "P2_F3_OWNER_NOT_QUIESCENT",
            "P2_F3_TASK_IDENTITY_MISMATCH",
            "P2_F3_INSTALLED_GATEWAY_DEPENDENCIES_NOT_READY",
            "P2_F3_UNCERTAIN_BATCH=UNCHANGED",
        ):
            self.assertIn(required, content)

    def test_original_backup_verified_and_rollback_kept_fail_closed(self):
        content = SCRIPT.read_text(encoding="utf-8")
        for required in (
            "P2_F3_BACKUP_VERIFY_FAILED",
            "[IO.File]::Replace(",
            "P2_F3_ROLLBACK_AFTER_QUARANTINE_REFUSED",
            "P2_F3_ORIGINAL_BACKUP_BYTES_MISMATCH",
            "P2_F3_RESULT=ROLLBACK_HASH_VERIFIED_OWNER_STILL_DISABLED",
        ):
            self.assertIn(required, content)

    @unittest.skipUnless(shutil.which("pwsh"), "PowerShell 7 not installed")
    def test_powershell_parser_accepts_exact_script(self):
        escaped = str(SCRIPT).replace("'", "''")
        inspect = (
            "$tokens=$null; $errors=$null; "
            "[System.Management.Automation.Language.Parser]::ParseFile("
            f"'{escaped}',[ref]$tokens,[ref]$errors) | Out-Null; "
            "if ($errors.Count -gt 0) { $errors | Out-String | Write-Error; exit 1 }"
        )
        process = subprocess.run(
            ["pwsh", "-NoProfile", "-NonInteractive", "-Command", inspect],
            text=True, capture_output=True, check=False, timeout=20,
        )
        self.assertEqual(process.returncode, 0, process.stderr)


if __name__ == "__main__":
    unittest.main()
