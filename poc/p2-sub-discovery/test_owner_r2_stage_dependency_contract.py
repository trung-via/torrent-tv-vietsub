"""Ensure the offline Owner overlay includes the R0 modules it relies on.

The full checkout can import R2 while an old installed Owner cannot: the
release must explicitly stage compatibility dependencies rather than assuming
the prior Windows installation has newer R0 files.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "hostops/releases/owner-r2-stage-v1.json"


class R2StageDependencyContract(unittest.TestCase):
    def test_exact_source_bytes_and_previous_owner_compatibility(self):
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(manifest["release_id"], "r2-rolling-175-r2")
        self.assertEqual(manifest["mode"], "STAGE_ONLY")
        rows = {item["path"]: item["sha256"] for item in manifest["files"]}
        self.assertEqual(len(rows), len(manifest["files"]))
        self.assertEqual(len(rows), 17)
        for relative, expected in rows.items():
            with self.subTest(relative=relative):
                self.assertTrue(relative.startswith((
                    "poc/p2-sub-discovery/", "poc/p2-aisub/")))
                source = ROOT / relative
                self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), expected)

        # These three files are imported by R2 but were NOT part of the
        # previous 14-file release. Their installed provenance was unproven
        # at the failed upgrade; their exact versions must ship together.
        for name in (
            "owner_p3_p4_private_policy.py",  # R0 empty-media personal mode
            "owner_torrserver_ffp_tracks.py",  # VI track probe contract
            "owner_hostops_snapshot.py",  # V3 snapshot writer's V2 base
        ):
            self.assertIn("poc/p2-sub-discovery/" + name, rows)

    def test_stage_dispatch_and_source_gate_same_release(self):
        dispatch = (ROOT / "hostops/jobs/owner-release-stage-dispatch.ps1").read_text()
        check = (ROOT / "hostops/jobs/owner-release-source-check.ps1").read_text()
        self.assertIn("r2-rolling-175-r2", dispatch)
        self.assertIn("r2-rolling-175-r2", check)
        self.assertIn("Count -ne 17", check)


if __name__ == "__main__":
    unittest.main()
