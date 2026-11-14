"""Issue #157: a real P4 session must wait for an exact verified source.

This is synthetic owner-private fixture ONLY. No Gemini, OpenSubtitles,
Redmi, Windows LAN service or media content. It exercises the existing
authenticated P4 source factory/verified manifest and signed P4 revision
without a second AI worker.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

_POC = Path(__file__).resolve().parent.parent
for _part in ("p2-aisub", "p3-vietsub-trigger"):
    _dir = str(_POC / _part)
    if _dir not in sys.path:
        sys.path.insert(0, _dir)

from matcher import Media
from p3_p4_media_key import p4_media_key
from paired_activation import PairedActivation, activation_request_mac
from verified_source_manifest import verified_source_from_manifest
from synthetic_mock_feed import (
    synthetic_source_srt, publish_synthetic_revisions, decode_latest_test_only,
)


KEY = bytes(range(32))
MEDIA = Media("owner-test-profile", "a" * 40, 2,
              "Synthetic.Movie.2017.1080p.BluRay-GRP.mkv")
P4KEY = p4_media_key(MEDIA, vlc_selected=True)


def request(media_key: str, nonce: str) -> dict[str, object]:
    return {
        "schema": "TTV-P4-ACTIVATE-V1", "media_key": media_key,
        "nonce": nonce, "auth": activation_request_mac(KEY, media_key, nonce),
    }


class P3P4SourceReadyTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="p3-p4-ready-")
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.manifest = self.root / "matched-en.json"
        self.calls = []

        def publish_existing_source(feed, source):
            self.calls.append((feed.media_key, source.source_sha256))
            publish_synthetic_revisions(
                source.media_key, feed, hold_seconds=0.0,
                wait=lambda _: None)

        self.p4 = PairedActivation(
            device_secret=KEY, supplied={}, on_activate=publish_existing_source,
            authenticated_source_factory=lambda media_key:
                verified_source_from_manifest(self.manifest, media_key),
        )

    def ready(self):
        bytes_ = synthetic_source_srt()
        src = self.root / "synthetic-authorized.en.srt"
        src.write_bytes(bytes_)
        self.manifest.write_text(json.dumps({
            "schema": "TTV-P2-OWNER-MATCHED-EN-V1",
            "sources": [{
                "media_key": P4KEY, "format": "srt",
                "source_path": str(src),
                "source_sha256": hashlib.sha256(bytes_).hexdigest(),
                "owner_confirmed_match": True,
            }],
        }, separators=(",", ":")), encoding="utf-8")

    def test_pre_source_hold_then_existing_p4_activation_and_revisions(self):
        # This is the circular-dependency break: viewer request already
        # started D1/D2; P4 returns source unavailable but does not trigger
        # any provider/translation on its own.
        with self.assertRaisesRegex(ValueError, "P2_MATCHED_OWNER_MANIFEST_REQUIRED"):
            self.p4.activate(request(P4KEY, "a" * 32))
        self.assertEqual(self.calls, [])
        self.ready()  # Synthetic stand-in for an accepted owner D1/D2 receipt.
        result = self.p4.activate(request(P4KEY, "b" * 32))
        self.assertEqual(result["media_key"], P4KEY)
        feed = self.p4.feed_for(result["session_id"])
        self.assertIsNotNone(feed)
        latest = decode_latest_test_only(feed)
        self.assertEqual(latest["media_key"], P4KEY)
        self.assertEqual(latest["translated_count"], 240)
        self.assertEqual(latest["total_count"], 240)
        self.assertEqual(len(self.calls), 1)

    def test_same_filename_another_torrent_does_not_borrow_ready_source(self):
        self.ready()
        wrong = p4_media_key(
            Media("owner-test-profile", "b"*40, 2, MEDIA.filename),
            vlc_selected=True)
        with self.assertRaisesRegex(ValueError, "P2_MATCHED_EN_SOURCE_NOT_FOUND"):
            self.p4.activate(request(wrong, "c"*32))
        self.assertEqual(self.calls, [])

    def test_tampered_cached_source_never_activates_p4(self):
        self.ready()
        (self.root / "synthetic-authorized.en.srt").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "P2_MATCHED_EN_SOURCE_HASH_MISMATCH"):
            self.p4.activate(request(P4KEY, "d"*32))
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
