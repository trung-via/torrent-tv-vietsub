"""Offline P3-MOBILE setup-contract checks; never touch phones, server or TV."""
from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
ROADMAP = ROOT / "docs" / "ROADMAP.md"
GUIDE = ROOT / "docs" / "mobile-companion" / "ANDROID_PHONE_SETUP.md"
SCRIPT = Path(__file__).with_name("Inspect-TorrServerMobileReadiness.ps1")


class MobileSetupContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.roadmap = ROADMAP.read_text(encoding="utf-8")
        cls.guide = GUIDE.read_text(encoding="utf-8")
        cls.script = SCRIPT.read_text(encoding="utf-8")

    def test_roadmap_adds_independent_p3_mobile_gates(self):
        self.assertIn("| P3-MOBILE |", self.roadmap)
        for gate in ("G-MOBILE-INSTALL", "G-MOBILE-SERVER",
                     "G-MOBILE-ADD", "G-MOBILE-TV"):
            with self.subTest(gate=gate):
                self.assertIn(gate, self.roadmap)
                self.assertIn(gate, self.guide)

    def test_install_guide_reuses_pinned_official_omp(self):
        self.assertIn("spacesarmat/omp/releases/tag/v0.30.0", self.guide)
        self.assertIn("OMP-0.30.0-arm64.apk", self.guide)
        self.assertIn("OMP-0.30.0.apk", self.guide)
        self.assertIn("Android", self.guide)
        self.assertIn("6 chữ số", self.guide)
        self.assertIn("COMPATIBILITY_BLOCKED", self.guide)

    def test_phone_cannot_be_pretended_to_have_connected(self):
        for state in ("PHONE_INSTALL_NOT_RUN", "WINDOWS_SERVER_CONNECT_NOT_RUN",
                      "REDMI_PAIR_NOT_RUN"):
            self.assertIn(state, self.guide)
        self.assertIn("PHONE_NOT_VERIFIED", self.script)

    def test_windows_inspector_uses_only_read_only_net_inventory(self):
        for safe in ("Get-NetTCPConnection", "Get-NetIPAddress",
                     "Get-NetConnectionProfile", "ValidateRange(1, 65535)"):
            self.assertIn(safe, self.script)
        # Check actual command invocations, not words in documentation/comments.
        forbidden = r"(?im)^\s*(?:&\s*)?(?:Set-NetFirewall|New-NetFirewall|Remove-NetFirewall|Enable-NetFirewall|Start-Service|Stop-Service|Restart-Service|Set-Service|netsh|adb|curl|Invoke-WebRequest|Invoke-RestMethod|Start-Process|Invoke-Expression|Set-NetIP|New-NetIPAddress|Add-NetRoute)\b"
        self.assertIsNone(re.search(forbidden, self.script))

    def test_no_auto_server_or_remote_crawler(self):
        self.assertIn("MOBILE_PREFLIGHT_OWNER_LOCAL_ONLY_NO_CI", self.script)
        self.assertIn("LOCAL_LISTENER_OBSERVED_PHONE_NOT_VERIFIED", self.script)
        self.assertNotIn("https://api.opensubtitles", self.script)
        self.assertNotIn("GEMINI_API_KEY", self.script)
        self.assertNotIn("0.0.0.0:8090", self.script)

    def test_ip_disclosure_is_explicit_local_opt_in(self):
        self.assertIn("[switch]$ShowPrivateAddresses", self.script)
        self.assertIn("if ($ShowPrivateAddresses)", self.script)
        self.assertIn("NEVER_PASTE_THESE_ADDRESSES_IN_PUBLIC_GITHUB", self.script)


if __name__ == "__main__":
    unittest.main()
