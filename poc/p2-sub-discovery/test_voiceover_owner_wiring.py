"""R2 Owner callback integration test: P4 first, optional voice second.

No AGY, VieNeu SDK, Windows task, socket or physical TV. The real existing
R2 worker binding and real current-film identity checks are exercised; the
P2 provider work is replaced at the closest test seam.
"""
from __future__ import annotations

from dataclasses import replace
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch
import unittest

_POC = Path(__file__).resolve().parent.parent
for sibling in ("p2-aisub", "p3-vietsub-trigger"):
    path = str(_POC / sibling)
    if path not in sys.path:
        sys.path.insert(0, path)

from automatic_lean120_worker import AutomaticLean120Worker
from lean120_api import load_profile
from owner_r2_progressive_registry import R2OwnerProgressiveRegistry
from owner_r2_progressive_worker import R2ProgressiveWorker
from owner_r2_verified_processor import R2VerifiedV3Processor
from owner_selected_file_resolver import (
    CurrentPlaying, TorrServerSelectedFile, _fingerprint,
)
from verified_v3_processor import VerifiedV3Processor


class FakeVoice:
    def __init__(self, events):
        self.events = events
    def offer(self, revision):
        self.events.append("voice")


class R2FanoutWiringTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        profile = load_profile(_POC / "p2-aisub" / "translator_profile.json")
        worker = R2ProgressiveWorker(existing=AutomaticLean120Worker(
            state_root=self.root / "checkpoints", profile=profile,
            glossary={}, runner=lambda *args, **kwargs: {}))
        self.flow = type("Flow", (), {
            "selected_media": lambda *a, **k: None, "worker": worker
        })()
        self.current = CurrentPlaying(
            kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
            server_id="owner-test-profile", tv_session_id="c"*32,
            torrent_hash="a"*40, file_index=2,
            video_name="Synthetic.Film.2017.1080p.BluRay-GRP.mkv",
            owner_auto_enabled=True, viewer_choice="REQUESTED",
            media_rights_approved=True, local_vi_state="ABSENT")
        self.fp = _fingerprint(
            self.current.server_id, self.current.torrent_hash,
            self.current.file_index)
        self.record = TorrServerSelectedFile(
            2, self.current.video_name, 100_000)
        self.events = []
        self.registry = R2OwnerProgressiveRegistry(
            read_verified_current_playback=lambda: self.current)
        self.handoff = type("HandOff", (), {})()
        self.revision = type("Revision", (), {})()

    def _run(self, current):
        self.current = current
        proc = R2VerifiedV3Processor(
            progressive_registry=self.registry,
            voiceover_consumer=FakeVoice(self.events),
            flow=self.flow, private_media_root=self.root,
            read_verified_current_playback=lambda: self.current,
            read_verified_torrserver_file=lambda *args: self.record,
            locate_owner_pinned_files=lambda *args: None)

        def fake_super(processor, video_filename, **kwargs):
            cb = processor.flow.worker._scoped.callback
            cb(self.handoff, self.revision)
            return "PROCESSED"

        def fake_publish(**kwargs):
            self.events.append("p4")

        with patch.object(VerifiedV3Processor, "selected_media", fake_super), \
                patch.object(self.registry, "publish_worker_revision", fake_publish):
            return proc.selected_media(
                self.current.video_name,
                source_fingerprint=self.fp,
                tv_session_id="c"*32,
                authorized_selection=None)

    def test_real_validated_callback_runs_p4_then_voice(self):
        self.assertEqual(self._run(self.current), "PROCESSED")
        self.assertEqual(self.events, ["p4", "voice"])

    def test_stale_tv_session_blocks_p4_but_not_owned_voice(self):
        with self.assertRaisesRegex(ValueError, "TV_SESSION_CHANGED"):
            self._run(replace(self.current, tv_session_id="d"*32))
        self.assertEqual(self.events, ["voice"])

    def test_mismatched_torrserver_file_blocks_p4_but_not_owned_voice(self):
        self.record = replace(self.record, id=9)
        with self.assertRaisesRegex(ValueError, "TORRSERVER_FILE_CHANGED"):
            self._run(self.current)
        self.assertEqual(self.events, ["voice"])


if __name__ == "__main__":
    unittest.main()
