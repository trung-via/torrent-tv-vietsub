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

    def test_voiceover_timeline_native_seek_pause_buffer(self):
        compiler = shutil.which("kotlinc")
        runtime = shutil.which("kotlin")
        self.assertIsNotNone(compiler, "KOTLINC_REQUIRED_FOR_VOICE_GATE")
        self.assertIsNotNone(runtime, "KOTLIN_REQUIRED_FOR_VOICE_GATE")
        with tempfile.TemporaryDirectory(prefix="ttv-voice-clock-") as work:
            classes = Path(work) / "classes"
            result = subprocess.run([
                compiler, str(ROOT / "P4VoiceoverTimeline.kt"),
                str(ROOT / "P4VoiceoverTimelineSmoke.kt"),
                "-d", str(classes),
            ], capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr[-2000:])
            result = subprocess.run([
                runtime, "-classpath", str(classes),
                "com.spacesarmat.omp.player.P4VoiceoverTimelineSmokeKt",
            ], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stderr[-2000:])
            self.assertIn(
                "P4_VOICEOVER_VLC_CLOCK_SEEK_PAUSE_BUFFER_PASS_NOT_TV_AUDIO",
                result.stdout)

    def test_player_activity_voice_source_is_injected_and_scoped(self):
        import importlib.util
        from test_p4_overlay import fake_g2_activity
        spec = importlib.util.spec_from_file_location(
            "voice_activity_patch", ROOT / "activity_patch.py")
        assert spec is not None and spec.loader is not None
        patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patch)
        activity = patch.patch_activity(fake_g2_activity())
        for expected in (
            "private val p4VoiceTick = object : Runnable",
            "p4VoiceController?.close()",
            "handler.removeCallbacks(p4VoiceTick)",
            "P4VoiceoverController(",
            "setP4VoiceMode(\"VOICE\")",
            "setP4VoiceMode(\"BOTH\")",
            "setP4VoiceMode(\"ORIGINAL\")",
            "p4VoiceoverDuck(audible)",
            "engine.positionMs",
            "engine.isBuffering",
            "session.firstFrame",
            "engine.selectSubtitle(null)",
            "p4VoiceSubHidden = false",
        ):
            self.assertIn(expected, activity)
        self.assertNotIn("ServerSocket", activity)
        self.assertEqual(activity.count("private val p4VoiceTick"), 1)

    def test_pcm_renderer_prepares_off_main_and_releases_on_switch(self):
        src = (ROOT / "P4VoiceoverAudioTrack.kt").read_text("utf-8")
        controller = (ROOT / "P4VoiceoverController.kt").read_text("utf-8")
        composer = (ROOT / "apply.py").read_text("utf-8")
        for item in ("AudioTrack.MODE_STATIC", "CHANNEL_OUT_MONO",
                     "ENCODING_PCM_16BIT", "AudioTrack.WRITE_BLOCKING",
                     "P4VoiceoverTimeline.decision", "internal fun reset()"):
            self.assertIn(item, src)
        for item in ("receiver.verify(offer, sid, mediaKey)",
                     "P4VoiceoverLanClient.wav(", "Prepared.fromWav",
                     "P4VoiceoverTimeline.discontinuity",
                     "receiver.resetForSeek(", "secret.fill(0)",
                     "player.close()"):
            self.assertIn(item, controller)
        for file in ("VOICE_AUDIO_FILE", "VOICE_CLOCK_FILE",
                     "VOICE_CONTROLLER_FILE"):
            self.assertIn(file, composer)
        self.assertIn("private fun setAudio(es: Int)", composer)
        self.assertIn("mp.volume = original * 30 / 100", composer)
        self.assertIn("p4VoiceOriginalVolume?.let { mp.volume = it }", composer)

    def test_explicit_seek_hooks_reset_voice_without_discovery(self):
        import importlib.util
        from test_p4_overlay import fake_g2_activity
        spec = importlib.util.spec_from_file_location("p4_voice_seek", ROOT / "activity_patch.py")
        assert spec is not None and spec.loader is not None
        patch = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(patch)
        src = fake_g2_activity() + "\nengine.seekTo(t)\nengine.seekTo(t)\nseeker.take()?.let { engine.seekTo(it) }\n"
        patched = patch.patch_activity(src)
        self.assertEqual(patched.count("p4ResetVoiceOnSeek(); engine.seekTo(t)"), 2)
        self.assertIn("p4ResetVoiceOnSeek(); engine.seekTo(it)", patched)

    def test_static_track_writes_pcm_before_initialized_gate(self):
        src = (ROOT / "P4VoiceoverAudioTrack.kt").read_text("utf-8")
        a = src.index("track.state == AudioTrack.STATE_UNINITIALIZED")
        b = src.index("track.write(wav", a)
        d = src.index("track.state != AudioTrack.STATE_INITIALIZED", b)
        self.assertLess(a, b)
        self.assertLess(b, d)

    def test_android_client_is_composed_into_original_omp_player_only(self):
        client = (ROOT / "P4VoiceoverLanClient.kt").read_text("utf-8")
        composer = (ROOT / "apply.py").read_text("utf-8")
        self.assertIn('VOICE_RECEIVER_FILE = "P4VoiceoverReceiver.kt"', composer)
        self.assertIn('VOICE_LAN_CLIENT_FILE = "P4VoiceoverLanClient.kt"', composer)
        self.assertIn("VOICE_RECEIVER_FILE, VOICE_LAN_CLIENT_FILE", composer)
        self.assertIn("P4PinnedTls.open", client)
        self.assertIn("TTV-P4-VOICE-READ-V1", client)
        self.assertIn("P4VoiceoverOffer(", client)
        self.assertIn("P4_VOICE_WAV_HASH_INVALID", client)
        for forbidden in ("ServerSocket", "WebView", "BroadcastReceiver",
                          "http://", "startService(", "ACTION_VIEW"):
            self.assertNotIn(forbidden, client)

    def test_no_android_socket_or_external_player_in_policy(self):
        content = (ROOT / "P4VoiceoverReceiver.kt").read_text("utf-8")
        for forbidden in ("ServerSocket", "HttpURLConnection",
                          "BroadcastReceiver", "android.media", "TorrServer"):
            self.assertNotIn(forbidden, content)
        self.assertIn("MessageDigest.isEqual", content)
        self.assertIn("P4_VOICE_DEFERRED_USER_CHOICE", content)


if __name__ == "__main__":
    unittest.main()
