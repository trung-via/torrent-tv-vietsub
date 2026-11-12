"""Offline gates for the opt-in synthetic P4 120->240 PC feed.

No LAN socket, Windows service, Gemini API or real media is used.
"""
from __future__ import annotations

import base64
import hashlib
import json
from pathlib import Path
import unittest
from unittest import mock

from paired_activation import activation_request_mac
from lan_revision_feed import SessionRevisionFeed
from run_assumed_source_gateway import build_controller
from synthetic_mock_feed import (
    publish_synthetic_revisions, synthetic_source_sha256, synthetic_source_srt,
)

MEDIA = "media." + "a" * 64
OTHER = "media." + "b" * 64
MASTER = b"synthetic-pairing-device-key-32x"
assert len(MASTER) == 32


class SyntheticP4FeedTests(unittest.TestCase):
    def new_feed(self):
        return SessionRevisionFeed(
            session_id="SYNTHETIC_SESSION_20261112",
            media_key=MEDIA,
            source_sha256=synthetic_source_sha256(),
            pairing_secret=b"synthetic-session-key-32-bytes!!",
        )

    def test_120_then_240_are_cumulative_with_cue_131(self):
        feed = self.new_feed()
        snapshots = []
        def hold(seconds):
            wire = json.loads(feed.latest())
            snapshots.append((seconds,wire))
        first, second = publish_synthetic_revisions(
            MEDIA,feed,hold_seconds=19,wait=hold)
        self.assertEqual(len(snapshots),1)
        self.assertEqual(snapshots[0][0],19)
        self.assertEqual((first.version,first.translated_count),(1,120))
        self.assertEqual((second.version,second.translated_count),(2,240))
        first_wire=snapshots[0][1]
        self.assertEqual(first_wire["version"],1)
        self.assertEqual(first_wire["translated_count"],120)
        self.assertNotIn("Phụ đề giả lập 131",
                         base64.b64decode(first_wire["payload_b64"]).decode("utf-8"))
        latest=json.loads(feed.latest())
        self.assertEqual(latest["version"],2)
        self.assertEqual(latest["translated_count"],240)
        payload=base64.b64decode(latest["payload_b64"]).decode("utf-8")
        self.assertIn("Phụ đề giả lập 131",payload)
        self.assertEqual(hashlib.sha256(payload.encode("utf-8")).hexdigest(),
                         latest["payload_sha256"])
        self.assertEqual(latest["source_sha256"],synthetic_source_sha256())
        self.assertTrue(synthetic_source_srt().startswith(b"1\\n"))

    def test_wrong_media_or_source_rejected_before_publication(self):
        feed=self.new_feed()
        with self.assertRaisesRegex(ValueError,"IDENTITY_MISMATCH"):
            publish_synthetic_revisions(OTHER,feed,wait=lambda x:None)
        with self.assertRaisesRegex(ValueError,"HOLD_INVALID"):
            publish_synthetic_revisions(MEDIA,feed,hold_seconds=200,
                                        wait=lambda x:None)
        self.assertIsNone(feed.latest())
        other_source=SessionRevisionFeed(
            session_id="SYNTHETIC_SESSION_20261112",
            media_key=MEDIA,source_sha256="b"*64,
            pairing_secret=b"synthetic-session-key-32-bytes!!",
        )
        with self.assertRaisesRegex(ValueError,"IDENTITY_MISMATCH"):
            publish_synthetic_revisions(MEDIA,other_source,wait=lambda x:None)

    def test_gateway_mock_activation_is_opt_in_and_no_api_or_lan_on_build(self):
        profile=Path(__file__).with_name("translator_profile.json")
        with mock.patch("run_assumed_source_gateway.threading.Thread") as thread:
            controller=build_controller(
                media_key=MEDIA,source_file=None,master_hex=MASTER.hex(),
                execute_api=False,profile_file=profile,api_key="",
                mock_revisions=True)
            self.assertIsNone(controller.feed_for("nothing"))
            nonce="c"*32
            result=controller.activate({
                "schema":"TTV-P4-ACTIVATE-V1",
                "media_key":MEDIA,
                "nonce":nonce,
                "auth":activation_request_mac(MASTER,MEDIA,nonce),
            })
            self.assertIsNotNone(controller.feed_for(result["session_id"]))
            thread.assert_called_once()
            thread.return_value.start.assert_called_once()
        with self.assertRaisesRegex(ValueError,"MOCK_CANNOT_CALL_API"):
            build_controller(media_key=MEDIA,source_file=None,
                master_hex=MASTER.hex(),execute_api=True,
                profile_file=profile,api_key="test",mock_revisions=True)
        with self.assertRaisesRegex(ValueError,"MOCK_REJECTS_REAL_SOURCE_FILE"):
            build_controller(media_key=MEDIA,source_file=profile,
                master_hex=MASTER.hex(),execute_api=False,
                profile_file=profile,api_key="",mock_revisions=True)


if __name__=="__main__":
    unittest.main()
