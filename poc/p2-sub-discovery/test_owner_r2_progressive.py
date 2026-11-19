"""Synthetic P3 verified EN -> existing P2 checkpoints -> P4 120/240.

No network socket, AGY/Google account, OpenSubtitles, TV or Windows task.
"""
from __future__ import annotations

from dataclasses import replace
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

_POC = Path(__file__).resolve().parent.parent
for _sibling in ("p2-aisub", "p3-vietsub-trigger"):
    _path = str(_POC / _sibling)
    if _path not in sys.path:
        sys.path.insert(0, _path)

from automatic_lean120_worker import AutomaticLean120Worker
from cached_en_direct_handoff import CachedEnReceipt, prepare_local_translation_source
from lean120_api import load_profile
from matcher import Media
from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
from owner_r2_progressive_worker import R2ProgressiveWorker
from owner_selected_file_resolver import CurrentPlaying, _fingerprint
from p3_p4_media_key import p4_media_key
from p3_p4_ready_registry import P3ReadyRejected
from paired_activation import PairedActivation, activation_request_mac
from synthetic_mock_feed import synthetic_source_srt, decode_latest_test_only
from test_automatic_lean120_worker import FakeAntigravity


KEY = bytes(range(32))
MEDIA = Media("owner-test-profile", "a" * 40, 2,
              "Synthetic.Film.2017.1080p.BluRay-GRP.mkv")
SESSION = "b" * 32
FP = _fingerprint(MEDIA.server_profile_id, MEDIA.torrent_hash, MEDIA.file_index)
MEDIA_KEY = p4_media_key(MEDIA, vlc_selected=True)


class R2RollingTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.cache = self.root / "cache"
        self.cache.mkdir()
        self.state = self.root / "state"
        self.state.mkdir()
        raw = synthetic_source_srt()
        digest = hashlib.sha256(raw).hexdigest()
        self.source = self.cache / (digest + ".srt")
        self.source.write_bytes(raw)
        (self.cache / (".auto-source-" + FP + ".json")).write_text(
            json.dumps(dict(schema="TTV-LOCAL-AUTO-SOURCE-V1",
                            file=self.source.name, language="en",
                            sha256=digest, cues=240)))
        self.handoff = prepare_local_translation_source(
            CachedEnReceipt(self.source, digest, 240), private_root=self.cache)
        self.current = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id=MEDIA.server_profile_id, tv_session_id=SESSION,
            torrent_hash=MEDIA.torrent_hash, file_index=MEDIA.file_index,
            video_name=MEDIA.filename, owner_auto_enabled=True,
            viewer_choice="REQUESTED", media_rights_approved=True,
            local_vi_state="ABSENT")
        self.registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current)
        self.p4 = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_vietsub_factory=self.registry.resolve,
            authenticated_progressive_factory=self.registry.resolve_progressive)
        profile = load_profile(
            Path(__file__).resolve().parent.parent / "p2-aisub" /
            "translator_profile.json")
        self.provider = FakeAntigravity()
        self.worker = R2ProgressiveWorker(existing=AutomaticLean120Worker(
            state_root=self.state, profile=profile, glossary={},
            runner=self.provider))
        self.flow = type("Flow", (), {"cache_root": self.cache,
                                       "worker": self.worker})()

    def activate(self, nonce: str):
        request = dict(schema="TTV-P4-ACTIVATE-V1", media_key=MEDIA_KEY,
                       nonce=nonce, auth=activation_request_mac(KEY, MEDIA_KEY, nonce))
        reply = self.p4.activate(request)
        return self.p4.feed_for(reply["session_id"])

    def run_worker(self, *, max_new_windows=None):
        def delivered(handoff, revision):
            self.registry.publish_worker_revision(
                media=MEDIA, source_fingerprint=FP, tv_session_id=SESSION,
                flow=self.flow, handoff=handoff, revision=revision)
        with self.worker.bind(delivered):
            return self.worker.run(
                self.handoff, max_new_windows=max_new_windows)

    def test_first_120_available_before_full_240_with_one_p2_job(self):
        with self.assertRaises(P3ReadyRejected):
            self.activate("1" * 32)
        first = self.run_worker(max_new_windows=1)
        self.assertEqual((first.translated_count, first.complete), (120, False))
        self.assertFalse(list(self.state.rglob("vi-final.srt")))
        first_feed = self.activate("2" * 32)
        wire = decode_latest_test_only(first_feed)
        self.assertEqual((wire["version"], wire["translated_count"],
                          wire["total_count"]), (1, 120, 240))
        self.assertEqual(wire["media_key"], MEDIA_KEY)
        self.assertNotEqual(self.handoff.media_key, MEDIA_KEY)
        second_feed = self.activate("3" * 32)
        finished = self.run_worker()
        self.assertTrue(finished.complete)
        self.assertEqual(len(self.provider.calls), 2)
        for feed in (first_feed, second_feed):
            wire = decode_latest_test_only(feed)
            self.assertEqual((wire["version"], wire["translated_count"]), (2, 240))
            self.assertEqual(wire["source_sha256"], self.handoff.source_sha256)
        self.assertEqual(len(list(self.state.rglob("vi-final.srt"))), 1)
        self.assertFalse(list(self.state.rglob("batch-*.inflight")))

    def test_off_or_changed_session_cannot_receive_next_revision(self):
        self.run_worker(max_new_windows=1)
        feed = self.activate("4" * 32)
        self.current = replace(self.current, viewer_choice="OFF")
        with self.assertRaises(P3ReadyRejected):
            self.activate("5" * 32)
        self.run_worker()
        self.assertEqual(decode_latest_test_only(feed)["translated_count"], 120)
        self.assertEqual(len(self.provider.calls), 2)
        self.current = replace(self.current, viewer_choice="REQUESTED",
                               tv_session_id="c" * 32)
        with self.assertRaises(P3ReadyRejected):
            self.activate("6" * 32)

    def test_changed_private_source_is_not_served(self):
        self.run_worker(max_new_windows=1)
        self.source.write_bytes(b"tampered")
        with self.assertRaises(P3ReadyRejected):
            self.activate("7" * 32)

    def test_delivery_callback_failure_preserves_checkpoint_without_retry(self):
        with self.worker.bind(lambda _h, _r: (_ for _ in ()).throw(
                ValueError("TV_OFF"))):
            first = self.worker.run(self.handoff, max_new_windows=1)
        self.assertEqual(first.translated_count, 120)
        self.assertEqual(len(self.provider.calls), 1)
        self.assertTrue(list(self.state.rglob("batch-0001.json")))
        self.assertFalse(list(self.state.rglob("batch-*.inflight")))
        self.run_worker()
        self.assertEqual(len(self.provider.calls), 2)


if __name__ == "__main__":
    unittest.main()
