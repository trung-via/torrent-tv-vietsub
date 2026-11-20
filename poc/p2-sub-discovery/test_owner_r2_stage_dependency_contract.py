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
        # This manifest describes the IMMUTABLE R2 release already staged on
        # Windows. It must not silently change when the live source evolves.
        # Comparing every old SHA to current HEAD made all subsequent Owner
        # fixes fail CI, although the release helper fetches historical bytes
        # from source_tree and verifies the 17 downloaded hashes independently.
        # Windows checkout may convert Git LF to CRLF. Hash canonical Git
        # bytes, as the historical release stage itself does.
        immutable = MANIFEST.read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(immutable).hexdigest(),
                         "0145b0c536b70195b17671c065c8ced071013a784a47a9f77217c16b8ead9298")
        manifest = json.loads(immutable)
        self.assertEqual(manifest["release_id"], "r2-rolling-175-r2")
        self.assertEqual(manifest["source_tree"],
                         "b9e42ef91be1c5c347f418e4e4a6133e2a963366")
        self.assertEqual(manifest["mode"], "STAGE_ONLY")
        rows = {item["path"]: item["sha256"] for item in manifest["files"]}
        self.assertEqual(len(rows), len(manifest["files"]))
        self.assertEqual(len(rows), 17)
        for relative, expected in rows.items():
            with self.subTest(relative=relative):
                self.assertTrue(relative.startswith((
                    "poc/p2-sub-discovery/", "poc/p2-aisub/")))
                self.assertNotIn("..", Path(relative).parts)
                self.assertRegex(expected, r"\A[0-9a-f]{64}\Z")
                self.assertTrue((ROOT / relative).is_file())

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
        self.assertIn("owner-r2-deblock-stage-v1.json", dispatch)
        self.assertIn("owner-r2-deblock-stage-v1.json", check)
        self.assertIn("r2-deblock-175", dispatch)
        self.assertIn("r2-deblock-175", check)
        self.assertIn("Count -ne 3", check)

    def test_new_hotfix_stages_only_three_changed_owner_modules(self):
        manifest = json.loads((ROOT / "hostops/releases/owner-r2-deblock-stage-v1.json")
                              .read_text(encoding="utf-8"))
        self.assertEqual(manifest["schema"], "TTV-OWNER-RELEASE-STAGE-V1")
        self.assertEqual(manifest["mode"], "STAGE_ONLY")
        self.assertEqual(manifest["release_id"], "r2-deblock-175")
        self.assertEqual(manifest["source_tree"],
                         "99e4eee06675c9e5db2a640962ba641c0329b60c")
        self.assertEqual({x["path"] for x in manifest["files"]}, {
            "poc/p2-sub-discovery/owner_session_bridge.py",
            "poc/p2-sub-discovery/verified_v3_processor.py",
            "poc/p2-sub-discovery/owner_r2_verified_processor.py",
        })
        # Subsequent fixes may change HEAD. The source-check HostOps job
        # enforces current bytes at dispatch, while a historical stage
        # manifest remains immutable rather than blocking future source.
        for row in manifest["files"]:
            with self.subTest(path=row["path"]):
                self.assertRegex(row["sha256"], r"\A[0-9a-f]{64}\Z")

    def test_owner_hotfix_offline_applier_requires_stopped_agent_and_backup(self):
        applier = (ROOT / "hostops/setup/owner-r2-deblock-offline-apply.ps1").read_text()
        checker = (ROOT / "hostops/jobs/owner-release-source-check.ps1").read_text()
        self.assertIn("owner-r2-deblock-offline-apply.ps1", checker)
        for token in (
            "OWNER_TASK_NOT_DISABLED", "OWNER_WORKERS_NOT_STOPPED",
            "ACTIVE_OR_UNCERTAIN_P2_JOB", "PENDING_OWNER_EVENTS",
            "STAGE_HASH_MISMATCH", "INSTALLED_BASELINE_UNEXPECTED",
            "BACKUP_HASH_MISMATCH", "INSTALL_FAILED_OLD_BYTES_RESTORED_OWNER_STOPPED",
            "OWNER_DEBLOCK_OWNER_RESTART=NOT_RUN",
        ):
            self.assertIn(token, applier)
        for name in ("Start-ScheduledTask", "Enable-ScheduledTask", "Stop-ScheduledTask",
                     "Disable-ScheduledTask", "Invoke-WebRequest", "Remove-Item"):
            self.assertNotIn(name, applier)

    def test_one_shot_owner_maintenance_is_interactive_and_recoverable(self):
        wrapper = (ROOT / "hostops/setup/owner-r2-deblock-maintenance-once.ps1").read_text()
        applier_path = ROOT / "hostops/setup/owner-r2-deblock-offline-apply.ps1"
        applier = applier_path.read_bytes().replace(b"\r\n", b"\n")
        script_hash = hashlib.sha256(applier).hexdigest()
        checker = (ROOT / "hostops/jobs/owner-release-source-check.ps1").read_text()
        self.assertIn("owner-r2-deblock-maintenance-once.ps1", checker)
        self.assertIn(script_hash, wrapper)
        self.assertIn("1687fb327803c916af047c5fa13183ff9e79f92c", wrapper)
        for token in (
            "INTERACTIVE_OWNER_REQUIRED", "OWNER_PENDING_EVENTS",
            "P2_UNCERTAIN_OR_ACTIVE", "RESIDUAL_WORKER_UNVERIFIED",
            "RESIDUAL_WORKER_IDENTITY_CHANGED", "PINNED_APPLIER_HASH_MISMATCH",
            "-ApplyOffline", "-RollbackOffline", "-BackupId",
            "NEW_OWNER_ACTIVE_FRESH_HEARTBEAT", "NEW_OWNER_UNHEALTHY_OLD_OWNER_RECOVERED",
        ):
            self.assertIn(token, wrapper)
        offline = applier.decode("utf-8")
        for token in (
            "OWNER_DEBLOCK_ROLLBACK=ORIGINAL_BYTES_RESTORED_OWNER_STOPPED",
            "ROLLBACK_BACKUP_HASH_MISMATCH", "ROLLBACK_INSTALLED_HASH_MISMATCH",
        ):
            self.assertIn(token, offline)


if __name__ == "__main__":
    unittest.main()
