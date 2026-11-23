"""Signed narration manifest protocol tests. No real Android/LAN side effects."""
from __future__ import annotations

from dataclasses import replace
import hashlib
import unittest

from cue_pipeline import Cue, render
from voiceover_audio_store import AudioReceipt
from voiceover_revision import plan_voiceover
from voiceover_signed_offer import (
    PairedVoiceoverReceiver, sign_voiceover_offer,
)


class Revision:
    def __init__(self, media=None):
        self.version = 1
        self.media_key = media or "media." + "a" * 64
        self.source_sha256 = "b" * 64
        self.fmt = "srt"
        self.translated_count = 1
        self.total_count = 10
        self.last_end_ms = 1200
        self.payload = render((Cue(1, 0, 1200, "Xin chào Ngài"),), "srt")
        self.sha256 = hashlib.sha256(self.payload).hexdigest()


class VoiceOfferTests(unittest.TestCase):
    def setUp(self):
        self.rev = Revision()
        cue = plan_voiceover(self.rev, voice_id="minhduc_v3turbo").new_cues[0]
        self.receipt = AudioReceipt(
            cue.tts_key, "e"*64, 48_000, 4800, 100,
            cue.start_ms, cue.end_ms, cue.tts_key + ".wav")
        self.secret = bytes(range(32))
        self.session = "s"*32
        self.offer = sign_voiceover_offer(
            revision=self.rev, receipt=self.receipt,
            voice_id="minhduc_v3turbo", session_id=self.session,
            pairing_secret=self.secret)
        self.receiver = PairedVoiceoverReceiver(
            session_id=self.session, media_key=self.rev.media_key,
            source_sha256=self.rev.source_sha256, pairing_secret=self.secret)

    def receive(self, offer=None, **changes):
        values = {"active_session":self.session,
                  "active_media_key":self.rev.media_key,
                  "presentation_mode":"VOICE",
                  "on_native_audio":lambda o: True}
        values.update(changes)
        return self.receiver.receive(offer or self.offer, **values)

    def test_signed_offer_only_for_committed_matching_tts_key(self):
        self.assertEqual(self.offer.cue_number, 1)
        self.assertEqual(self.offer.start_ms, 0)
        self.assertEqual(self.offer.end_ms, 1200)
        self.assertEqual(self.receive(), "AUDIO_MANIFEST_ACCEPTED")
        self.assertEqual(self.receive(), "DUPLICATE_NOOP")

    def test_wrong_film_source_or_voice_never_reuses_wav(self):
        for bad in (
            replace(self.rev, media_key="media."+"c"*64) if False else Revision("media."+"c"*64),
        ):
            with self.assertRaisesRegex(ValueError, "CUE_OR_SOURCE_MISMATCH"):
                sign_voiceover_offer(
                    revision=bad, receipt=self.receipt,
                    voice_id="minhduc_v3turbo", session_id=self.session,
                    pairing_secret=self.secret)
        with self.assertRaisesRegex(ValueError, "CUE_OR_SOURCE_MISMATCH"):
            sign_voiceover_offer(
                revision=self.rev, receipt=self.receipt,
                voice_id="another_voice", session_id=self.session,
                pairing_secret=self.secret)

    def test_off_stale_session_wrong_media_and_tamper(self):
        self.assertEqual(self.receive(presentation_mode="OFF"),
                         "DEFERRED_USER_AUDIO_CHOICE")
        with self.assertRaisesRegex(ValueError, "STALE_SESSION"):
            self.receive(active_session="t"*32)
        with self.assertRaisesRegex(ValueError, "STALE_SESSION"):
            self.receive(active_media_key="media."+"d"*64)
        with self.assertRaisesRegex(ValueError, "SIGNATURE_INVALID"):
            self.receive(replace(self.offer, end_ms=9999))
        self.assertEqual(self.receive(), "AUDIO_MANIFEST_ACCEPTED")

    def test_applier_failure_no_ack_and_later_retry(self):
        self.assertEqual(self.receive(on_native_audio=lambda x: False),
                         "AUDIO_APPLY_FAILED_NO_ACK")
        self.assertEqual(self.receive(), "AUDIO_MANIFEST_ACCEPTED")


if __name__ == "__main__":
    unittest.main()
