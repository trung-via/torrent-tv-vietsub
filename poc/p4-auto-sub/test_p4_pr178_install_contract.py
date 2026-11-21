"""Safe source contract for exact PR178 staged APK HostOps deployment.

Does not touch Windows, Owner, ADB, TV or subtitle/provider systems.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
INSTALL = ROOT / "hostops/jobs/owner-p4-pr178-install.ps1"
PREFLIGHT = ROOT / "hostops/jobs/owner-p4-pr178-preflight.ps1"


class P4Pr178InstallContractTests(unittest.TestCase):
    def test_pinned_exact_ci_built_apk_and_private_stage(self):
        source = INSTALL.read_text("utf-8")
        self.assertIn("2fe92888364ec212c341f756da92a7c47e6c06f1", source)
        self.assertIn("478bfaf344cd55540576d8c951bc08e9db400965e8e0030237d5c2ca8b7663ce", source)
        self.assertIn("'_omp-fast-cache\\p4-flat-staged\\'", source)
        self.assertIn("schema=TTV-P4-FLAT-APK-STAGE-V1", source)
        self.assertIn("[Security.Principal.WindowsIdentity]::GetCurrent().User.Value", source)
        self.assertIn("$PSVersionTable.PSVersion.Major -lt 7", source)

    def test_off_and_idle_checked_again_immediately_before_single_install(self):
        source = INSTALL.read_text("utf-8")
        self.assertEqual(source.count("Assert-ViewerOffAndOwnerIdle"), 3)
        self.assertIn("FRESH_OFF", source)
        self.assertIn("$r.p2.inflight_count -ne 0", source)
        self.assertIn("$r.p2.pending_events -ne 0", source)
        self.assertEqual(source.count("@('install', '-r', $apk)"), 1)
        self.assertLess(source.rindex("Assert-ViewerOffAndOwnerIdle"),
                        source.index("@('install', '-r', $apk)"))
        self.assertNotIn("'uninstall'", source)
        self.assertNotIn("'pm', 'clear'", source)
        self.assertNotIn("'install', '-d'", source)
        self.assertIn("P4_PR178_INSTALL_POST_READBACK_SHA_MISMATCH_NO_REINSTALL", source)

    def test_read_only_preflight_distinct_from_install(self):
        preflight = PREFLIGHT.read_text("utf-8")
        self.assertIn("-PreflightOnly", preflight)
        self.assertNotIn("@('install'", preflight)
        source = INSTALL.read_text("utf-8")
        self.assertLess(source.index("if ($PreflightOnly) {"),
                        source.index("@('install', '-r', $apk)"))
        self.assertIn("P4_PR178_PREFLIGHT=PASS_NO_TV_WRITE", source)


if __name__ == "__main__":
    unittest.main()
