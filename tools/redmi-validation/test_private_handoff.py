"""Static safeguards for the real-APK private preflight; no TV/Windows access."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "tools/redmi-validation/verify-g1p2-arm32.ps1").read_text(encoding="utf-8")
CHECKSUM = "c2f71cb8c8accc11821396d20a96490b0a129344cb329e1c5e6d9c3bf2f7b75f"
RUN = "42331308161"


class PrivateHandoffContract(unittest.TestCase):
    def test_exact_provenance(self):
        self.assertIn(RUN, SCRIPT)
        self.assertIn(CHECKSUM, SCRIPT)
        self.assertIn("app-armeabi-v7a-debug.apk", SCRIPT)
        self.assertIn("SHA256SUMS-G1P2.txt", SCRIPT)

    def test_default_is_read_only_inspect(self):
        self.assertIn("[string]$Mode = 'Inspect'", SCRIPT)
        self.assertIn("ValidateSet('Inspect','Stage','CompareInstalled')", SCRIPT)

    def test_no_adb_install_delete_or_network_upload(self):
        # Comment text may explain forbidden actions; inspect executable source.
        active = "\n".join(
            line for line in SCRIPT.splitlines()
            if not line.lstrip().startswith("#")
        ).lower()
        for prohibited in ("adb install", "pm clear", "adb push", "adb uninstall",
                           "Invoke-WebRequest", "Invoke-RestMethod", "Start-Process",
                           "curl.exe", "gh release", "gh api"):
            self.assertNotIn(prohibited.lower(), active)

    def test_copy_only_when_stage_selected(self):
        self.assertIn("if ($Mode -ceq 'Stage')", SCRIPT)
        self.assertIn("Copy-Item -LiteralPath $SourceApk -Destination $target", SCRIPT)
        self.assertIn("PRIVATE_COPY_HASH_MISMATCH", SCRIPT)
        self.assertIn("EXISTING_PRIVATE_COPY_DIFFERS", SCRIPT)

    def test_adb_pull_is_read_only_and_opt_in(self):
        self.assertIn("if ($Mode -ceq 'CompareInstalled')", SCRIPT)
        self.assertIn("shell pm path", SCRIPT)
        self.assertIn("pull $basePaths[0] $temp", SCRIPT)
        self.assertIn("SIGNING_CERT_MISMATCH_DO_NOT_INSTALL", SCRIPT)

    def test_checks_apk_signing_and_package(self):
        self.assertIn("apksigner.bat", SCRIPT)
        self.assertIn("aapt.exe", SCRIPT)
        self.assertIn("com.spacesarmat.omp.test", SCRIPT)
        self.assertIn("APKSIGNER_VERIFY_FAILED", SCRIPT)

    def test_unknown_or_missing_file_returns_hold(self):
        self.assertIn("SOURCE_APK_NOT_RETAINED_ON_RUNNER", SCRIPT)
        self.assertIn("MANIFEST_EXPECTED_ARM32_SHA_MISSING", SCRIPT)
        self.assertIn("APK_SHA256_MISMATCH", SCRIPT)
        self.assertIn("throw ('G1P2_HANDOFF_HOLD: '", SCRIPT)

    def test_no_install_implicit_grants(self):
        self.assertIn("NO_ADB_INSTALL_OR_TV_CHANGE", SCRIPT)
        self.assertNotIn("Install-Android", SCRIPT)

    def test_historical_run_remains_default_but_future_runs_supported(self):
        self.assertIn("42331308161", SCRIPT)
        self.assertIn("[string]$RunId", SCRIPT)
        self.assertIn("[string]$RunAttempt", SCRIPT)
        self.assertIn("[string]$ExpectedSha256", SCRIPT)
        self.assertIn("'p1-g1-prod-' + $run", SCRIPT)
        self.assertIn("private-artifacts\\G1P2", SCRIPT)

    def test_no_canonical_pass_fabrication(self):
        self.assertNotIn("TORRENT_TV_BRAIN_REVIEW_PASS_V1", SCRIPT)


if __name__ == "__main__":
    unittest.main()
