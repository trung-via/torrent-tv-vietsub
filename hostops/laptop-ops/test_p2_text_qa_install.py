"""Offline contract for exactly two Owner P2 text-QA files and rollback."""
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
OP = ROOT / "hostops/laptop-ops/operations/owner-p2-text-qa-install-v1.ps1"
MANIFEST = ROOT / "hostops/laptop-ops/manifests/current.json"


class OwnerTextQaInstallContract(unittest.TestCase):
    def test_fixed_staged_files_exact_hashes_and_owner_scope(self):
        source = OP.read_text(encoding="utf-8")
        for token in (
            "owner-p2-text-qa-v1-39f2a63787b0",
            "poc/p2-aisub/translator_gateway.py",
            "poc/p2-sub-discovery/owner_session_bridge.py",
            "d63c468a6417fab87d6c9e56e6dd319ddc28289f7c95eb064eaf9684d5774fc3",
            "85f8ca9e75d83e357becf7c9191734ce0f41b664b83cf8ea684a3bff1e1dc4b7",
            "P2_TEXT_QA_OWNER=INSTALLED_HASH_VERIFIED_OWNER_RUNNING",
            "P2_TEXT_QA_OWNER=ROLLED_BACK_OLD_OWNER_RUNNING",
            "StopOwner", "StartOwner", "NoOpenP2", "Hash $saved",
        ):
            self.assertIn(token, source)
        for prohibited in (
            "agy --model", "Invoke-RestMethod", "Invoke-WebRequest",
            "batch-0002.inflight').Delete", "Remove-Item", "Clear-Content",
        ):
            self.assertNotIn(prohibited, source)

    def test_dispatch_pins_only_owner_maintenance(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["operation"], "owner-p2-text-qa-install-v1")
        self.assertEqual(manifest["category"], "owner-maintenance")
        self.assertEqual(manifest["risk"], "ROUTINE")
        self.assertEqual(manifest["arguments"], [])


if __name__ == "__main__":
    unittest.main()
