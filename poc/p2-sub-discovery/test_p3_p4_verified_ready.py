"""P3 owner completed VI/LEAN120 -> existing signed P4 final source, OFF-safe.

Pure synthetic fixture; never does OpenSubtitles, Gemini, LAN or TV I/O.
"""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from matcher import Media
from owner_selected_file_resolver import CurrentPlaying, _fingerprint
from p3_p4_media_key import p4_media_key
from p3_p4_ready_registry import P3OwnerReadyRegistry, P3ReadyRejected
from automatic_vietsub_flow import AutoResult
from automatic_lean120_worker import AutomaticLean120Worker, _job_fingerprint
from cached_en_direct_handoff import CachedEnReceipt, prepare_local_translation_source
from lean120_api import load_profile
from progressive_handoff import ProgressiveSubtitleSession
from synthetic_mock_feed import synthetic_source_srt, decode_latest_test_only
from paired_activation import PairedActivation, activation_request_mac

KEY = bytes(range(32))
MEDIA = Media("owner-test-profile", "a"*40, 2,
              "Synthetic.Film.2017.1080p.BluRay-GRP.mkv")
SESSION = "b"*32
FP = _fingerprint(MEDIA.server_profile_id, MEDIA.torrent_hash, MEDIA.file_index)
MEDIA_KEY = p4_media_key(MEDIA, vlc_selected=True)


def request(media_key=MEDIA_KEY, nonce="1"*32):
    return dict(schema="TTV-P4-ACTIVATE-V1", media_key=media_key, nonce=nonce,
                auth=activation_request_mac(KEY, media_key, nonce))


class FlowStub:
    def __init__(self, cache_root: Path, worker: AutomaticLean120Worker):
        self.cache_root = cache_root
        self.worker = worker


class ReadyRegistryTests(unittest.TestCase):
    def setUp(self):
        t = tempfile.TemporaryDirectory(prefix="p3-ready-private-")
        self.addCleanup(t.cleanup)
        self.root = Path(t.name).resolve()
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.state = self.root / "state"
        self.state.mkdir()
        # Reuse the pinned selected model/profile with an INERT fake transport.
        profile = load_profile((Path(__file__).resolve().parent.parent /
                                "p2-aisub" / "translator_profile.json"))
        self.worker = AutomaticLean120Worker(
            state_root=self.state, profile=profile, glossary={},
            api_key="synthetic-no-live-provider",
            transport=lambda *args, **kwargs: (_ for _ in ()).throw(
                AssertionError("LIVE_PROVIDER_FORBIDDEN")))
        self.flow = FlowStub(self.cache, self.worker)
        self.current = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=MEDIA.server_profile_id, tv_session_id=SESSION,
            torrent_hash=MEDIA.torrent_hash, file_index=MEDIA.file_index,
            video_name=MEDIA.filename, owner_auto_enabled=True,
            viewer_choice="REQUESTED", media_rights_approved=True,
            local_vi_state="ABSENT")
        self.registry = P3OwnerReadyRegistry(
            read_verified_current_playback=lambda: self.current)
        self.p4 = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_vietsub_factory=self.registry.resolve)

    def source(self, *, language: str):
        raw = synthetic_source_srt()
        digest = hashlib.sha256(raw).hexdigest()
        self.src = self.cache / (digest + ".srt")
        self.src.write_bytes(raw)
        (self.cache / (".auto-source-" + FP + ".json")).write_text(
            json.dumps(dict(schema="TTV-LOCAL-AUTO-SOURCE-V1",
                            file=self.src.name, language=language,
                            sha256=digest, cues=240)),
            encoding="utf-8")
        return raw

    def finish_en_from_existing_worker(self, raw: bytes) -> bytes:
        handoff = prepare_local_translation_source(
            CachedEnReceipt(self.src, hashlib.sha256(raw).hexdigest(), 240),
            private_root=self.cache)
        job = _job_fingerprint(handoff, self.worker.profile, self.worker.glossary)
        folder = self.state / job
        folder.mkdir()
        session = ProgressiveSubtitleSession(
            handoff.source_bytes, "srt", handoff.media_key)
        for i, window in enumerate(session.windows):
            session.commit(
                window, {idx:f"Phụ đề giả lập {idx:03d}" for idx in window.ids},
                expected_version=i, source_sha256=handoff.source_sha256,
                media_key=handoff.media_key)
        done = session.revision
        self.assertIsNotNone(done)
        self.assertTrue(done.complete)
        (folder / "vi-final.srt").write_bytes(done.payload)
        return done.payload

    def register(self, outcome: AutoResult):
        return self.registry.register(
            media=MEDIA, source_fingerprint=FP, tv_session_id=SESSION,
            flow=self.flow, result=outcome)

    def test_vi_fast_ready_exact_p4_activation_no_second_ai(self):
        self.source(language="vi")
        with self.assertRaisesRegex(P3ReadyRejected, "NO_CURRENT_ACCEPTED"):
            self.p4.activate(request())
        self.assertEqual(self.register(AutoResult("VI_READY", cue_count=240)),
                         MEDIA_KEY)
        ans = self.p4.activate(request(nonce="2"*32))
        feed = self.p4.feed_for(ans["session_id"])
        self.assertIsNotNone(feed)
        p = decode_latest_test_only(feed)
        self.assertEqual(p["translated_count"], 240)
        self.assertEqual(p["total_count"], 240)
        self.assertEqual(p["version"], 1)
        self.assertEqual(p["media_key"], MEDIA_KEY)
        self.assertEqual(p["source_sha256"], hashlib.sha256(
            synthetic_source_srt()).hexdigest())
        self.assertEqual(ans["source_sha256"], p["source_sha256"])

    def test_en_already_translated_uses_final_without_model_or_lookup(self):
        raw = self.source(language="en")
        out = self.finish_en_from_existing_worker(raw)
        self.register(AutoResult("VIETSUB_READY", cue_count=240,
                                 translated_cues=240))
        ans = self.p4.activate(request(nonce="3"*32))
        payload = decode_latest_test_only(self.p4.feed_for(ans["session_id"]))
        self.assertEqual(payload["source_sha256"],hashlib.sha256(raw).hexdigest())
        self.assertEqual(payload["payload_sha256"],hashlib.sha256(out).hexdigest())
        self.assertNotEqual(payload["source_sha256"],payload["payload_sha256"])
        self.assertEqual(payload["translated_count"],240)
        self.assertEqual(payload["total_count"],240)

    def test_en_without_existing_full_lean120_is_not_ready(self):
        self.source(language="en")
        with self.assertRaisesRegex(P3ReadyRejected,"COMPLETE_OUTPUT_MISSING"):
            self.register(AutoResult("VIETSUB_READY", cue_count=240,
                                     translated_cues=240))
        with self.assertRaises(P3ReadyRejected):
            self.p4.activate(request(nonce="4"*32))

    def test_status_vi_and_en_rejected_if_not_verified_completed(self):
        self.source(language="vi")
        self.assertIsNone(self.register(AutoResult("REVIEW_REQUIRED")))
        with self.assertRaisesRegex(P3ReadyRejected, "STATUS_LANGUAGE_MISMATCH"):
            self.register(AutoResult("VIETSUB_READY",cue_count=240,
                                     translated_cues=240))
        with self.assertRaisesRegex(P3ReadyRejected, "SOURCE_RECEIPT_MISMATCH"):
            self.register(AutoResult("VI_READY",cue_count=239))
        self.assertEqual(self.registry._ready, {})

    def test_off_other_stale_session_and_cross_torrent_denied(self):
        self.source(language="vi")
        self.register(AutoResult("VI_READY",cue_count=240))
        original = self.current
        for change in (dict(viewer_choice="OFF"),dict(viewer_choice="OTHER"),
                       dict(tv_session_id="c"*32),dict(torrent_hash="d"*40),
                       dict(active=False),dict(media_rights_approved=False),
                       dict(owner_auto_enabled=False)):
            self.current = replace(self.current, **change)
            with self.subTest(change=change), self.assertRaisesRegex(
                    P3ReadyRejected, "CURRENT_MEDIA_OR_CONSENT_CHANGED"):
                self.p4.activate(request(nonce=str(len(change))*32))
            self.current = original
        wrong = p4_media_key(
            Media(MEDIA.server_profile_id,"d"*40, MEDIA.file_index,MEDIA.filename),
            vlc_selected=True)
        with self.assertRaises(P3ReadyRejected):
            self.p4.activate(request(wrong,"a"*32))

    def _original(self):
        return CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=MEDIA.server_profile_id, tv_session_id=SESSION,
            torrent_hash=MEDIA.torrent_hash, file_index=MEDIA.file_index,
            video_name=MEDIA.filename, owner_auto_enabled=True,
            viewer_choice="REQUESTED", media_rights_approved=True,
            local_vi_state="ABSENT")

    def test_modified_cache_content_and_outside_paths_fail_closed(self):
        self.source(language="vi")
        self.register(AutoResult("VI_READY",cue_count=240))
        self.src.write_bytes(b"not SRT")
        with self.assertRaisesRegex(P3ReadyRejected,"FILE_HASH_CHANGED"):
            self.p4.activate(request(nonce="5"*32))

    def test_identical_video_name_different_file_index_not_accepted(self):
        self.source(language="vi")
        self.register(AutoResult("VI_READY",cue_count=240))
        other = p4_media_key(
            Media(MEDIA.server_profile_id,MEDIA.torrent_hash,3,MEDIA.filename),
            vlc_selected=True)
        with self.assertRaisesRegex(P3ReadyRejected,"NO_CURRENT_ACCEPTED"):
            self.p4.activate(request(other,nonce="6"*32))


if __name__=="__main__":
    unittest.main()
