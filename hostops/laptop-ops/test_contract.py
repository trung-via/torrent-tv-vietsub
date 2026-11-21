"""Source-only laptop HostOps contract. No Windows, network, Owner or provider."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "hostops/laptop-ops/manifests/current.json"
ALLOWED = {"diagnostics", "owner-maintenance", "development",
           "app-maintenance", "device-lan"}


class LaptopOpsContractTests(unittest.TestCase):
    def test_only_source_pinned_routine_operation(self):
        raw = MANIFEST.read_bytes()
        self.assertLess(len(raw), 8192)
        manifest = json.loads(raw)
        self.assertEqual(set(manifest), {
            "schema", "operation", "risk", "category", "script_path",
            "script_sha256", "arguments",
        })
        self.assertEqual(manifest["schema"], "TTV-LAPTOP-HOSTOPS-OPERATION-V1")
        self.assertEqual(manifest["risk"], "ROUTINE")
        self.assertIn(manifest["category"], ALLOWED)
        self.assertRegex(manifest["operation"], r"^[a-z][a-z0-9-]{2,60}$")
        self.assertRegex(manifest["script_path"],
                         r"^hostops/laptop-ops/operations/[a-z][a-z0-9-]*\.ps1$")
        self.assertRegex(manifest["script_sha256"], r"^[0-9a-f]{64}$")
        self.assertIsInstance(manifest["arguments"], list)
        self.assertLessEqual(len(manifest["arguments"]), 8)
        for argument in manifest["arguments"]:
            self.assertRegex(argument, r"^-[A-Za-z][A-Za-z0-9]{0,39}$")
        script = (ROOT / manifest["script_path"]).resolve(strict=True)
        self.assertEqual(hashlib.sha256(script.read_bytes()).hexdigest(),
                         manifest["script_sha256"])

    def test_no_arbitrary_issues_command_or_admin_task(self):
        helper = (ROOT / "hostops/setup/owner-laptop-ops-helper.ps1").read_text()
        dispatcher = (ROOT / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        enrollment = (ROOT / "hostops/setup/enroll-owner-laptop-ops.ps1").read_text()
        self.assertIn("TTV-LAPTOP-HOSTOPS-REQUEST-V1", helper)
        self.assertIn("TTV-LAPTOP-HOSTOPS-RECEIPT-V1", dispatcher)
        self.assertIn("$manifest.risk -cne 'ROUTINE'", helper)
        self.assertIn("$manifest.risk -cne 'ROUTINE'", dispatcher)
        self.assertIn("-RunLevel Limited", enrollment)
        self.assertNotIn("-RunLevel Highest", enrollment)
        self.assertNotIn("Invoke-Expression", helper + dispatcher + enrollment)
        self.assertIn("FAILED_NO_RETRY", helper)
        self.assertIn("FAILED_NO_RETRY", dispatcher)

    def test_first_operation_installer_pin(self):
        operation = (ROOT / "hostops/laptop-ops/operations/owner-full-diagnostics-install.ps1").read_text()
        self.assertIn("5bb0dfc114e0f8702ce86cb768a387a521e94fee", operation)
        self.assertIn("430317baf5574d9dda186684cad4ebd95cfcf3d5e839cc6799af1c3ac50e3361", operation)
        self.assertRegex(operation, re.compile(r"(?m)^\s*& pwsh .* -Apply$"))


if __name__ == "__main__":
    unittest.main()
