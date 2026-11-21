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
        self.registry.bind_existing_flow(self.flow)

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
        pending = self.activate("1" * 32)
        self.assertIsNone(pending.latest())  # P4 GET 204 before first batch.
        first = self.run_worker(max_new_windows=1)
        self.assertEqual((first.translated_count, first.complete), (120, False))
        self.assertFalse(list(self.state.rglob("vi-final.srt")))
        self.assertEqual(decode_latest_test_only(pending)["translated_count"], 120)
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
        for feed in (pending, first_feed, second_feed):
            wire = decode_latest_test_only(feed)
            self.assertEqual((wire["version"], wire["translated_count"]), (2, 240))
            self.assertEqual(wire["source_sha256"], self.handoff.source_sha256)
        self.assertEqual(len(list(self.state.rglob("vi-final.srt"))), 1)
        self.assertFalse(list(self.state.rglob("batch-*.inflight")))

    def test_signed_tv_native_key_overrides_different_owner_profile(self):
        """A P3 request can translate yet P4 fail when aliases differ."""
        tv_media = Media("tv-profile-alias", MEDIA.torrent_hash,
                         MEDIA.file_index, MEDIA.filename)
        tv_key = p4_media_key(tv_media, vlc_selected=True)
        self.assertNotEqual(tv_key, MEDIA_KEY)
        self.current = replace(self.current, native_p4_media_key=tv_key)
        native_gateway = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_vietsub_factory=self.registry.resolve,
            authenticated_progressive_factory=self.registry.resolve_progressive)
        def activate(key, nonce):
            return native_gateway.activate(dict(
                schema="TTV-P4-ACTIVATE-V1", media_key=key, nonce=nonce,
                auth=activation_request_mac(KEY, key, nonce)))
        with self.assertRaises(P3ReadyRejected):
            activate(MEDIA_KEY, "1" * 32)
        accepted = activate(tv_key, "2" * 32)
        feed = native_gateway.feed_for(accepted["session_id"])
        self.assertIsNone(feed.latest())
        self.run_worker(max_new_windows=1)
        first = decode_latest_test_only(feed)
        self.assertEqual((first["media_key"], first["translated_count"]),
                         (tv_key, 120))
        self.run_worker()
        self.assertEqual(decode_latest_test_only(feed)["translated_count"], 240)
        self.assertEqual(len(self.provider.calls), 2)

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

    def test_failed_callback_can_recover_latest_without_provider(self):
        with self.worker.bind(lambda _h, _r: (_ for _ in ()).throw(
                ValueError("TV_UNAVAILABLE"))):
            self.worker.run(self.handoff, max_new_windows=1)
        self.assertEqual(len(self.provider.calls), 1)
        # Simulates the old in-memory registry being lost at Owner restart.
        fresh = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current)
        fresh.bind_existing_flow(self.flow)
        gateway = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_vietsub_factory=fresh.resolve,
            authenticated_progressive_factory=fresh.resolve_progressive)
        nonce = "8" * 32
        reply = gateway.activate(dict(
            schema="TTV-P4-ACTIVATE-V1", media_key=MEDIA_KEY, nonce=nonce,
            auth=activation_request_mac(KEY, MEDIA_KEY, nonce)))
        self.assertEqual(decode_latest_test_only(
            gateway.feed_for(reply["session_id"]))["translated_count"], 120)
        self.assertEqual(len(self.provider.calls), 1)

    def test_inflight_next_batch_does_not_hide_last_verified_checkpoint(self):
        self.run_worker(max_new_windows=1)
        job, = [x for x in self.state.iterdir() if x.is_dir()]
        (job / "batch-0002.inflight").write_text("unresolved")
        fresh = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current)
        fresh.bind_existing_flow(self.flow)
        gateway = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_progressive_factory=fresh.resolve_progressive)
        nonce = "9" * 32
        reply = gateway.activate(dict(
            schema="TTV-P4-ACTIVATE-V1", media_key=MEDIA_KEY, nonce=nonce,
            auth=activation_request_mac(KEY, MEDIA_KEY, nonce)))
        self.assertEqual(decode_latest_test_only(
            gateway.feed_for(reply["session_id"]))["translated_count"], 120)
        self.assertEqual(len(self.provider.calls), 1)
        self.assertTrue((job / "batch-0002.inflight").is_file())

    def test_later_failed_callback_is_replayed_on_next_p4_activation(self):
        self.run_worker(max_new_windows=1)
        first_feed = self.activate("d" * 32)
        self.assertEqual(decode_latest_test_only(first_feed)["version"], 1)
        with self.worker.bind(lambda _h, _r: (_ for _ in ()).throw(
                RuntimeError("TV_LOST_WHILE_PROVIDER_CONTINUED"))):
            self.worker.run(self.handoff)
        self.assertEqual(len(self.provider.calls), 2)
        self.assertEqual(decode_latest_test_only(first_feed)["version"], 1)
        # The already paired TV keeps polling the SAME P4 session, not a
        # second activation; its read replays the verified batch from disk.
        self.assertTrue(self.p4.refresh_for(first_feed.session_id))
        self.assertEqual(decode_latest_test_only(first_feed)["version"], 2)
        reconnected = self.activate("e" * 32)
        self.assertEqual(decode_latest_test_only(reconnected)["version"], 2)
        self.assertEqual(len(self.provider.calls), 2)

    def test_p4_read_refuses_off_after_previous_successful_activation(self):
        self.run_worker(max_new_windows=1)
        feed = self.activate("f" * 32)
        self.assertTrue(self.p4.refresh_for(feed.session_id))
        self.current = replace(self.current, viewer_choice="OFF")
        self.assertFalse(self.p4.refresh_for(feed.session_id))
        self.assertEqual(len(self.provider.calls), 1)

    def test_restored_checkpoint_obeys_off_and_source_integrity(self):
        self.run_worker(max_new_windows=1)
        self.registry._rolling.clear()  # Loss of in-memory delivery pointers.
        self.current = replace(self.current, viewer_choice="OFF")
        with self.assertRaises(P3ReadyRejected):
            self.activate("a" * 32)
        self.current = replace(self.current, viewer_choice="REQUESTED")
        self.source.write_bytes(b"tampered")
        with self.assertRaises(P3ReadyRejected):
            self.activate("b" * 32)
        self.assertEqual(len(self.provider.calls), 1)

    def test_pending_feed_on_fresh_owner_does_not_start_translation(self):
        fresh = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current)
        fresh.bind_existing_flow(self.flow)
        gateway = PairedActivation(
            device_secret=KEY, supplied={},
            authenticated_progressive_factory=fresh.resolve_progressive)
        nonce = "c" * 32
        reply = gateway.activate(dict(
            schema="TTV-P4-ACTIVATE-V1", media_key=MEDIA_KEY, nonce=nonce,
            auth=activation_request_mac(KEY, MEDIA_KEY, nonce)))
        feed = gateway.feed_for(reply["session_id"])
        self.assertIsNone(feed.latest())
        self.assertTrue(gateway.refresh_for(reply["session_id"]))
        self.assertEqual(len(self.provider.calls), 0)
        # Only the existing worker starts through the original Owner event.
        with self.worker.bind(lambda handoff, revision:
                fresh.publish_worker_revision(
                    media=MEDIA, source_fingerprint=FP, tv_session_id=SESSION,
                    flow=self.flow, handoff=handoff, revision=revision)):
            self.worker.run(self.handoff, max_new_windows=1)
        self.assertEqual(decode_latest_test_only(feed)["translated_count"], 120)
        self.assertEqual(len(self.provider.calls), 1)

    def test_p4_diagnoses_media_key_mismatch_without_starting_provider(self):
        statuses = []
        registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current,
            on_status=statuses.append)
        registry.bind_existing_flow(self.flow)
        wrong = Media("another-tv-profile", MEDIA.torrent_hash,
                      MEDIA.file_index, MEDIA.filename)
        self.assertIsNone(registry.resolve_progressive(
            p4_media_key(wrong, vlc_selected=True)))
        self.assertEqual(statuses[-1], "MEDIA_KEY_MISMATCH")
        self.assertNotIn("ROLLING_FEED_MISSING", statuses)
        self.assertEqual(len(self.provider.calls), 0)

    def test_p4_diagnoses_no_index_and_pending_checkpoint_without_replay(self):
        statuses = []
        registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current,
            on_status=statuses.append)
        registry.bind_existing_flow(self.flow)
        index = self.cache / (".auto-source-" + FP + ".json")
        saved = index.read_bytes()
        index.unlink()
        self.assertIsNone(registry.resolve_progressive(MEDIA_KEY))
        self.assertEqual(statuses[-1], "EN_INDEX_NOT_READY")
        index.write_bytes(saved)
        self.assertIsNotNone(registry.resolve_progressive(MEDIA_KEY))
        self.assertIn("P2_CHECKPOINT_PENDING", statuses)
        self.assertEqual(len(self.provider.calls), 0)

    def test_p4_diagnostic_callback_cannot_block_existing_feed(self):
        def broken_sink(_code):
            raise RuntimeError("synthetic diagnostic sink failed")
        registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current,
            on_status=broken_sink)
        registry.bind_existing_flow(self.flow)
        self.assertIsNotNone(registry.resolve_progressive(MEDIA_KEY))
        self.assertEqual(len(self.provider.calls), 0)


if __name__ == "__main__":
    unittest.main()
