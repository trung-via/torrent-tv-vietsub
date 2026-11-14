"""P3 TV publisher patch: source-only synthetic P4 app fixture tests."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def patcher():
    file = HERE / "p3_activity_patch.py"
    spec = importlib.util.spec_from_file_location("p3_tv_overlay", file)
    if spec is None or spec.loader is None:
        raise RuntimeError("P3_PATCHER_MISSING")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def fake_p4_activity() -> str:
    return """// Synthetic G1+G2+P4 activity, NOT a live APK
class PlayerActivity {
    private var g2Recovery: G2RefreshRecovery? = null
    internal fun receiveP4Revision(offer: P4SubtitleOffer): String { return "" }
    override fun trackChosen(choice: TrackChoice) {
        if (!closedSent && ::session.isInitialized) P1ProductionSubtitles.noteTrackChoice(this, session.request, index(), choice)
    }
    private fun load(r: PlayRequest, choose: Boolean = true) {
        P4OwnerBootstrap.consume(applicationContext)
        session.load(production.request, next)
        flow.reset()
    }
    private fun playItem(i: Int) {
        if (!switcher.goTo(i, itemTransition?.picks)) return
        cancelCountdown()
    }
    private fun emitClosed(replaced: Boolean) {
        closedSent = true
        commitPendingSeek()
    }
    private fun beginP4Activation() {
        runOnUiThread {
                if (result == null) {
                    showMessage("PC chưa sẵn sàng hoặc chưa có phụ đề nguồn cho phim.", true)
                    return@runOnUiThread
                }
                result.sessionSecret.fill(0)
                showMessage(
                    if (started) "Đã bật Vietsub AI. Đang chờ bản dịch đầu tiên..."
                    else "Phim đã đổi hoặc không thể bật Vietsub AI.", !started)
        }
    }
    private fun openMenu() {
        add(if (p4LanScope != null || p4ActivationInFlight)
                 "Tắt Vietsub AI" else "Bật Vietsub AI", "AD01.10") {
            if (p4LanScope != null) {
                stopP4LanSession()
                showMessage("Đã tắt Vietsub AI cho phim này.", false)
            } else if (p4ActivationInFlight) {
                p4ActivationGeneration++
                p4ActivationInFlight = false
                showMessage("Đã hủy yêu cầu Vietsub AI.", false)
            } else {
                beginP4Activation()
            }
        }
        add("Hủy ghép đôi PC Vietsub AI", "AD01.12") {}
    }
}
"""


class P3TvSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p = patcher()
        cls.kt = (HERE / "P3SelectedMediaPublisher.kt").read_text("utf-8")
        cls.patched = cls.p.patch_activity(fake_p4_activity())

    def test_only_actual_accepted_load_and_successful_next_emit(self):
        self.assertIn('session.load(production.request, next)\n        P3SelectedMediaPublisher.accepted(', self.patched)
        self.assertIn('if (!switcher.goTo(i, itemTransition?.picks)) return\n        P3SelectedMediaPublisher.accepted(', self.patched)
        self.assertEqual(self.patched.count("P3SelectedMediaPublisher.accepted("), 2)
        self.assertIn('P3SelectedMediaPublisher.closed(applicationContext)', self.patched)
        self.assertNotIn("P3SelectedMediaPublisher.accepted(", fake_p4_activity())

    def test_pause_resume_seek_dont_trigger_signal(self):
        for word in ("pause", "resume", "seek"):
            self.assertNotIn("P3SelectedMediaPublisher." + word, self.patched)
        self.assertIn('NEXT_QUEUE_ITEM_ACCEPTED', self.patched)
        self.assertIn('PLAY_REQUEST_ACCEPTED', self.patched)
        self.assertIn('PLAYBACK_CLOSED', self.kt)

    def test_explicit_owner_consent_off_by_default_and_owner_menu(self):
        self.assertIn('getBoolean(ENABLED, false)', self.kt)
        self.assertIn('if (!enabled(ctx)', self.kt)
        self.assertIn('P4PairingStore(ctx).load()', self.kt)
        self.assertIn('P3SelectedMediaPublisher.setEnabled(', self.patched)
        self.assertIn('"Bật tín hiệu tự tìm Vietsub"', self.patched)
        self.assertNotIn('setEnabled(applicationContext, true)', self.patched)

    def test_private_certificate_pinned_transport_only(self):
        self.assertIn('P4PinnedTls.open(url, paired.certPinSha256)', self.kt)
        self.assertIn('P4LanClient.isPrivateIPv4(paired.host)', self.kt)
        self.assertIn('conn.instanceFollowRedirects = false', self.kt)
        self.assertIn('P3_OWNER_ENDPOINT_NOT_READY', self.kt)
        self.assertIn('/p3/selection', self.kt)
        self.assertNotIn('http://', self.kt)
        self.assertNotIn('ServerSocket(', self.kt)
        self.assertNotIn('BroadcastReceiver', self.kt)
        self.assertNotIn('Log.', self.kt)

    def test_proposed_hmac_and_session_are_domain_separated(self):
        self.assertIn('private const val SCHEMA = "TTV-P3-TV-SELECTION-V1"', self.kt)
        self.assertIn('Mac.getInstance("HmacSHA256")', self.kt)
        self.assertIn('val selected = Current(randomHex(), hash, fileIndex, kind)', self.kt)
        self.assertIn('P4PairingStore.Pairing', self.kt)
        self.assertIn('Random', self.kt)
        self.assertIn('sent_at_ms', self.kt)
        self.assertIn('tv_session_id', self.kt)
        self.assertIn('torrent_hash', self.kt)
        self.assertIn('file_index', self.kt)
        self.assertIn('nonce', self.kt)
        self.assertNotIn('"video_filename"', self.kt)
        self.assertNotIn('item.title', self.kt)
        self.assertNotIn('request.session', self.kt)

    def test_true_current_status_samples_exact_native_and_g1_choice(self):
        self.assertIn("private val p3StatusTick =", self.patched)
        self.assertIn("handler.postDelayed(this, 3_000L)", self.patched)
        self.assertIn("handler.removeCallbacks(p3StatusTick)", self.patched)
        self.assertEqual(self.patched.count("P3SelectedMediaPublisher.sample("), 4)
        self.assertIn("P1ProductionSubtitles.automaticChoice(", self.kt)
        self.assertIn("request?.queue?.getOrNull(selectedIndex)", self.kt)
        self.assertIn("engine is VlcEngine", self.patched)
        self.assertIn('private const val STATUS_SCHEMA = "TTV-P3-TV-STATE-V1"', self.kt)
        self.assertIn('postJson(paired, "/p3/state", body)', self.kt)
        self.assertIn('postJson(paired, "/p3/selection", body)', self.kt)
        self.assertIn('private val bootId = randomHex()', self.kt)
        self.assertIn('private val statusSequence = AtomicLong(0L)', self.kt)
        self.assertIn('val sampledAt = android.os.SystemClock.elapsedRealtime()', self.kt)
        self.assertIn('STATUS_TIMEOUT_MS = 2_000L', self.kt)
        self.assertNotIn('item.title', self.kt)
        self.assertNotIn('"video_filename"', self.kt)

    def test_real_viewer_button_starts_request_not_p4_opt_in(self):
        self.assertIn("P3SelectedMediaPublisher.requestViewer(", self.patched)
        self.assertIn('"VIEWER_VIETSUB_REQUESTED"', self.kt)
        self.assertIn("current.requestedByViewer = true", self.kt)
        self.assertIn('val choice = if (isSame && current.requestedByViewer &&', self.kt)
        self.assertIn('nativeChoice != "ON") "REQUESTED" else nativeChoice', self.kt)
        self.assertIn("sample(ctx, request, selectedIndex, nativeVlc)", self.kt)
        self.assertIn('enqueue(ctx.applicationContext, current, "VIEWER_VIETSUB_REQUESTED")', self.kt)
        self.assertNotIn('P1ProductionSubtitles.setAutomaticOptIn(', self.kt)

    def test_source_wait_uses_only_bounded_original_p4_activation(self):
        self.assertIn("private val p3ActivationTick =", self.patched)
        self.assertIn("p3ActivationAttempts >= 120", self.patched)
        self.assertIn("handler.postDelayed(this, 15_000L)", self.patched)
        self.assertIn("beginP4Activation()", self.patched)
        self.assertIn("P3SelectedMediaPublisher.reaffirmViewer(", self.patched)
        self.assertIn("P3SelectedMediaPublisher.cancelViewer(", self.patched)
        self.assertIn("handler.removeCallbacks(p3ActivationTick)", self.patched)
        self.assertIn("p4ActivationGeneration++", self.patched)
        self.assertNotIn("startP4LanSession(", self.patched)

    def test_p4_source_guards_apply_once_and_fail_closed_on_drift(self):
        with self.assertRaisesRegex(ValueError, "P3_ACTIVITY_ALREADY_APPLIED"):
            self.p.patch_activity(self.patched)
        for old in (self.p.FIELD, self.p.CHOICE, self.p.LOAD, self.p.ITEM, self.p.CLOSE, self.p.MENU, self.p.P4_BUTTON, self.p.P4_PENDING_MESSAGE, self.p.P4_SUCCESS):
            with self.subTest(old=old[:30]):
                with self.assertRaises(ValueError):
                    self.p.patch_activity(fake_p4_activity().replace(old, "DRIFT", 1))
        with self.assertRaisesRegex(ValueError, "REQUIRES_EXACT_P4"):
            self.p.patch_activity(fake_p4_activity().replace(
                "internal fun receiveP4Revision(", "internal fun missing("))

    def test_source_apply_is_explicit_and_disposable_only(self):
        with tempfile.TemporaryDirectory(prefix="p3-compose-test-") as t:
            root = Path(t).resolve()
            pkg = root / self.p.PKG
            pkg.mkdir(parents=True)
            names = ["P4PinnedTls.kt", "P4PairingStore.kt", "P4LanClient.kt",
                     "P4ActivationClient.kt"]
            for name in names:
                (pkg / name).write_text("synthetic p4 dependency", encoding="utf-8")
            target = pkg / "PlayerActivity.kt"
            target.write_text(fake_p4_activity(), encoding="utf-8")
            original = target.read_bytes()
            self.assertEqual(self.p.run(root, apply=False), "P3_NATIVE_SOURCE_DRY_RUN_PASS")
            self.assertEqual(target.read_bytes(), original)
            self.assertFalse((pkg / "P3SelectedMediaPublisher.kt").exists())
            self.assertEqual(self.p.run(root, apply=True),
                             "P3_NATIVE_SOURCE_APPLIED_DISPOSABLE_ONLY")
            self.assertEqual(target.read_text("utf-8"), self.patched)
            self.assertEqual((pkg / "P3SelectedMediaPublisher.kt").read_bytes(),
                             (HERE / "P3SelectedMediaPublisher.kt").read_bytes())
            with self.assertRaisesRegex(ValueError, "ALREADY_EXISTS"):
                self.p.run(root, apply=True)


if __name__ == "__main__":
    unittest.main()
