"""Offline check that the owner-only stage cannot drift from exact #165 bytes."""
from __future__ import annotations

import hashlib
from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "hostops/setup/stage-owner-p3p4-v2.ps1"
SOURCE = REPO / "poc/p2-sub-discovery"
EXPECTED = {
    "owner_p3_p4_diagnostics.py": "a30bc451c4d8d0c38d9899773c9c33a9c0e0ba7e0bf98cd0f351c2f873877886",
    "p3_owner_state_wiring.py": "4bbafda8444413a2d7e907f10aa2cce904be03e8bcb1075f39e01fa4bd60e73a",
    "p3_p4_shared_https_route.py": "ab9deb57a7d568c1a5141a50a18afe5831577242d0e8e7723f569dec4ef27d2e",
    "p3_ingress_telemetry.py": "69f6711496575dd61ba82d3260d39726232b761bc395e22c10435d917c405b69",
}


class StageContractTest(unittest.TestCase):
    def test_runtime_byte_pins_are_exact(self):
        for name, expected in EXPECTED.items():
            with self.subTest(name=name):
                raw = (SOURCE / name).read_bytes()
                # Git core.autocrlf on Windows changes checkout bytes, but
                # staging reconstructs the canonical LF Git blob on disk.
                canonical = raw.replace(b"\r\n", b"\n")
                self.assertNotIn(b"\r", canonical)
                actual = hashlib.sha256(canonical).hexdigest()
                self.assertEqual(actual, expected)

    def test_script_manifest_matches_pinned_source(self):
        script = SCRIPT.read_text(encoding="utf-8")
        listed = dict(re.findall(
            r"'([a-z0-9_]+\.py)'\s*=\s*'([0-9a-f]{64})'", script))
        self.assertEqual(listed, EXPECTED)

    def test_windows_crlf_checkout_normalizes_to_reviewed_bytes(self):
        for name, expected in EXPECTED.items():
            with self.subTest(name=name):
                raw = (SOURCE / name).read_bytes().replace(b"\r\n", b"\n")
                self.assertNotIn(b"\r", raw)
                simulated_windows = raw.replace(b"\n", b"\r\n")
                self.assertEqual(
                    hashlib.sha256(simulated_windows.replace(b"\r\n", b"\n")).hexdigest(),
                    expected)

    def test_stage_does_not_change_running_owner_or_start_provider(self):
        script = SCRIPT.read_text(encoding="utf-8")
        for forbidden in (
            "Stop-ScheduledTask", "Start-ScheduledTask", "Stop-Process",
            "Start-Process", "Remove-Item", "Register-ScheduledTask",
            "Unregister-ScheduledTask", "Set-Acl", "icacls.exe",
            "Invoke-RestMethod", "Invoke-WebRequest", "adb.exe",
        ):
            self.assertNotIn(forbidden, script)
        self.assertIn("$root 'staged-releases'", script)
        self.assertIn("[IO.FileMode]::CreateNew", script)
        self.assertIn("Get-TTVCanonicalSourceBytes", script)
        self.assertIn("TTV_OWNER_V2_INSTALLED_RUNTIME=UNCHANGED", script)
        self.assertIn("TTV_OWNER_V2_ACTIVE_PROVIDER_JOB=UNPROVEN_V1", script)


if __name__ == "__main__":
    unittest.main()
