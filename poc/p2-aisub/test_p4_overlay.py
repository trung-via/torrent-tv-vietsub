"""P4 G1+G2 import-bytes overlay guards, synthetic source only."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1] / "p4-auto-sub"
spec = importlib.util.spec_from_file_location("p4_auto_apply", HERE / "apply.py")
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fake_g1() -> str:
    return (
        "// Synthetic, not real OMP source\n"
        "class P1ProductionSubtitles {\n"
        + module.OLD_HEAD + "\n"
        + "        val dir = folder(ctx)\n"
        + "        val target = file(ctx, k, v)\n"
        + "        var created = false\n"
        + module.OLD_COMMIT + "\n"
        + "            if (created) target.delete()\n"
        + "            return false\n"
        + "        }\n"
        + "        return true\n"
        + "    }\n"
        + "    fun noteTrackChoice(ctx: Context, r: PlayRequest?, i: Int, choice: TrackChoice) {\n"
        + "        // Synthetic user's OFF/OTHER choice\n"
        + "    }\n}\n"
    )


class P4SourcePatchTest(unittest.TestCase):
    def test_bounded_helper_preserves_human_picker_and_rechecks_off_other(self):
        source = fake_g1()
        result = module.patch_g1(source)
        self.assertIn("fun importSelected(ctx: Context, uri: Uri", result)
        self.assertIn("val bytes = readDocument(ctx, uri)", result)
        self.assertIn("fun importAutomaticBytes(", result)
        self.assertIn("key != expectedMediaKey", result)
        self.assertIn('choice == "off" || choice == "other"', result)
        self.assertIn("if (automatic && p.getString", result)
        self.assertIn("@Synchronized fun noteTrackChoice", result)
        self.assertEqual(result.count("fun importAutomaticBytes("), 1)
        self.assertEqual(result.count("fun importSelected("), 1)
        self.assertNotIn("http://",result)

    def test_exact_repository_g1_helper_accepts_patch_without_omitting_original_methods(self):
        # Use actual G1 source pinned by G1's own source/Gradle overlay.
        real = HERE.parent / "g1-prod" / "P1ProductionSubtitles.kt"
        original = real.read_text(encoding="utf-8")
        patched = module.patch_g1(original)
        self.assertEqual(patched.count("fun importSelected("), 1)
        self.assertEqual(patched.count("fun importAutomaticBytes("), 1)
        self.assertIn("fun forItem(", patched)
        self.assertIn("fun prepare(", patched)
        self.assertIn("fun noteTrackChoice(", patched)
        self.assertIn("fun detectedExtension(", patched)
        self.assertEqual(original.count("fun detectedExtension("),
                         patched.count("fun detectedExtension("))
        self.assertEqual(original.count("fun removeSaved("),
                         patched.count("fun removeSaved("))

    def test_fails_closed_if_anchors_drift_or_overlay_reapplied(self):
        original=fake_g1()
        with self.assertRaisesRegex(ValueError, "P4_ALREADY_APPLIED"):
            module.patch_g1(module.patch_g1(original))
        for bad in [
            original.replace("fun importSelected", "fun importSelectedNew"),
            original.replace("val oldExt =", "val OLD_EXT ="),
            original.replace("fun noteTrackChoice", "fun changedTrackChoice"),
        ]:
            with self.subTest(kind=bad[-65:]),self.assertRaises(ValueError):
                module.patch_g1(bad)

    def _setup(self, root: Path):
        pkg = root / module.PKG
        pkg.mkdir(parents=True)
        (pkg / module.SOURCE_FILE).write_text(fake_g1(),encoding="utf-8")
        (pkg / "G2RefreshInPlace.kt").write_text("object G2RefreshInPlace {}")
        (pkg / "G2RefreshRecovery.kt").write_text("object G2RefreshRecovery {}")
        (pkg / "PlayerActivity.kt").write_text("val updated = G2RefreshInPlace.prepare(ctx,r,idx)")
        return pkg

    def test_dry_run_no_changes_then_apply_only_disposable_source(self):
        with tempfile.TemporaryDirectory(prefix="p1-g1-prod-") as temp:
            root=Path(temp)
            pkg=self._setup(root)
            original=(pkg/module.SOURCE_FILE).read_bytes()
            module.run(root,apply=False)
            self.assertEqual((pkg/module.SOURCE_FILE).read_bytes(),original)
            self.assertFalse((pkg/module.RECEIVER_FILE).exists())
            module.run(root,apply=True)
            text=(pkg/module.SOURCE_FILE).read_text(encoding="utf-8")
            self.assertIn("fun importAutomaticBytes",text)
            self.assertIn("@Synchronized fun noteTrackChoice",text)
            self.assertTrue((pkg/module.RECEIVER_FILE).is_file())
            with self.assertRaises(ValueError):
                module.run(root,apply=True)

    def test_wrong_directory_missing_g2_and_wrong_native_hook_blocked(self):
        with tempfile.TemporaryDirectory(prefix="not-g1-") as temp:
            with self.assertRaisesRegex(ValueError,"P4_DISPOSABLE_G1_CHECKOUT_REQUIRED"):
                module.run(Path(temp),apply=True)
        with tempfile.TemporaryDirectory(prefix="p1-g1-prod-") as temp:
            root=Path(temp)
            pkg=self._setup(root)
            (pkg/"G2RefreshRecovery.kt").unlink()
            with self.assertRaisesRegex(ValueError,"P4_G1_G2_COMPOSITE_SOURCE_REQUIRED"):
                module.run(root,apply=True)
        with tempfile.TemporaryDirectory(prefix="p1-g1-prod-") as temp:
            root=Path(temp)
            pkg=self._setup(root)
            (pkg/"PlayerActivity.kt").write_text("G2 removed")
            with self.assertRaisesRegex(ValueError,"P4_LIVE_G2_ACTIVITY_HOOK_NOT_PRESENT"):
                module.run(root,apply=True)


if __name__=="__main__":
    unittest.main()
