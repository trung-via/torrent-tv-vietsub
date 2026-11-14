"""P4 native receiver Kotlin/JVM smoke, no TV or provider access."""
from __future__ import annotations

import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1] / "p4-auto-sub"


class NativeP4ContractTest(unittest.TestCase):
    def test_kotlin_receiver_matches_python_hmac_and_timeline_contract(self):
        compiler = shutil.which("kotlinc")
        runtime = shutil.which("kotlin")
        self.assertIsNotNone(compiler, "KOTLINC_REQUIRED_FOR_P4_NATIVE_GATE")
        self.assertIsNotNone(runtime, "KOTLIN_RUNTIME_REQUIRED_FOR_P4_NATIVE_GATE")
        with tempfile.TemporaryDirectory(prefix="ttv-p4-kotlin-") as temp:
            classes = pathlib.Path(temp) / "classes"
            build = subprocess.run(
                [compiler, str(ROOT / "P4SignedReceiver.kt"),
                 str(ROOT / "P4SignedReceiverSmoke.kt"), "-d", str(classes)],
                capture_output=True, text=True, timeout=90,
            )
            self.assertEqual(build.returncode, 0, "P4_KOTLIN_COMPILE_FAILED " +
                             (build.stderr[-1500:] if build.stderr else ""))
            run = subprocess.run(
                [runtime, "-classpath", str(classes),
                 "com.spacesarmat.omp.player.P4SignedReceiverSmokeKt"],
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(run.returncode, 0, "P4_NATIVE_SMOKE_FAILED " +
                             (run.stderr[-1500:] if run.stderr else ""))
            self.assertIn("P4_NATIVE_SIGNED_RECEIVER_SYNTHETIC_PASS", run.stdout)

    def test_no_sockets_or_untrusted_receiver_exports(self):
        text = (ROOT / "P4SignedReceiver.kt").read_text(encoding="utf-8")
        self.assertNotIn("ServerSocket", text)
        self.assertNotIn("BroadcastReceiver", text)
        self.assertNotIn("http://", text)
        self.assertNotIn("ACTION_VIEW", text)
        self.assertIn("MessageDigest.isEqual", text)
        self.assertIn("DEFERRED_USER_SUBTITLE_CHOICE", text)


if __name__ == "__main__":
    unittest.main()
