"""Fail early if the native G1 source or test changes without updating its trusted pin."""

import re
import subprocess
import unittest
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]


class G1HelperBlobPinTests(unittest.TestCase):
    def verify_pin(self, name: str, variable: str) -> None:
        script = (HERE / "apply.ps1").read_text(encoding="utf-8")
        anchor = re.search(rf"\${re.escape(variable)}\s+-cne\s+'([a-f0-9]{{40}})'", script)
        self.assertIsNotNone(anchor, f"Missing {variable} fail-closed Git blob pin")
        source = HERE / name
        actual = subprocess.run(
            ["git", "-C", str(REPO), "hash-object", "--", str(source)],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        self.assertEqual(actual, anchor.group(1), f"{name} changed without updating apply.ps1 pin")

    def test_g1_helper_blob_pin(self) -> None:
        self.verify_pin("P1ProductionSubtitles.kt", "helperHash")

    def test_g1_unit_test_blob_pin(self) -> None:
        self.verify_pin("P1ProductionSubtitlesTest.kt", "testHash")


if __name__ == "__main__":
    unittest.main()
