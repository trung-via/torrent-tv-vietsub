"""Offline source-package tests; no Windows, provider, TV or Git network."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import zipfile

from build_flow3_owner_overlay import (RECIPE, apply_patch, assemble, git_blob,
                                      write_zip)


class Flow3PackageTests(unittest.TestCase):
    def fixture(self):
        before = b"def legacy():\n    pass\n\ndef tick():\n    legacy()\n"
        after = b"def shared():\n    pass\n\ndef tick():\n    shared()\n"
        path = "app/poc/p2-sub-discovery/bridge.py"
        other = "runner/play.ps1"
        copy = b"# fixture only\n"
        patch = {"path": path, "source": "old/bridge.py", "base_blob": git_blob(before),
                 "blob": git_blob(after), "kind": "bridge", "begin": "def legacy():",
                 "end": "def tick():", "replace_block": "def shared():\n    pass\n\n",
                 "old": "    legacy()", "new": "    shared()"}
        row = {"path": other, "source": "main/play.ps1", "blob": git_blob(copy)}
        recipe = {"schema": "TTV-FLOW3-SOURCE-OVERLAY-V1", "runtime_base": "old",
                  "merged_g2_source": "main", "package_commit": "package",
                  "patches": [patch], "copies": [row]}
        manifest = {"schema": "TTV-FLOW3-SOURCE-PACKAGE-V1", "runtime_base": "old",
                    "merged_g2_source": "main", "files": [
                        {"path": path, "blob": patch["blob"], "base_blob": patch["base_blob"]},
                        {"path": other, "blob": row["blob"]}]}
        data = {("old", patch["source"]): before, ("main", row["source"]): copy,
                ("package", path): after, ("package", other): copy,
                ("package", "manifest.json"): json.dumps(manifest).encode(),
                ("package", "README.md"): b"source only\n"}
        return recipe, data

    def test_actual_recipe_two_runtime_hooks_and_canonical_paths(self):
        recipe = json.loads(RECIPE.read_text())
        self.assertEqual(len(recipe["patches"]), 2)
        self.assertEqual(len(recipe["copies"]), 8)
        bridge, runtime = recipe["patches"]
        self.assertIn("poll_owner_g2_idle(", bridge["new"])
        self.assertIn("active.add(pool.submit(work))", bridge["new"])
        self.assertIn("trace=owner_full_trace", bridge["new"])
        self.assertIn("_publish_g2_selection", bridge["replace_block"])
        self.assertIn("bind_owner_g2(factory, runner)", runtime["new"])
        self.assertIn('TTV_G2_WARM', runtime["new"])
        handoff = [x for x in recipe["copies"] if x["path"].endswith("owner_movie_handoff.py")]
        self.assertEqual(len(handoff), 1)
        self.assertEqual(handoff[0]["source"], "poc/p2-source/owner_movie_handoff.py")
        self.assertTrue(all("start-owner" not in x["path"] for x in recipe["patches"]+recipe["copies"]))

    def test_build_exact_and_reproducible_no_overwrite(self):
        recipe, data = self.fixture()
        files = assemble(recipe, lambda c,p: data[c,p])
        with TemporaryDirectory() as d:
            a, b = Path(d)/"a.zip", Path(d)/"b.zip"
            write_zip(a, files)
            write_zip(b, files)
            self.assertEqual(a.read_bytes(), b.read_bytes())
            with zipfile.ZipFile(a) as z:
                self.assertEqual({n: z.read(n) for n in z.namelist()}, files)
            with self.assertRaises(FileExistsError):
                write_zip(a, files)

    def test_source_drift_and_snapshot_drift_fail_before_zip(self):
        recipe, data = self.fixture()
        patch = recipe["patches"][0]
        with self.assertRaisesRegex(ValueError, "BLOB_MISMATCH"):
            apply_patch(b"wrong", patch)
        data[("package", patch["path"])] = b"wrong"
        with self.assertRaisesRegex(ValueError, "SNAPSHOT_MISMATCH"):
            assemble(recipe, lambda c,p: data[c,p])

    def test_literal_transform(self):
        before = b"def factory():\n    return old()\n"
        after = b"def factory():\n    return new()\n"
        row = {"kind":"literal","base_blob":git_blob(before),"blob":git_blob(after),
               "old":"return old()", "new":"return new()"}
        self.assertEqual(apply_patch(before, row), after)
        row["old"] = "missing"
        with self.assertRaisesRegex(ValueError, "CONTEXT_MISMATCH"):
            apply_patch(before, row)


if __name__ == "__main__":
    unittest.main()
