"""P3 HMAC playback event verifier: offline only, synthetic identities."""
from __future__ import annotations

import json
import unittest

from p3_signed_playback_signal import (
    SignedPlaybackVerifier, SignedPlaybackError,
    sign_synthetic_event, signing_message,
    MAX_WIRE_BYTES,
)


KEY = bytes(range(32))
WHEN = 1_800_000_000_000
SESSION = "a" * 32
NONCE = "c" * 32
HASH = "b" * 40


def packet(**updates):
    source = dict(
        kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
        torrent_hash=HASH, file_index=7,
        sent_at_ms=WHEN, nonce=NONCE)
    source.update(updates)
    return sign_synthetic_event(KEY, **source)


class SignedPlaybackSignalTests(unittest.TestCase):
    def setUp(self):
        self.verifier = SignedPlaybackVerifier(KEY)

    def test_pinned_cross_language_hmac_ascii_vector(self):
        # Kotlin Mac HmacSHA256 must produce this exact value; no movie text.
        self.assertEqual(
            signing_message(
                kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
                torrent_hash=HASH, file_index=7,
                sent_at_ms=WHEN, nonce=NONCE),
            ("TTV-P3-TV-SELECTION-V1\nPLAY_REQUEST_ACCEPTED\n" +
             SESSION + "\n" + HASH + "\n7\n1800000000000\n" +
             NONCE).encode("ascii"))
        self.assertEqual(
            json.loads(packet())["signature"],
            "c554546c5d9e78424f5fa3d17c31589652d4e9139fa93125a7a9ab76989e6964")

    def test_good_message_authenticates_only_signal_not_media(self):
        valid = self.verifier.verify(packet(), now_ms=WHEN)
        self.assertEqual(valid.file_index, 7)
        self.assertEqual(valid.torrent_hash, HASH)
        self.assertEqual(valid.tv_session_id, SESSION)
        # Don't carry untrusted filename, source server id, subtitles, keys.
        self.assertEqual(set(json.loads(packet())), {
            "schema", "kind", "tv_session_id", "torrent_hash",
            "file_index", "sent_at_ms", "nonce", "signature"})
        self.assertNotIn("video_filename", packet().decode())
        self.assertNotIn("server_id", packet().decode())
        self.assertFalse(hasattr(valid, "attested"))

    def test_duplicate_nonce_rejected_even_if_signed(self):
        self.verifier.verify(packet(), now_ms=WHEN)
        with self.assertRaisesRegex(SignedPlaybackError, "REPLAY"):
            self.verifier.verify(packet(), now_ms=WHEN)

    def test_new_nonce_with_new_selection_passes(self):
        self.verifier.verify(packet(), now_ms=WHEN)
        b = self.verifier.verify(
            packet(file_index=8, nonce="d" * 32,
                   kind="NEXT_QUEUE_ITEM_ACCEPTED", sent_at_ms=WHEN + 5),
            now_ms=WHEN + 5)
        self.assertEqual((b.file_index, b.kind),
                         (8, "NEXT_QUEUE_ITEM_ACCEPTED"))

    def test_authenticated_closed_signal_is_not_playback_start(self):
        closed = self.verifier.verify(
            packet(kind="PLAYBACK_CLOSED"), now_ms=WHEN)
        self.assertEqual(closed.kind, "PLAYBACK_CLOSED")
        self.assertNotEqual(closed.kind, "PLAY_REQUEST_ACCEPTED")

    def test_tamper_hash_index_session_nonce_time_kind_signature_refused(self):
        original = json.loads(packet())
        for field, value in (
            ("torrent_hash", "c" * 40),
            ("file_index", 8),
            ("tv_session_id", "b" * 32),
            ("nonce", "d" * 32),
            ("sent_at_ms", WHEN + 1),
            ("kind", "NEXT_QUEUE_ITEM_ACCEPTED"),
            ("signature", "0" * 64),
        ):
            with self.subTest(field=field):
                attempt = dict(original, **{field: value})
                with self.assertRaisesRegex(SignedPlaybackError, "AUTH_FAILED"):
                    self.verifier.verify(json.dumps(attempt).encode(),
                                         now_ms=WHEN)

    def test_rejects_expired_and_future_signed_messages(self):
        for sent in (WHEN - 15001, WHEN + 15001):
            with self.subTest(sent=sent):
                with self.assertRaisesRegex(SignedPlaybackError, "EXPIRED"):
                    self.verifier.verify(packet(sent_at_ms=sent), now_ms=WHEN)

    def test_accepts_exact_clock_window(self):
        self.assertEqual(
            self.verifier.verify(packet(sent_at_ms=WHEN + 15000), now_ms=WHEN).file_index, 7)

    def test_prevents_old_out_of_order_selection(self):
        self.verifier.verify(packet(sent_at_ms=WHEN + 3000), now_ms=WHEN + 3000)
        with self.assertRaisesRegex(SignedPlaybackError, "OUT_OF_ORDER"):
            self.verifier.verify(packet(
                sent_at_ms=WHEN, nonce="d" * 32), now_ms=WHEN + 3000)

    def test_strict_json_no_duplicate_extras_or_floating_index(self):
        old = json.loads(packet())
        variants = [
            packet() + b"X",
            json.dumps(dict(old, video_filename="private movie")).encode(),
            json.dumps(dict(old, file_index=7.0)).encode(),
            json.dumps(dict(old, file_index=True)).encode(),
            json.dumps(dict(old, file_index=-1)).encode(),
            json.dumps(dict(old, tv_session_id="A" * 32)).encode(),
            json.dumps(dict(old, torrent_hash="malformed")).encode(),
            json.dumps(dict(old, nonce="bad")).encode(),
            b'{"schema":"TTV-P3-TV-SELECTION-V1","schema":"TTV-P3-TV-SELECTION-V1"}',
        ]
        for attempted in variants:
            with self.subTest(attempted=attempted[:45]):
                with self.assertRaises(SignedPlaybackError):
                    SignedPlaybackVerifier(KEY).verify(attempted, now_ms=WHEN)

    def test_wire_size_cap_and_key_length(self):
        with self.assertRaisesRegex(SignedPlaybackError, "WIRE_SIZE"):
            self.verifier.verify(b"0" * (MAX_WIRE_BYTES + 1), now_ms=WHEN)
        with self.assertRaisesRegex(SignedPlaybackError, "PAIRING_SECRET"):
            SignedPlaybackVerifier(b"not-32")
        with self.assertRaisesRegex(SignedPlaybackError, "PAIRING_SECRET"):
            SignedPlaybackVerifier(KEY, max_skew_ms=90_000)

    def test_no_model_or_owner_win_service_access(self):
        import p3_signed_playback_signal as mod
        self.assertFalse(hasattr(mod, "run_owner_agent"))
        self.assertFalse(hasattr(mod, "open_subtitles"))
        self.assertFalse(hasattr(mod, "launch_server"))


if __name__ == "__main__":
    unittest.main()
