from pathlib import Path
import tempfile
import unittest
from apply import G2_CALLBACK, patch_activity, run

G1 = '''class PlayerActivity {
    private val sidecarPicker = registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        val r = session.request ?: return@registerForActivityResult
        val idx = index()
        Thread {
            val saved = try {
                P1ProductionSubtitles.importSelected(applicationContext, uri, r, idx)
            } catch (_: Exception) { false }
            runOnUiThread {
                if (!isFinishing && !isDestroyed) showMessage(
                    if (saved) "Đã lưu Vietsub. Mở lại phim để sử dụng."
                    else "Không thể đọc file SRT/VTT UTF-8.", !saved
                )
            }
        }.start()
    }
    private var closedSent = false
    override fun onFirstFrameShown() {
        render()
    }
    override fun engineFailed(kind: ErrorKind, detail: String, beforeFirstFrame: Boolean): Boolean {
        return false
    }
    private fun load(r: PlayRequest, choose: Boolean = true) {
        session.load(r)
    }
    private fun playItem(i: Int) {
        val q = session.request?.queue
        if (q == null || i !in q.indices || i == session.index) return
        session.goTo(i)
    }
}
'''

class TestG2Patch(unittest.TestCase):
    def test_valid_g1_callback_patched_once(self):
        result = patch_activity(G1)
        self.assertEqual(result.count('G2RefreshInPlace.prepare'), 1)
        self.assertEqual(result.count('P1ProductionSubtitles.importSelected'), 1)
        self.assertEqual(result.count('runOnUiThread'), 2)  # label in return and call
        self.assertIn('session.load(refreshed)', result)
        self.assertIn('g2Before = G2RefreshRecovery.capture(applicationContext, r, idx)', result)
        self.assertIn('g2Before != null && P1ProductionSubtitles.importSelected', result)
        self.assertIn('if (rollbackG2Refresh()) return true', result)
        self.assertIn('handler.postDelayed(g2RecoveryTimeout, 25_000L)', result)
        self.assertIn('g2Recovery?.matchesCurrent(session.request, index())', result)
        self.assertIn('current !== r', result)
        self.assertIn('item.copy(resumeMs = session.resumeOf(i))', result)
        self.assertIn('if (wasPaused) engine.pause()', result)
        self.assertIn('g2Before.restoreOldFile()', result)
        self.assertNotIn('if (!isFinishing && !isDestroyed) showMessage(',result)

    def test_unexpected_callback_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'UNEXPECTED_G1'):
            patch_activity(G1.replace('if (saved)', 'if (somethingElse)'))

    def test_reapply_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'G2_ALREADY_PRESENT'):
            patch_activity(patch_activity(G1))

    def test_missing_old_anchor_fails_closed(self):
        with self.assertRaisesRegex(ValueError,'G1_PICKER_ANCHOR'):
            patch_activity(G1.replace('importSelected','importChanged'))

    def test_dry_run_is_read_only(self):
        with tempfile.TemporaryDirectory(prefix='p1-g1-prod-') as d:
            root=Path(d); p=root / 'android/app/src/main/java/com/spacesarmat/omp/player'; p.mkdir(parents=True)
            f=p/'PlayerActivity.kt'; f.write_text(G1,encoding='utf8')
            (p/'P1ProductionSubtitles.kt').write_text('internal object P1ProductionSubtitles { fun importSelected() {} }')
            run(root,False)
            self.assertEqual(f.read_text(encoding='utf-8'),G1)
            self.assertFalse((p/'G2RefreshInPlace.kt').exists())

    def test_apply_changes_bounded_source(self):
        with tempfile.TemporaryDirectory(prefix='p1-g1-prod-') as d:
            root=Path(d); p=root / 'android/app/src/main/java/com/spacesarmat/omp/player'; p.mkdir(parents=True)
            f=p/'PlayerActivity.kt'; f.write_text(G1,encoding='utf8')
            (p/'P1ProductionSubtitles.kt').write_text('internal object P1ProductionSubtitles { fun importSelected() {} }')
            run(root,True)
            self.assertIn('G2RefreshDecision.matchesCurrent',f.read_text(encoding='utf-8'))
            self.assertTrue((p/'G2RefreshInPlace.kt').is_file())
            self.assertTrue((p/'G2RefreshDecision.kt').is_file())
            self.assertTrue((p/'G2RefreshRecovery.kt').is_file())

    def test_recovery_hooks_required_fails_closed(self):
        for missing in (
            'private var closedSent = false',
            'override fun onFirstFrameShown() {',
            'override fun engineFailed(kind: ErrorKind, detail: String, beforeFirstFrame: Boolean): Boolean {',
            'private fun load(r: PlayRequest, choose: Boolean = true) {',
            '        if (q == null || i !in q.indices || i == session.index) return',
        ):
            with self.subTest(anchor=missing):
                with self.assertRaisesRegex(ValueError, 'G2_RECOVERY_EVENT_ANCHOR'):
                    patch_activity(G1.replace(missing, '// anchor drift', 1))

    def test_recovery_hook_injection_bounded(self):
        result = patch_activity(G1)
        self.assertEqual(result.count('private var g2Recovery:'), 1)
        self.assertEqual(result.count('fun rollbackG2Refresh()'), 1)
        self.assertEqual(result.count('val g2Before = G2RefreshRecovery.capture'), 1)
        self.assertEqual(result.count('handler.postDelayed(g2RecoveryTimeout, 25_000L)'), 1)
        self.assertNotIn('P1ProductionSubtitles.removeSaved(', result)

    def test_wrong_directory_blocked(self):
        with tempfile.TemporaryDirectory(prefix='other-') as d:
            with self.assertRaisesRegex(ValueError,'DISPOSABLE_G1'):
                run(Path(d),True)

if __name__ == '__main__': unittest.main()