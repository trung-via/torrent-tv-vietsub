"""Offline TV/owner signed-interface proof on source; not a Kotlin APK or real TV."""
from pathlib import Path
import unittest

from p3_signed_playback_signal import (
    SCHEMA as SELECTION_SCHEMA, SignedPlaybackVerifier, SignedPlaybackError,
    sign_synthetic_event,
)
from p3_redmi_current_state import (
    SCHEMA as STATE_SCHEMA, SignedRedmiStateCache, RedmiStateRejected,
    sign_synthetic_state,
)
from p3_p4_shared_https_route import P3_POST_ROUTE, P3_STATE_ROUTE

ROOT = Path(__file__).resolve().parents[2]
TV = (ROOT / "poc/p4-auto-sub/P3SelectedMediaPublisher.kt").read_text("utf-8")
OWNER = (ROOT / "poc/p2-sub-discovery/p3_signed_signal_to_owner.py").read_text("utf-8")
HANDLER = (ROOT / "poc/p2-sub-discovery/p3_p4_shared_https_route.py").read_text("utf-8")
KEY = bytes(range(32))
NOW = 1760000000000
SESSION = "1" * 32
INFOHASH = "a" * 40


class CrossLaneContractTests(unittest.TestCase):
    def test_tv_owner_hmac_domains_match_and_remain_separate(self):
        self.assertIn('private const val SCHEMA = "' + SELECTION_SCHEMA + '"', TV)
        self.assertIn('private const val STATUS_SCHEMA = "' + STATE_SCHEMA + '"', TV)
        self.assertNotEqual(SELECTION_SCHEMA, STATE_SCHEMA)

    def test_original_p4_paired_https_transport_reused(self):
        self.assertEqual((P3_POST_ROUTE, P3_STATE_ROUTE),
                         ("/p3/selection", "/p3/state"))
        self.assertIn('postJson(paired, "/p3/selection", body)', TV)
        self.assertIn('postJson(paired, "/p3/state", body)', TV)
        self.assertIn("P4PinnedTls.open(url, paired.certPinSha256)", TV)
        self.assertIn("return super().do_POST()", HANDLER)

    def test_viewer_request_is_distinct_from_play(self):
        self.assertIn('"VIEWER_VIETSUB_REQUESTED"', TV)
        self.assertIn('if signal.kind != "VIEWER_VIETSUB_REQUESTED":', OWNER)
        self.assertIn('current.subtitle_choice != "REQUESTED"', OWNER)
        self.assertIn('choice !in setOf("ON", "REQUESTED", "OFF", "OTHER")', TV)

    def test_signed_selection_replay_rejected(self):
        raw = sign_synthetic_event(
            KEY, kind="VIEWER_VIETSUB_REQUESTED", tv_session_id=SESSION,
            torrent_hash=INFOHASH, file_index=4, sent_at_ms=NOW,
            nonce="b" * 32)
        verifier = SignedPlaybackVerifier(KEY)
        event = verifier.verify(raw, now_ms=NOW)
        self.assertEqual((event.kind, event.tv_session_id),
                         ("VIEWER_VIETSUB_REQUESTED", SESSION))
        with self.assertRaisesRegex(SignedPlaybackError, "REPLAY"):
            verifier.verify(raw, now_ms=NOW)

    def test_signed_requested_expires_and_off_refuses(self):
        cache = SignedRedmiStateCache(KEY)
        requested = sign_synthetic_state(
            KEY, boot_id="c" * 32, sequence=1,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
            torrent_hash=INFOHASH, file_index=4, active=True,
            subtitle_choice="REQUESTED", sent_at_ms=NOW, nonce="d" * 32)
        cache.receive(requested, now_ms=NOW, monotonic_s=100.0)
        self.assertEqual(cache.read_fresh(monotonic_s=102.0).subtitle_choice,
                         "REQUESTED")
        with self.assertRaisesRegex(RedmiStateRejected, "STALE"):
            cache.read_fresh(monotonic_s=109.0)
        off_cache = SignedRedmiStateCache(KEY)
        off = sign_synthetic_state(
            KEY, boot_id="e" * 32, sequence=1,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
            torrent_hash=INFOHASH, file_index=4, active=True,
            subtitle_choice="OFF", sent_at_ms=NOW, nonce="f" * 32)
        off_cache.receive(off, now_ms=NOW, monotonic_s=100.0)
        with self.assertRaisesRegex(RedmiStateRejected, "OFF_OR_INACTIVE"):
            off_cache.read_fresh(monotonic_s=101.0)


if __name__ == "__main__":
    unittest.main()
