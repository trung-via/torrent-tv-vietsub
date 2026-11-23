"""One-LAN-listener signed VieNeu manifest/WAV integration, no sockets or SDK.

Tests the original PairedHandler HTTP seam: auth, actual WAV bytes, active
TV recheck, replay isolation, wrong film, cursor, and caption-only fallback.
"""
from __future__ import annotations

import hashlib
import hmac
from io import BytesIO
import json
from pathlib import Path
import tempfile
import unittest

from assumed_source_handoff import AssumedEnglishSubtitle
from cue_pipeline import Cue, render
from paired_activation import (
    PairedActivation, AuthenticatedProgressiveSource,
    activation_request_mac, derive_session_secret, make_paired_handler,
)
from voiceover_audio_lane import VoiceoverAudioLane
from voiceover_audio_store import VoiceoverWavStore
from voiceover_revision import plan_voiceover
from voiceover_signed_offer import SignedVoiceoverOffer, PairedVoiceoverReceiver
from voiceover_vieneu import DEFAULT_VOICE_CACHE_ID

MEDIA = "media." + "a" * 64
OTHER_MEDIA = "media." + "b" * 64
MASTER = bytes(range(32))


class Revision:
    def __init__(self, media_key: str, source_sha256: str):
        self.version = 1
        self.media_key = media_key
        self.source_sha256 = source_sha256
        self.fmt = "srt"
        self.translated_count = 1
        self.total_count = 12
        self.last_end_ms = 1500
        self.payload = render((Cue(1, 0, 1500, "Thuyết minh phim"),), "srt")
        self.sha256 = hashlib.sha256(self.payload).hexdigest()


class PairedAudioLaneTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.store = VoiceoverWavStore(Path(temp.name).resolve())
        self.lane = VoiceoverAudioLane(store=self.store)
        self.enabled = True
        source = AssumedEnglishSubtitle.from_supplied(
            media_key=MEDIA, fmt="srt",
            source_bytes=b"1\n00:00:00,000 --> 00:00:01,500\nEnglish\n")
        self.source_sha = source.source_sha256
        def refresh():
            if not self.enabled:
                raise ValueError("TV_OFF_OR_OTHER")
        self.gateway = PairedActivation(
            device_secret=MASTER, supplied={},
            authenticated_progressive_factory=lambda media:
                AuthenticatedProgressiveSource(
                    media, self.source_sha, lambda feed: None,
                    refresh=refresh,
                ))
        self.active = self.gateway.activate({
            "schema": "TTV-P4-ACTIVATE-V1", "media_key": MEDIA,
            "nonce": "a" * 32,
            "auth": activation_request_mac(MASTER, MEDIA, "a" * 32),
        })
        self.sid = self.active["session_id"]
        self.secret = derive_session_secret(MASTER, self.sid, MEDIA, self.source_sha)
        self.revision = Revision(MEDIA, self.source_sha)
        self.cue = plan_voiceover(
            self.revision, voice_id=DEFAULT_VOICE_CACHE_ID).new_cues[0]
        self.receipt, _ = self.store.synthesize(
            self.cue, [[0.0] * 480, [0.1] * 960])
        self.lane.on_audio_ready(self.revision, self.cue, self.receipt)

    def _auth(self, scope: str, nonce: str):
        body = "TTV-P4-VOICE-READ-V1\n" + self.sid + "\n" + scope + "\n" + nonce
        tag = hmac.new(self.secret, body.encode("ascii"), hashlib.sha256).hexdigest()
        return {"X-P4-Nonce": nonce, "X-P4-Authorization": tag}

    def _get(self, path, headers=None, *, lane=None):
        cls = make_paired_handler(
            self.gateway, voiceover_lane=self.lane if lane is None else lane)
        handler = object.__new__(cls)
        responses, fields = [], []
        handler.send_response = lambda code: responses.append(code)
        handler.send_error = lambda code: responses.append(code)
        handler.send_header = lambda key, value: fields.append((key, value))
        handler.end_headers = lambda: None
        handler.path = path
        handler.headers = headers or {}
        handler.wfile = BytesIO()
        handler.do_GET()
        return responses[-1], dict(fields), handler.wfile.getvalue()

    def test_manifest_and_actual_wav_have_exact_paired_scope(self):
        url = "/p4/voice/" + self.sid
        status, headers, payload = self._get(
            url, self._auth("manifest:0", "1" * 32))
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        manifest = json.loads(payload)
        self.assertEqual(manifest["session_id"], self.sid)
        self.assertEqual(manifest["media_key"], MEDIA)
        self.assertEqual(len(manifest["offers"]), 1)
        offer = SignedVoiceoverOffer(**manifest["offers"][0])
        self.assertEqual(offer.tts_key, self.cue.tts_key)
        self.assertEqual(offer.voice_id, DEFAULT_VOICE_CACHE_ID)
        receiver = PairedVoiceoverReceiver(
            session_id=self.sid, media_key=MEDIA,
            source_sha256=self.source_sha, pairing_secret=self.secret)
        result = receiver.receive(
            offer, active_session=self.sid, active_media_key=MEDIA,
            presentation_mode="VOICE", on_native_audio=lambda _offer: True)
        self.assertEqual(result, "AUDIO_MANIFEST_ACCEPTED")

        wav_url = "/p4/audio/" + self.sid + "/" + self.cue.tts_key
        code, info, wav = self._get(
            wav_url, self._auth("audio:" + self.cue.tts_key, "2" * 32))
        self.assertEqual(code, 200)
        self.assertEqual(info["Content-Type"], "audio/wav")
        self.assertEqual(info["X-P4-Audio-Sha256"], self.receipt.wav_sha256)
        self.assertEqual(hashlib.sha256(wav).hexdigest(), self.receipt.wav_sha256)
        self.assertTrue(wav.startswith(b"RIFF"))

    def test_replay_and_cross_endpoint_auth_rejected(self):
        url = "/p4/voice/" + self.sid
        hdr = self._auth("manifest:0", "3" * 32)
        self.assertEqual(self._get(url, hdr)[0], 200)
        self.assertEqual(self._get(url, hdr)[0], 401)
        wav_url = "/p4/audio/" + self.sid + "/" + self.cue.tts_key
        self.assertEqual(self._get(wav_url, self._auth("manifest:0", "4" * 32))[0], 401)
        self.assertEqual(self._get(url, self._auth("manifest:0", "5" * 32)
                                   | {"X-P4-After-Cue": "1"})[0], 401)
        self.assertEqual(self._get(url, {"X-P4-After-Cue": "0001"})[0], 400)

    def test_tv_off_prevents_audio_but_keeps_verified_wav(self):
        self.enabled = False
        wav_url = "/p4/audio/" + self.sid + "/" + self.cue.tts_key
        self.assertEqual(self._get(
            wav_url, self._auth("audio:" + self.cue.tts_key, "6" * 32))[0], 403)
        self.assertEqual(self._get(
            "/p4/voice/" + self.sid, self._auth("manifest:0", "7" * 32))[0], 403)
        self.assertEqual(self.store.read(self.cue), self.receipt)

    def test_cursor_wrong_source_and_bad_path_do_not_expose_wav(self):
        url = "/p4/voice/" + self.sid
        self.assertEqual(self._get(
            url, self._auth("manifest:1", "8" * 32)
            | {"X-P4-After-Cue": "1"})[0], 204)
        self.assertEqual(self._get(
            "/p4/audio/" + self.sid + "/../" + self.cue.tts_key,
            self._auth("audio:" + self.cue.tts_key, "9" * 32))[0], 404)
        self.assertEqual(self._get(
            "/p4/audio/" + self.sid + "/" + "c"*64,
            self._auth("audio:" + "c"*64, "b" * 32))[0], 404)
        wrong = Revision(OTHER_MEDIA, self.source_sha)
        wrong_cue = plan_voiceover(
            wrong, voice_id=DEFAULT_VOICE_CACHE_ID).new_cues[0]
        wrong_receipt, _ = self.store.synthesize(wrong_cue, [[0.1] * 96])
        self.lane.on_audio_ready(wrong, wrong_cue, wrong_receipt)
        status, _fields, wav = self._get(
            "/p4/audio/" + self.sid + "/" + wrong_cue.tts_key,
            self._auth("audio:" + wrong_cue.tts_key, "c" * 32))
        self.assertEqual(status, 404)
        self.assertFalse(wav)

    def test_corrupted_wav_is_never_served(self):
        with (self.store.root / self.receipt.filename).open("ab") as stream:
            stream.write(b"corruption")
        url = "/p4/audio/" + self.sid + "/" + self.cue.tts_key
        status, _headers, body = self._get(
            url, self._auth("audio:" + self.cue.tts_key, "d" * 32))
        self.assertEqual(status, 403)
        self.assertEqual(body, b"")

    def test_subtitle_endpoint_unchanged_when_voice_lane_enabled(self):
        nonce = "e" * 32
        tag = hmac.new(
            self.secret,
            ("TTV-P4-LAN-READ-V1\n"+self.sid+"\n"+nonce).encode("ascii"),
            hashlib.sha256).hexdigest()
        status, _headers, _body = self._get(
            "/p4/revision/" + self.sid,
            {"X-P4-Nonce":nonce,"X-P4-Authorization":tag})
        self.assertEqual(status, 204)


if __name__ == "__main__":
    unittest.main()
