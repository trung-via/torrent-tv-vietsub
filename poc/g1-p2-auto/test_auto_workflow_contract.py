"""Structural guardrails: auto main builds must not run on PRs or publish APKs."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
AUTO = (ROOT / ".github/workflows/tv-g1p2-auto-debug.yml").read_text(encoding="utf-8")
MANUAL = (ROOT / ".github/workflows/p2-g1-combined-manual.yml").read_text(encoding="utf-8")
BUILDER = (ROOT / "poc/p2-source/omp-ui/build-g1p2-on-runner.ps1").read_text(encoding="utf-8")


class WorkflowContracts(unittest.TestCase):
    def test_push_main_only_not_pr_or_direct_public_dispatch(self):
        self.assertIn("on:\n  push:", AUTO)
        self.assertIn("branches: [main]", AUTO)
        self.assertNotIn("pull_request_target:", AUTO)
        self.assertNotIn("workflow_dispatch:", AUTO)
        self.assertNotIn("schedule:", AUTO)

    def test_main_review_gate_required_before_windows(self):
        self.assertIn("needs: brain-acceptance", AUTO)
        self.assertIn("needs.brain-acceptance.outputs.approved == 'true'", AUTO)
        self.assertIn("needs.brain-acceptance.outputs.source_sha == github.sha", AUTO)
        self.assertIn("runs-on: ubuntu-latest", AUTO)
        self.assertIn("runs-on: [self-hosted, Windows, X64, torrent-tv-vietsub]", AUTO)

    def test_source_and_workflow_identity_bound_to_exact_main_commit(self):
        self.assertIn("ref: ${{ github.sha }}", AUTO)
        self.assertIn("G1P2_AUTO_SOURCE_SHA", AUTO)
        self.assertIn("$autoRoute", BUILDER)
        self.assertIn("GITHUB_SHA -ceq $SourceCommit", BUILDER)
        self.assertIn("G1P2_AUTO_BRAIN_PR -match", BUILDER)

    def test_all_checks_and_owner_approval_before_selfhost(self):
        self.assertIn("verify_merged_pass.py", AUTO)
        self.assertIn("GH_TOKEN:", AUTO)
        self.assertIn("PUSH_BEFORE: ${{ github.event.before }}", AUTO)
        self.assertIn("github.repository == 'trung-via/torrent-tv-vietsub'", AUTO)

    def test_apk_never_uploaded_by_auto_workflow_even_public(self):
        self.assertNotIn("*.apk", AUTO)
        self.assertIn("SHA256SUMS-G1P2.txt", AUTO)
        self.assertIn("G1P2-BUILD-EVIDENCE.txt", AUTO)
        self.assertNotIn("release", AUTO.lower().split("  composed-debug:")[1].split("      - name: Upload")[0])

    def test_preserve_old_manual_owner_public_artifact_confirmation(self):
        self.assertIn("BUILD_G1P2_DEBUG_PUBLIC_ARTIFACT_ONCE", MANUAL)
        self.assertIn("$manualRoute", BUILDER)
        self.assertIn("workflow_dispatch", BUILDER)
        self.assertIn("p2-g1-combined-manual.yml", BUILDER)

    def test_no_device_or_host_lifecycle_actions(self):
        for forbidden in ("adb install", "adb shell", "adb push", "pm clear",
                          "torrserver.exe", "netsh advfirewall", "sc.exe"):
            self.assertNotIn(forbidden, AUTO.lower())
        self.assertIn("persist-credentials: false", AUTO)


if __name__ == "__main__":
    unittest.main()
