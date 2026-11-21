"""Offline contract for Owner P2 gateway-only installation and rollback."""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
OP = ROOT / "hostops/laptop-ops/operations/owner-p2-gateway-install-v2.ps1"
MANIFEST = ROOT / "hostops/laptop-ops/manifests/current.json"
STATUS = ROOT / "hostops/laptop-ops/operations/owner-p2-text-qa-status-v1.ps1"
READER = ROOT / "hostops/jobs/owner-p2-text-qa-status-readonly.ps1"


class OwnerTextQaInstallContract(unittest.TestCase):
    def test_fixed_staged_files_exact_hashes_and_owner_scope(self):
        source = OP.read_text(encoding="utf-8")
        for token in (
            "owner-p2-text-qa-v1-39f2a63787b0",
            "poc/p2-aisub/translator_gateway.py",
            "poc\\p2-sub-discovery\\owner_session_bridge.py",
            "d63c468a6417fab87d6c9e56e6dd319ddc28289f7c95eb064eaf9684d5774fc3",
            "P2_TEXT_QA_OWNER=INSTALLED_HASH_VERIFIED_OWNER_RUNNING",
            "P2_TEXT_QA_OWNER=ROLLED_BACK_OLD_OWNER_RUNNING",
            "StopOwner", "StartOwner", "NoOpenP2", "Hash $saved",
            "OWNER_BRIDGE_DRIFT", "Hash $bridgePath",
        ):
            self.assertIn(token, source)
        self.assertEqual(source.count("'poc/p2-aisub/translator_gateway.py' = @{"), 1)
        self.assertNotIn("'poc/p2-sub-discovery/owner_session_bridge.py' = @{", source)
        for prohibited in (
            "agy --model", "Invoke-RestMethod", "Invoke-WebRequest",
            "batch-0002.inflight').Delete", "Remove-Item", "Clear-Content",
        ):
            self.assertNotIn(prohibited, source)

    def test_manifest_pins_one_bounded_batch2_archive(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["operation"], "owner-p2-batch2-archive-v1")
        self.assertEqual(manifest["script_path"], "hostops/laptop-ops/operations/owner-p2-batch2-archive-v1.ps1")
        self.assertEqual(manifest["category"], "owner-maintenance")
        self.assertEqual(manifest["risk"], "ROUTINE")
        self.assertEqual(manifest["arguments"], [])

    def test_private_status_probe_never_mutates_owner_or_calls_provider(self):
        source = STATUS.read_text(encoding="utf-8")
        for prohibited in (
            "Stop-ScheduledTask", "Start-ScheduledTask", "Stop-Process",
            "Disable-ScheduledTask", "Enable-ScheduledTask", "Move-Item",
            "Remove-Item", "Invoke-WebRequest", "agy --model",
        ):
            self.assertNotIn(prohibited, source)
        self.assertIn("full-owner-output.log", source)
        self.assertIn("last_install_code", source)
        self.assertIn("archived_batch2_count", source)
        self.assertIn("last_archive_code", source)
        self.assertIn("bridge_sha16", source)
        self.assertIn("owner-p2-gateway-install-v2", source)
        reader = READER.read_text(encoding="utf-8")
        self.assertNotIn("$env:LOCALAPPDATA", reader)
        self.assertIn("P2_TEXT_STATUS_PRIVATE_LOG=NOT_EXPORTED", reader)
        self.assertIn("P2_TEXT_STATUS_BRIDGE_SHA16", reader)


if __name__ == "__main__":
    unittest.main()
