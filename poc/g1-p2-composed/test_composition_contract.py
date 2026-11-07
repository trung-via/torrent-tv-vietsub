"""Pure source-policy regressions for G1+P2 staged integration. No Windows/TV actions."""
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = (ROOT / "poc/g1-p2-composed/build-on-runner.ps1").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github/workflows/p1-g1-p2-composed-manual.yml").read_text(encoding="utf-8")
G1 = ROOT / "poc/g1-prod/build-on-runner.ps1"
P2 = (ROOT / "poc/p2-source/omp-ui/apply.mjs").read_text(encoding="utf-8")


def git_blob(path: Path) -> str:
    return subprocess.check_output(["git", "hash-object", str(path)], text=True).strip()


class CompositeContractTests(unittest.TestCase):
    def test_existing_g1_builder_kept_byte_identical(self):
        self.assertEqual(git_blob(G1), "534379ab41699cc4d43328c5dfc80bbec6bad3db")

    def test_pinned_g1_helper_and_regression_test_unchanged(self):
        self.assertEqual(git_blob(ROOT / "poc/g1-prod/P1ProductionSubtitles.kt"),
                         "2732405d5b9ac2523e2b531815e6783803e14b7c")
        self.assertEqual(git_blob(ROOT / "poc/g1-prod/P1ProductionSubtitlesTest.kt"),
                         "f4b0a7dda39172f7b9171cb8b4022689018810c1")

    def test_composition_order_before_build(self):
        expected = [
            "poc\\g1-prod\\apply.ps1",
            "poc\\g1-prod\\verify.ps1",
            "poc\\p2-source\\omp-ui\\apply.mjs",
            "npx.cmd --no-install vitest",
            "npm.cmd run android:sync",
            "gradlew.bat assembleDebug testDebugUnitTest",
        ]
        positions = [BUILD.index(x) for x in expected]
        self.assertEqual(positions, sorted(positions))

    def test_source_pins_are_unchanged(self):
        self.assertIn("52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f", BUILD)
        self.assertIn("6ba6edd39f5d986ddfae29b5425b8ac0b319844e", BUILD)
        self.assertIn("52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f", P2)

    def test_distinct_workflow_ref_and_runner(self):
        self.assertIn("'.github/workflows/p1-g1-p2-composed-manual.yml'", BUILD)
        self.assertIn("torrent-tv-vietsub-win", BUILD)
        self.assertIn("RUNNER_WORKSPACE", BUILD)
        self.assertIn("RUNNER_TEMP", BUILD)
        self.assertIn("SOURCE_COMMIT", WORKFLOW)

    def test_repo_public_is_not_a_silent_skip(self):
        self.assertNotIn("github.event.repository.private == true &&", WORKFLOW)
        self.assertIn("github.actor == 'trung-via'", WORKFLOW)
        self.assertIn("github.ref == 'refs/heads/main'", WORKFLOW)

    def test_manual_only_with_exact_authorization(self):
        self.assertIn("workflow_dispatch:", WORKFLOW)
        self.assertIn("BUILD_G1_P2_DEBUG_ONCE", WORKFLOW)
        self.assertNotIn("pull_request_target:", WORKFLOW)
        self.assertNotIn("workflow_run:", WORKFLOW)
        self.assertNotIn("push:", WORKFLOW)

    def test_public_does_not_upload_unreviewed_binary(self):
        self.assertIn("if: github.event.repository.private == true", WORKFLOW)
        self.assertIn("*.apk", WORKFLOW)
        self.assertIn("SHA256SUMS-G1P2.txt", WORKFLOW)
        self.assertIn("G1P2-BUILD-EVIDENCE.txt", WORKFLOW)

    def test_no_adb_installs_or_tv_mutation(self):
        for banned in ["adb install", "adb shell", "adb push", "am force-stop",
                       "pm clear", "rm -rf", "torrserver.exe"]:
            self.assertNotIn(banned, BUILD.lower())
            self.assertNotIn(banned, WORKFLOW.lower())

    def test_gate_does_not_claim_tv_pass(self):
        self.assertIn("G1_P2_COMPOSED_REAL_TV_UNVERIFIED", BUILD)
        self.assertIn("G1_HUMAN_TEST_APPLIES_TO_PREVIOUS_APK_ONLY", BUILD)
        self.assertIn("NOT_REAL_TV_PASS_OR_RELEASE_PASS", BUILD)

    def test_new_p2_test_is_present_before_gradle(self):
        self.assertIn("tests/sources/tvCandidateCheck.test.ts", BUILD)
        self.assertIn("G1_P2_METADATA_VITEST_PASS", BUILD)

    def test_workflow_checks_out_exact_main_run_sha(self):
        self.assertIn("ref: ${{ github.sha }}", WORKFLOW)
        self.assertIn("SOURCE_COMMIT: ${{ github.sha }}", WORKFLOW)
        self.assertIn("$env:GITHUB_WORKFLOW_REF", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
