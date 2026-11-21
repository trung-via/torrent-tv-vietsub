"""Offline checks for the read-only Owner P2 diagnostic handoff."""

import hashlib
import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OP = ROOT / "hostops/laptop-ops/operations/owner-p2-fresh-inspect-v2.ps1"
READER = ROOT / "hostops/jobs/owner-p2-fresh-inspect-v2-readonly.ps1"
MANIFEST = ROOT / "hostops/laptop-ops/manifests/current.json"


class FreshInspectV2Contract(unittest.TestCase):
    def test_safe_manifest_pins_exact_owner_diagnostic_source(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["operation"], "owner-p2-text-qa-status-v1")
        self.assertEqual(manifest["risk"], "ROUTINE")
        self.assertEqual(manifest["category"], "diagnostics")
        self.assertEqual(manifest["arguments"], [])
        checked_in_bytes = subprocess.run(
            ["git", "show", "HEAD:hostops/laptop-ops/operations/owner-p2-text-qa-status-v1.ps1"],
            cwd=ROOT, capture_output=True, check=True,
        ).stdout
        self.assertEqual(
            manifest["script_sha256"], hashlib.sha256(checked_in_bytes).hexdigest()
        )

    def test_operation_is_bounded_read_only(self):
        source = OP.read_text(encoding="utf-8")
        for forbidden in (
            "Move-Item", "Remove-Item", "Stop-ScheduledTask",
            "Start-ScheduledTask", "Disable-ScheduledTask", "Enable-ScheduledTask",
            "Invoke-RestMethod", "Invoke-WebRequest", "run_local_translation",
        ):
            self.assertNotIn(forbidden, source)
        self.assertIn("P2_FRESH_INSPECT_V2=SANITIZED_RECEIPT_WRITTEN", source)
        self.assertIn("P2_FRESH_INSPECT_V2=RECEIPT_WRITE_FAILED", source)
        self.assertIn("$result.status = 'OBSERVED'", source)
        self.assertIn("$result.status = 'HOLD'", source)

    def test_reader_rejects_stale_or_wrong_runner_and_is_read_only(self):
        source = READER.read_text(encoding="utf-8")
        self.assertIn("P2_FRESH_V2_READER_STALE", source)
        self.assertIn("S-1-5-20", source)
        self.assertIn("'OBSERVED','HOLD'", source)
        self.assertNotIn("$env:LOCALAPPDATA", source)
        self.assertNotIn("Set-Content", source)

    def test_clear_selects_one_marker_not_all_jobs(self):
        source = (ROOT / "hostops/laptop-ops/operations/owner-p2-fresh-start.ps1").read_text()
        self.assertIn("'Running','Ready'", source)
        self.assertIn("$targetCandidates.Count -ne 1", source)
        self.assertIn("$candidateDoc.marker_sha256 -ceq $expectedOriginalMarkerSha", source)
        self.assertIn("if ($wasRunning)", source)
        self.assertIn("$result", OP.read_text())
        self.assertIn("$uninspectable.Count -eq 0", source)


if __name__ == "__main__":
    unittest.main()
