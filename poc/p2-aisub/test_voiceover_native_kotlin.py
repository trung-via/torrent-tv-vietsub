"""Compile the new native Ngọc Linh HMAC/session receiver as a JVM smoke.

This is not a soundbar, Android APK or Owner runtime acceptance test.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1] / "p4-auto-sub"


class NativeVoiceoverContract(unittest.TestCase):
    def test_native_cross_language_voice_contract(self):
        compiler = shutil.which("kotlinc")
        runner = shutil.which("kotlin")
        self.assertIsNotNone(compiler, "KOTLINC_REQUIRED_FOR_VOICE_GATE")
        self.assertIsNotNone(runner, "KOTLIN_REQUIRED_FOR_VOICE_GATE")
        with tempfile.TemporaryDirectory(prefix="ttv-native-voice-") as work:
            classes = Path(work) / "classes"
            result = subprocess.run(
                [compiler, str(ROOT / "P4VoiceoverReceiver.kt"),
                 str(ROOT / "P4VoiceoverReceiverSmoke.kt"), "-d", str(classes)],
                capture_output=True, text=True, timeout=90,
            )
            self.assertEqual(
                result.returncode, 0,
                "P4_VOICEOVER_COMPILE_FAILED " + result.stderr[-2000:])
            result = subprocess.run(
                [runner, "-classpath", str(classes),
                 "com.spacesarmat.omp.player.P4VoiceoverReceiverSmokeKt"],
                capture_output=True, text=True, timeout=20,
            )
            self.assertEqual(
                result.returncode, 0,
                "P4_VOICEOVER_SMOKE_FAILED " + result.stderr[-2000:])
            self.assertIn(
                "P4_VOICEOVER_NATIVE_HMAC_AND_SESSION_PASS_NOT_TV_AUDIO",
                result.stdout)

    def test_no_android_socket_or_external_player_in_policy(self):
        content = (ROOT / "P4VoiceoverReceiver.kt").read_text("utf-8")
        for forbidden in ("ServerSocket", "HttpURLConnection",
                          "BroadcastReceiver", "android.media", "TorrServer"):
            self.assertNotIn(forbidden, content)
        self.assertIn("MessageDigest.isEqual", content)
        self.assertIn("P4_VOICE_DEFERRED_USER_CHOICE", content)


if __name__ == "__main__":
    unittest.main()
