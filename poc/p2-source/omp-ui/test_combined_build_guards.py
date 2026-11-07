"""Source-only guard tests for G1+P2 composition; never run Windows/ADB."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
G1 = ROOT / "poc/g1-prod/build-on-runner.ps1"
COMBINED = ROOT / "poc/p2-source/omp-ui/build-g1p2-on-runner.ps1"
P2_OVERLAY = ROOT / "poc/p2-source/omp-ui/apply.mjs"
WORKFLOW = ROOT / ".github/workflows/p2-g1-combined-manual.yml"

class CompositionGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.g1 = G1.read_text(encoding="utf-8")
        cls.combo = COMBINED.read_text(encoding="utf-8")
        cls.overlay = P2_OVERLAY.read_text(encoding="utf-8")
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_main_only_distinct_workflow_and_original_g1_unchanged(self):
        self.assertIn("$workflow = '.github/workflows/p1-g1-production-manual.yml'", self.g1)
        self.assertIn("$workflow = '.github/workflows/p2-g1-combined-manual.yml'", self.combo)
        self.assertIn("$branch = 'refs/heads/main'", self.combo)
        self.assertIn("$env:GITHUB_WORKFLOW_REF", self.combo)

    def test_g1_applies_and_verifies_before_p2(self):
        c = self.combo
        first = c.index("poc\\g1-prod\\apply.ps1")
        verify = c.index("poc\\g1-prod\\verify.ps1")
        p2 = c.index("'apply.mjs') $omp")
        self.assertLess(first, verify)
        self.assertLess(verify, p2)

    def test_pinned_upstream_omp_player_unchanged(self):
        for x in ("52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f",
                  "6ba6edd39f5d986ddfae29b5425b8ac0b319844e"):
            self.assertIn(x, self.g1)
            self.assertIn(x, self.combo)
        self.assertIn("be8ab4529e0fdb9fe6dde3cc68c7fe58284aa323", self.overlay)

    def test_only_g1_source_with_p2_ui_changes(self):
        self.assertIn("G1PROD_GUARDED_SOURCE_PATCH_PASS", self.combo)
        self.assertIn("G1P2_COMPOSED_SOURCE_GUARDS_PASS", self.combo)
        self.assertIn("G1P2_P2_VITEST_PASS", self.combo)
        self.assertIn("npx.cmd vitest run tests/sources/tvCandidateCheck.test.ts", self.combo)
        self.assertIn("assembleDebug testDebugUnitTest", self.combo)

    def test_no_adb_install_or_release_dispatch(self):
        text = self.combo.lower()
        for forbidden in ("adb install", "adb shell", "assembleRelease", "upload release", "git push", "gh workflow"):
            self.assertNotIn(forbidden.lower(), text)
        self.assertIn("workflow_dispatch:", self.workflow)
        self.assertNotIn("pull_request_target:", self.workflow)
        self.assertNotIn("schedule:", self.workflow)
        self.assertNotIn("workflow_run:", self.workflow)

    def test_public_repo_manual_gate_no_silent_private_assumption(self):
        self.assertNotIn("repository.private == true", self.workflow)
        self.assertIn("github.actor == 'trung-via'", self.workflow)
        self.assertIn("BUILD_G1P2_DEBUG_PUBLIC_ARTIFACT_ONCE", self.workflow)
        self.assertIn("github.ref == 'refs/heads/main'", self.workflow)
        self.assertIn("persist-credentials: false", self.workflow)

    def test_artifact_sha_and_evidence_are_labeled_composition(self):
        self.assertIn("SHA256SUMS-G1P2.txt", self.combo)
        self.assertIn("G1P2-BUILD-EVIDENCE.txt", self.combo)
        self.assertIn("NOT_REAL_TV_PASS_OR_RELEASE_PASS", self.combo)
        self.assertIn("p2_ui=opt_in_reported_metadata_only", self.combo)
        self.assertIn("no_adb_or_tv_install=yes", self.combo)

    def test_git_porcelain_columns_remain_intact_with_g1_dirty_tree(self):
        # .trim() strips the significant first status column in Git porcelain.
        self.assertIn(".trimEnd()", self.overlay)
        self.assertNotIn("encoding: 'utf8' }).trim();", self.overlay)
        self.assertIn("line.slice(3)", self.overlay)

    def test_source_checkout_immutable_and_workflow_guard_present(self):
        pinned_ref = re.search(r"ref: ([0-9a-f]{40})", self.workflow)
        source_arg = re.search(r"SourceCommit '([0-9a-f]{40})'", self.workflow)
        self.assertIsNotNone(pinned_ref)
        self.assertIsNotNone(source_arg)
        self.assertEqual(pinned_ref.group(1), source_arg.group(1))
        self.assertNotEqual(pinned_ref.group(1), "dbc0c1b04dc352bed0662fae899475f4e55425f0")
        self.assertIn("GITHUB_REF -cne 'refs/heads/main'", self.workflow)
        self.assertIn("p2-g1-combined-manual.yml@refs/heads/main", self.workflow)

if __name__ == "__main__":
    unittest.main()
