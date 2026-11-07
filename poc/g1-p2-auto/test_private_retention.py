"""Contract guards: the private APK survives RUNNER_TEMP cleanup and stays local."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / "poc/g1-p2-auto/retain-private-arm32.ps1").read_text(encoding="utf-8")
AUTO = (ROOT / ".github/workflows/tv-g1p2-auto-debug.yml").read_text(encoding="utf-8")
HANDOFF = (ROOT / "tools/redmi-validation/verify-g1p2-arm32.ps1").read_text(encoding="utf-8")


class PersistentPrivateApkTests(unittest.TestCase):
    def test_build_then_private_retention_then_only_evidence_upload(self):
        a = AUTO.index("Apply G1 and P2, run tests, assemble Debug")
        b = AUTO.index("Persist verified ARM32 Debug APK")
        c = AUTO.index("Upload SHA256 and redacted build manifest even if signer gate holds")
        self.assertLess(a, b)
        self.assertLess(b, c)
        self.assertIn("retain-private-arm32.ps1", AUTO)
        self.assertNotIn("*.apk", AUTO)

    def test_durable_directory_outside_runner_work_temp(self):
        self.assertIn("$root = 'C:\\TOOL\\TorrentTV-Runner'", SCRIPT)
        self.assertIn("'private-artifacts'", SCRIPT)
        self.assertIn("'G1P2'", SCRIPT)
        self.assertIn("$env:RUNNER_TEMP", SCRIPT)
        self.assertIn("Move-Item -LiteralPath $partial -Destination $target", SCRIPT)

    def test_checksum_package_signature_verified_before_copy(self):
        checks = (
            "Get-FileHash -LiteralPath $apk -Algorithm SHA256",
            "SHA256_MANIFEST_MISMATCH",
            "EVIDENCE_SOURCE_RUN_MISMATCH",
            "APK_PACKAGE_NOT_PROVEN",
            "APK_SIGNATURE_NOT_VERIFIED",
        )
        for x in checks:
            self.assertIn(x, SCRIPT)
        self.assertLess(SCRIPT.index("SHA256_MANIFEST_MISMATCH"), SCRIPT.index("Copy-Item -LiteralPath $apk"))

    def test_verified_hash_copy_precedes_signing_hold(self):
        # Preserve bytes for diagnosis, but a signature failure still blocks install.
        self.assertLess(SCRIPT.index("Move-Item -LiteralPath $partial -Destination $target"),
                        SCRIPT.index("$signer = Read-Tool 'apksigner.bat'"))
        self.assertIn("SIGNATURE_HOLD_PENDING_VERIFY", SCRIPT)
        self.assertIn("SIGNATURE_VERIFIED", SCRIPT)
        self.assertIn("APK_SIGNATURE_NOT_VERIFIED_RETAINED_QUARANTINED", SCRIPT)
        self.assertIn("G1P2_APKSIGNER_DIAGNOSTIC", SCRIPT)
        self.assertIn("G1P2_PRIVATE_APK_QUARANTINED_LOCAL_ONLY", SCRIPT)

    def test_failed_signature_still_publishes_only_checksum_evidence(self):
        self.assertIn("if: always()", AUTO)
        self.assertIn("if-no-files-found: warn", AUTO)
        self.assertNotIn("*.apk", AUTO)

    def test_acl_is_restricted_to_owner_admins_and_system(self):
        self.assertIn("SetAccessRuleProtection($true,$false)", SCRIPT)
        self.assertIn("S-1-5-18", SCRIPT)
        self.assertIn("S-1-5-32-544", SCRIPT)
        self.assertIn("PRIVATE_DIRECTORY_ACL_NOT_EXCLUSIVE", SCRIPT)
        self.assertIn("REPARSE_POINT_DENIED", SCRIPT)

    def test_no_apk_external_publish_or_device_install(self):
        code = "\n".join(x for x in SCRIPT.splitlines() if not x.lstrip().startswith("#")).lower()
        for forbidden in (
            "adb install", "adb push", "adb shell", "gh release", "upload-artifact",
            "invoke-restmethod", "invoke-webrequest", "curl.exe", "new-netfirewallrule",
        ):
            self.assertNotIn(forbidden, code)

    def test_runner_identity_and_brain_source_bound(self):
        self.assertIn("G1P2_AUTO_BRAIN_APPROVED", SCRIPT)
        self.assertIn("G1P2_AUTO_SOURCE_SHA", SCRIPT)
        self.assertIn("GITHUB_WORKFLOW_REF", SCRIPT)
        self.assertIn("torrent-tv-vietsub-win", SCRIPT)
        self.assertIn("TRUSTED_AUTO_MAIN_BUILD_CONTEXT_REQUIRED", SCRIPT)

    def test_never_overwrite_existing_retained_build(self):
        self.assertIn("RETAINED_APK_ALREADY_EXISTS_NO_OVERWRITE", SCRIPT)
        self.assertIn(".partial-", SCRIPT)
        self.assertIn("PRIVATE_COPY_HASH_MISMATCH", SCRIPT)

    def test_new_handoff_accepts_pinned_run_and_sha(self):
        for fragment in ("[string]$RunId", "[string]$RunAttempt",
                         "[string]$ExpectedSha256",
                         "private-artifacts\\G1P2",
                         "SHA_OR_RUN_PARAMETER_INVALID"):
            self.assertIn(fragment, HANDOFF)

    def test_preflight_cannot_skip_expected_sha(self):
        self.assertIn("$expected = $ExpectedSha256.ToLowerInvariant()", HANDOFF)
        self.assertIn("MANIFEST_EXPECTED_ARM32_SHA_MISSING", HANDOFF)
        self.assertIn("APK_SHA256_MISMATCH", HANDOFF)

    def test_original_build_acceptance_not_device_claim(self):
        self.assertNotIn("REAL_TV_PASS", SCRIPT)
        self.assertIn("G1P2_PRIVATE_STORE_NOT_PUBLIC_NO_ADB_INSTALL", SCRIPT)


if __name__ == "__main__":
    unittest.main()
