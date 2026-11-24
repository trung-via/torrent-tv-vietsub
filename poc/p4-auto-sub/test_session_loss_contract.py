"""P4 session-loss repair: source-pinned offline safety regressions.

Static checks + actual Activity overlay application on a synthetic G2 source.
These are NOT Android Gradle, Redmi LAN or automatic-reconnect E2E tests.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


HERE = Path(__file__).resolve().parent
P2_TEST = HERE.parent / "p2-aisub" / "test_p4_overlay.py"


def fixture():
    spec = importlib.util.spec_from_file_location("p4_original_overlay_test", P2_TEST)
    if spec is None or spec.loader is None:
        raise RuntimeError("P4_G2_TEST_FIXTURE_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.fake_g2_activity()


def patcher():
    spec = importlib.util.spec_from_file_location("p4_activity_reliability", HERE / "activity_patch.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("P4_ACTIVITY_PATCH_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class P4SessionLossContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lan = (HERE / "P4LanClient.kt").read_text(encoding="utf-8")
        cls.src = (HERE / "activity_patch.py").read_text(encoding="utf-8")
        cls.activity = patcher().patch_activity(fixture())
        cls.poll = cls.activity.split("private val p4LanPoll =", 1)[1].split(
            "private fun beginP4Activation()", 1)[0]

    def test_204_means_valid_empty_revision_only(self):
        self.assertIn("204 -> return null", self.lan)
        self.assertIn("200 -> Unit", self.lan)

    def test_404_is_expired_session_not_empty_poll(self):
        self.assertIn("404 -> throw P4LanSessionExpired()", self.lan)
        self.assertIn('P4_LAN_SESSION_EXPIRED', self.lan)
        self.assertIn("catch (_: P4LanSessionExpired)", self.activity)

    def test_401_and_403_are_auth_failure_not_transient(self):
        self.assertIn("401, 403 -> throw P4LanAuthorizationRejected()", self.lan)
        self.assertIn('P4_LAN_AUTH_REJECTED', self.lan)
        self.assertIn("catch (_: P4LanAuthorizationRejected)", self.activity)

    def test_temporary_failure_keeps_bounded_polling(self):
        self.assertIn("catch (_: Exception)", self.poll)
        self.assertIn("handler.postDelayed(this, 6_000L)", self.poll)
        self.assertIn("if (terminalFailure != null)", self.poll)

    def test_terminal_failure_revokes_only_session_not_user_choice(self):
        self.assertIn("unbindP4Session()", self.poll)
        self.assertIn("val stillOn =", self.poll)
        self.assertIn("automaticChoice(", self.poll)
        self.assertNotIn("setAutomaticOptIn(", self.poll)
        self.assertNotIn("stopP4LanSession()", self.poll)

    def test_no_implicit_reattachment_paid_api_or_untrusted_listener(self):
        self.assertNotIn("beginP4Activation()", self.poll)
        self.assertNotIn("P4ActivationClient.activate(", self.poll)
        self.assertNotIn("GEMINI_API_KEY", self.poll)
        self.assertNotIn("http://", self.lan)
        self.assertNotIn("ServerSocket", self.lan)

    def test_stale_in_flight_worker_does_not_change_other_media(self):
        self.assertIn("if (gen != p4LanGeneration || p4LanScope !== scope)", self.poll)
        self.assertIn("if (isFinishing || isDestroyed || closedSent)", self.poll)
        self.assertIn("if (terminalFailure != null)", self.poll)
        self.assertIn("else if (offer != null)", self.poll)

    def test_bounded_user_safe_message_does_not_log_sensitive_metadata(self):
        self.assertIn("Phiên Vietsub AI trên PC đã hết.", self.poll)
        self.assertIn("PC từ chối xác thực Vietsub AI.", self.poll)
        self.assertNotIn("Log.", self.poll)
        self.assertNotIn("printStackTrace", self.poll)
        self.assertNotIn("showMessage(scope.", self.poll)
        self.assertNotIn("showMessage(offer.", self.poll)

    def test_overlay_is_once_only_and_preserves_g2_guard(self):
        with self.assertRaisesRegex(ValueError, "P4_ACTIVITY_ALREADY_APPLIED"):
            patcher().patch_activity(self.activity)
        self.assertIn("receiver.acknowledgeOverlayInstalled(", self.activity)
        self.assertIn("P1ProductionSubtitles.rollbackAutomatic(", self.activity)
        self.assertNotIn("session.load(newRequest)", self.activity)


if __name__ == "__main__":
    unittest.main()

class P4BackgroundStyleContract(unittest.TestCase):
    def test_optional_background_uses_same_overlay_without_reload(self):
        from activity_patch import ACTIVITY_BRIDGE, P4_MENU_ROWS
        self.assertIn('getBoolean("translucent_background", false)', ACTIVITY_BRIDGE)
        self.assertIn('Color.argb(155, 0, 0, 0)', ACTIVITY_BRIDGE)
        self.assertIn('applyP4Background(this)', ACTIVITY_BRIDGE)
        self.assertIn('Nền mờ phụ đề: Bật', P4_MENU_ROWS)
        self.assertIn('Nền mờ phụ đề: Tắt', P4_MENU_ROWS)
        self.assertIn('p4OverlayView?.let { applyP4Background(it) }', P4_MENU_ROWS)
        self.assertNotIn('session.load(', P4_MENU_ROWS)

class P4SavedOverlayReopenContract(unittest.TestCase):
    def test_reopen_uses_exact_saved_ai_file_and_same_renderer(self):
        from activity_patch import ACTIVITY_BRIDGE, patch_activity
        from pathlib import Path
        root = Path(__file__).resolve().parent
        g1 = (root.parent / "g1-prod" / "P1ProductionSubtitles.kt").read_text("utf-8")
        receiver = (root / "P4SignedReceiver.kt").read_text("utf-8")
        self.assertIn('savedAutomaticOverlay(applicationContext, r, idx)', ACTIVITY_BRIDGE)
        self.assertIn('P4SignedReceiver.parseTimeline(saved.first, saved.second)', ACTIVITY_BRIDGE)
        self.assertIn('P4_TV_SAVED_OVERLAY_RESTORED', ACTIVITY_BRIDGE)
        self.assertIn('handler.postDelayed({ restoreP4SavedOverlay() }, 700L)', root.joinpath('activity_patch.py').read_text("utf-8"))
        self.assertIn('if (automaticChoice(ctx, r, i) != "ON") return null', g1)
        self.assertIn('validate(it) == Validated(ext, digest)', g1)
        self.assertIn('    companion object {\n    internal fun parseTimeline(', receiver)
        self.assertNotIn('session.load(', ACTIVITY_BRIDGE)
