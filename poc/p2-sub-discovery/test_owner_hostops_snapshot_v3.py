"""Source-only HostOps V3 aggregate event diagnostics (no private payload read)."""
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from owner_hostops_snapshot import build_snapshot
from owner_hostops_snapshot_v3 import (
    SCHEMA, build_snapshot_v3, publish_owner_snapshot_v3,
)


class OwnerSnapshotV3Tests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.owner = self.root / "OwnerBridge"
        self.owner.mkdir()
        self.inbox = self.owner / "inbox"
        self.inbox.mkdir()
        self.shared = self.root / "shared"

    def test_adds_only_fixed_counts_without_changing_immutable_v2_schema(self):
        (self.inbox / ("event-" + "a" * 32 + ".blocked")).write_text(
            "PRIVATE_SYNTHETIC_MOVIE")
        (self.inbox / ("event-" + "b" * 32 + ".review")).write_text("PRIVATE")
        (self.inbox / ("preprovider-retry-" + "c" * 32 + ".json")).write_text("PRIVATE")
        (self.inbox / ("event-" + "d" * 32 + ".json")).write_text("PRIVATE")
        v2 = build_snapshot(owner_root=self.owner)
        self.assertEqual(v2["schema"], "TTV-HOSTOPS-OWNER-SNAPSHOT-V2")
        self.assertNotIn("blocked_events", v2["p2"])
        v3 = build_snapshot_v3(owner_root=self.owner)
        self.assertEqual(v3["schema"], SCHEMA)
        self.assertEqual(v3["p2"]["blocked_events"], 1)
        self.assertEqual(v3["p2"]["review_events"], 1)
        self.assertEqual(v3["p2"]["deferred_events"], 1)
        self.assertEqual(v3["p2"]["pending_events"], 1)
        self.shared.mkdir()
        self.assertTrue(publish_owner_snapshot_v3(
            owner_root=self.owner, shared_dir=self.shared))
        receipt = (self.shared / "owner-snapshot.json").read_text()
        self.assertEqual(json.loads(receipt)["schema"], SCHEMA)
        self.assertNotIn("PRIVATE", receipt)
        self.assertNotIn("event-", receipt)

    def test_missing_and_symlinked_inbox_do_not_fake_clearance(self):
        self.inbox.rmdir()
        self.assertEqual(build_snapshot_v3(owner_root=self.owner)["p2"]
                         ["blocked_events"], -1)
        outside = self.root / "outside"
        outside.mkdir()
        try:
            self.inbox.symlink_to(outside, target_is_directory=True)
        except (OSError, NotImplementedError):
            return
        self.assertEqual(build_snapshot_v3(owner_root=self.owner)["p2"]
                         ["blocked_events"], -1)
