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
    private fun acknowledgeP4FirstFrame(): Boolean {
        if (!acknowledged) return false
        // Only after the persisted first-frame ACK is this new registry valid.
        return true
    }
    private fun receiveP4CurrentOffer(): String {
        val choice = P1ProductionSubtitles.automaticChoice(applicationContext, r, idx)
        return try {
            receiver.receive(offer, sid, nowKey, choice)
        } catch (_: IllegalArgumentException) { "P4_INVALID" }
    }
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
        showMessage("Đang kết nối Vietsub AI với PC...", false)
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
        val savedPc = P4PairingStore(applicationContext).load()
        if (savedPc != null) {
            savedPc.deviceSecret.fill(0)
            add("Ngắt ghép đôi PC Vietsub AI (nâng cao)", "AD01.12") {
                stopP4LanSession()
                val revoked = P4PairingStore(applicationContext).revoke()
            }
        }
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

    def test_one_film_button_enables_paired_signal_and_request(self):
        self.assertIn('getBoolean(ENABLED, false)', self.kt)
        self.assertIn('if (!enabled(ctx)', self.kt)
        self.assertIn('P4PairingStore(ctx).load()', self.kt)
        self.assertIn('P3SelectedMediaPublisher.setEnabled(', self.patched)
        self.assertIn('P4OwnerBootstrap.consume(applicationContext)', self.patched)
        self.assertIn('P3SelectedMediaPublisher.setEnabled(applicationContext, true)', self.patched)
        self.assertLess(
            self.patched.index('P3SelectedMediaPublisher.setEnabled(applicationContext, true)'),
            self.patched.index('val allowed = enabled && P3SelectedMediaPublisher.requestViewer('),
        )
        self.assertNotIn('"Bật tín hiệu tự tìm Vietsub"', self.patched)
        self.assertEqual(self.patched.count('"AD01.10"'), 1)
        self.assertEqual(self.patched.count('"AD01.12"'), 1)
        self.assertNotIn('"AD01.13"', self.patched)
        self.assertIn('if (savedPc != null)', self.patched)
        self.assertIn('P3SelectedMediaPublisher.setEnabled(applicationContext, false)', self.patched)

    def test_unpair_is_advanced_and_revokes_signal_before_key(self):
        self.assertIn('"Ngắt ghép đôi PC Vietsub AI (nâng cao)"', self.patched)
        self.assertNotIn('"Hủy ghép đôi PC Vietsub AI"', self.patched)
        self.assertLess(self.patched.index('P3SelectedMediaPublisher.setEnabled(applicationContext, false)',
                                           self.patched.index('"AD01.12"')),
                        self.patched.index('P4PairingStore(applicationContext).revoke()'))
        bootstrap = (HERE.parent / "p2-aisub" /
                     "auto_pair_owner_redmi_adb.ps1").read_text("utf-8")
        self.assertNotIn('P4_ONE_OWNER_PC_ALREADY_STAGED=true', bootstrap)
        self.assertIn('P4_PRIOR_STAGE_RECEIPT_NOT_CURRENT_PAIR_PROOF=true', bootstrap)
        self.assertIn('P4_SINGLE_OWNER_LAPTOP_PRIVATE_BOOTSTRAP_STAGED=true', bootstrap)

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
        # OFF at activity creation may not permanently kill the 3s status
        # sampler: enabling Vietsub AI during playback must resume it.
        self.assertIn('if (P3SelectedMediaPublisher.enabled(applicationContext)) {', self.patched)
        self.assertNotIn('!P3SelectedMediaPublisher.enabled(applicationContext)) return', self.patched)
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
        for stage in ('P4_TV_ACTIVATE_NOT_READY', 'P4_TV_SESSION_ACCEPTED',
                      'P4_TV_OFFER_RECEIVED_UNVERIFIED', 'P4_TV_G2_FIRST_FRAME_ACK'):
            self.assertIn(stage, self.patched)
        self.assertNotIn('item.title', self.kt)
        self.assertNotIn('"video_filename"', self.kt)

    def test_real_viewer_button_starts_request_not_p4_opt_in(self):
        self.assertIn("P3SelectedMediaPublisher.requestViewer(", self.patched)
        self.assertIn('"VIEWER_VIETSUB_REQUESTED"', self.kt)
        self.assertIn("current.requestedByViewer = true", self.kt)
        self.assertIn('val choice = if (isSame && current.requestedByViewer &&', self.kt)
        self.assertIn('nativeChoice != "ON") "REQUESTED" else nativeChoice', self.kt)
        self.assertIn("sample(ctx, request, selectedIndex, nativeVlc)", self.kt)
        self.assertIn('enqueue(ctx.applicationContext, current, "VIEWER_VIETSUB_REQUESTED", onDelivery)', self.kt)
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

    def test_retry_never_repeats_connecting_to_pc_toast(self):
        # P4 activation still polls for a source; a P3 viewer request keeps
        # the connecting toast quiet throughout the 15-second retry cycle.
        self.assertIn(self.p.P4_CONNECTING_REPLACEMENT, self.patched)
        self.assertEqual(self.patched.count('"Đang kết nối Vietsub AI với PC..."'), 1)
        self.assertIn('p3ActivationTick.run()', self.patched)
        self.assertIn('p3LastDelivery: Boolean? = null', self.patched)

    def test_p3_http_receipt_or_failure_delivered_once_per_state(self):
        publisher = self.kt.split('private fun enqueue(', 1)[1].split(
            'private fun postOnce(', 1)[0]
        post = self.kt.split('private fun postOnce(', 1)[1].split(
            'private fun postStatusOnce(', 1)[0]
        self.assertIn('delivered = postOnce(paired, selected, kind)', publisher)
        self.assertIn('onDelivery?.invoke(delivered)', publisher)
        self.assertIn('active === selected && selected.requestedByViewer', publisher)
        self.assertIn('postJson(paired, "/p3/selection", body)\n        return true', post)
        self.assertIn('if (p3LastDelivery == acknowledged)', self.patched)
        self.assertIn('session.request !== expected', self.patched)
        self.assertIn('"PC đã nhận tín hiệu tìm Vietsub. Đang chờ phụ đề..."', self.patched)
        self.assertIn('"PC chưa xác nhận yêu cầu Vietsub. Sẽ tự thử lại."', self.patched)
        self.assertIn('p3LastDelivery = null', self.patched)

    def test_manual_off_other_invalidates_inflight_p4_before_source_ready(self):
        self.assertIn("P1ProductionSubtitles.automaticChoice(", self.patched)
        self.assertIn('index()) != "ON") {', self.patched)
        self.assertIn("p4ActivationGeneration++", self.patched)
        self.assertIn("p4ActivationInFlight = false", self.patched)
        self.assertIn("if (p4LanScope != null) unbindP4Session()", self.patched)
        self.assertIn("P3SelectedMediaPublisher.cancelViewer(", self.patched)
        # Do not call stopP4LanSession: it would force 'off' and override
        # the viewer's manually selected OTHER-language subtitle.
        self.assertNotIn("if (p4LanScope != null) stopP4LanSession()\n        }", self.patched)

    def test_off_revokes_previously_queued_signed_consent_before_send(self):
        # This source contract protects both the status executor and the
        # event executor; a test of HMAC alone cannot catch stale queue work.
        cancel = self.kt.split("internal fun cancelViewer(", 1)[1].split(
            "/** A signed close", 1)[0]
        self.assertLess(cancel.index("current.requestedByViewer = false"),
                        cancel.index("generation.incrementAndGet()"))
        self.assertLess(cancel.index("generation.incrementAndGet()"),
                        cancel.index("sample(ctx, request"))
        status = self.kt.split("private fun enqueueStatus(", 1)[1].split(
            "private fun randomHex", 1)[0]
        selected = self.kt.split("private fun enqueue(", 1)[1].split(
            "private fun postOnce", 1)[0]
        self.assertGreaterEqual(status.count("generation.get() != gen"), 2)
        self.assertGreaterEqual(selected.count("generation.get() != gen"), 2)
        self.assertGreaterEqual(status.count("!selected.requestedByViewer"), 2)
        self.assertGreaterEqual(selected.count("!selected.requestedByViewer"), 2)
        # Signed close and final inactive status are intentionally retained:
        # clearing a request must not suppress lifecycle teardown.
        self.assertIn("(isActive && active !== selected)", status)
        self.assertIn('kind != "PLAYBACK_CLOSED" && active !== selected', selected)

    def test_p4_source_guards_apply_once_and_fail_closed_on_drift(self):
        with self.assertRaisesRegex(ValueError, "P3_ACTIVITY_ALREADY_APPLIED"):
            self.p.patch_activity(self.patched)
        for old in (self.p.FIELD, self.p.CHOICE, self.p.LOAD, self.p.ITEM, self.p.CLOSE, self.p.MENU, self.p.P4_BUTTON, self.p.P4_CONNECTING_MESSAGE, self.p.P4_PENDING_MESSAGE, self.p.P4_SUCCESS):
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
