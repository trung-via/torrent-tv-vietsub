"""One P3→owner V3→P4 signed revision loopback socket acceptance.

This uses ONE real OS loopback HTTP socket and the genuine Python production
handler / owner event queue / ready registry / P4 HMAC feed. TV and TorrServer
inputs and VI source are entirely synthetic. NOT LAN/TLS/Redmi/provider PASS.
This test never binds a public/private-LAN adapter, installs or starts a worker.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
from http.client import HTTPConnection
from http.server import HTTPServer
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

_POC = Path(__file__).resolve().parent.parent
for _part in ("p2-aisub", "p3-vietsub-trigger"):
    _s = str(_POC / _part)
    if _s not in sys.path:
        sys.path.insert(0, _s)

from automatic_vietsub_flow import AutoResult
from owner_session_bridge import poll_private_events
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from owner_torrserver_ffp_tracks import TorrServerFfpTrackReader
from owner_p3_p4_private_policy import PrivateP3P4Policy
from p3_owner_state_wiring import compose_owner_redmi_status
from p3_signed_playback_signal import sign_synthetic_event
from p3_redmi_current_state import sign_synthetic_state
from paired_activation import (
    activation_request_mac, derive_session_secret,
)
from p3_p4_media_key import p4_media_key
from matcher import Media
from synthetic_mock_feed import synthetic_source_srt

KEY = bytes(range(32))
TORRENT = "a" * 40
SESSION = "b" * 32
VIDEO = "Synthetic.Authorized.2017.mkv"
PROFILE = "test-owner-profile"
MEDIA = Media(PROFILE, TORRENT, 2, VIDEO)
MEDIA_KEY = p4_media_key(MEDIA, vlc_selected=True)


class CompletedViSource:
    def __init__(self, cache: Path):
        self.cache_root = cache
        self.worker = object()
        self.calls = 0

    def selected_media(self, name, *, source_fingerprint, verified_media,
                       local_source=None):
        if name != VIDEO or verified_media != MEDIA or local_source is not None:
            raise AssertionError("P3_PIPELINE_IDENTITY_CHANGED")
        self.calls += 1
        source = synthetic_source_srt()
        sha = hashlib.sha256(source).hexdigest()
        (self.cache_root / (sha + ".srt")).write_bytes(source)
        (self.cache_root / (".auto-source-" + source_fingerprint + ".json")).write_text(
            json.dumps({
                "schema": "TTV-LOCAL-AUTO-SOURCE-V1",
                "file": sha + ".srt",
                "language": "vi",
                "sha256": sha,
                "cues": 240,
            }), encoding="utf-8")
        return AutoResult("VI_READY", cue_count=240)


class P3ToOwnerToP4SocketTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="ttv-main-pipeline-synthetic-")
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name).resolve()
        owner = root / "owner"
        media_root = root / "media"
        media_root.mkdir()
        cache = root / "cache"
        cache.mkdir()
        self.owner = owner
        self.flow = CompletedViSource(cache)
        self.reads = 0
        response = json.dumps({"hash": TORRENT, "file_stats": [{
            "id": 2, "path": "Synthetic/" + VIDEO, "length": 100000,
        }]}).encode("utf-8")

        def local_torrserver(url, body, timeout):
            self.reads += 1
            self.assertTrue(url.startswith("http://127.0.0.1:"))
            self.assertEqual(json.loads(body), {"action": "get", "hash": TORRENT})
            return response

        torrserver = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE, 8090), transport=local_torrserver)
        self.wiring = compose_owner_redmi_status(
            p4_gateway=None, paired_device_secret=KEY,
            torrserver_reader=torrserver, owner_root=owner,
            private_media_root=media_root,
            owner_auto_allowed=lambda: True,  # TEST FIXTURE ONLY
            media_rights_allowed=lambda *_: True,  # TEST FIXTURE ONLY
            verified_local_vi_state=lambda *_: "ABSENT",  # TEST FIXTURE ONLY
            locate_owner_pinned_files=lambda *_: None,
            enable_verified_vietsub_ready=True,
        )
        self.server = HTTPServer(("127.0.0.1", 0), self.wiring.handler)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()
        self.addCleanup(self.thread.join, 2)

    def http(self, method, endpoint, payload=None, headers=None):
        connection = HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        try:
            connection.request(method, endpoint, body=payload,
                               headers=headers or {})
            response = connection.getresponse()
            return response.status, response.read()
        finally:
            connection.close()

    def post(self, route, raw):
        return self.http("POST", route, raw,
                         {"Content-Type": "application/json"})

    def state(self, choice, seq, *, media_key=None):
        return sign_synthetic_state(
            KEY, boot_id="c" * 32, sequence=seq,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
            torrent_hash=TORRENT, file_index=2,
            active=True, subtitle_choice=choice,
            sent_at_ms=int(time.time() * 1000), nonce=f"{seq:032x}",
            media_key=media_key)

    def event(self, kind, nonce):
        return sign_synthetic_event(
            KEY, kind=kind, tv_session_id=SESSION,
            torrent_hash=TORRENT, file_index=2,
            sent_at_ms=int(time.time() * 1000), nonce=nonce)

    def activate(self, nonce, *, media_key=MEDIA_KEY):
        message = {
            "schema": "TTV-P4-ACTIVATE-V1", "media_key": media_key,
            "nonce": nonce,
            "auth": activation_request_mac(KEY, media_key, nonce),
        }
        return self.post("/p4/activate",
                         json.dumps(message, separators=(",", ":")).encode("ascii"))

    def test_real_loopback_full_vi_pipeline_and_off_revocation(self):
        # 1. Real network request to same composed P3/P4 Python handler.
        self.assertEqual(self.post("/p3/state", self.state("REQUESTED", 1))[0], 204)
        self.assertEqual(self.activate("1" * 32)[0], 403)
        self.assertEqual(self.flow.calls, 0)
        self.assertEqual(
            self.post("/p3/selection", self.event("PLAY_REQUEST_ACCEPTED", "e" * 32))[0],
            204)
        self.assertEqual(self.flow.calls, 0)
        self.assertFalse((self.owner / "inbox").exists())

        # 2. Explicit user tap -> PRIVATE V3 event -> SAME existing owner flow.
        self.assertEqual(self.post(
            "/p3/selection", self.event("VIEWER_VIETSUB_REQUESTED", "f" * 32))[0],
            204)
        emitted = []
        processed = poll_private_events(
            owner_root=self.owner,
            processor=self.wiring.trusted_v3_factory(self.flow),
            emit=emitted.append)
        self.assertEqual(processed, 1)
        self.assertEqual(emitted, ["OWNER_BRIDGE_EVENT_COMPLETE"])
        self.assertEqual(self.flow.calls, 1)

        # 3. Real HTTP P4 activation and authenticated one-use revision read.
        code, body = self.activate("2" * 32)
        self.assertEqual(code, 200)
        accepted = json.loads(body)
        sid = accepted["session_id"]
        secret = derive_session_secret(KEY, sid, MEDIA_KEY, accepted["source_sha256"])
        read_nonce = "3" * 32
        auth = hmac.new(
            secret,
            ("TTV-P4-LAN-READ-V1\n" + sid + "\n" + read_nonce).encode("ascii"),
            hashlib.sha256).hexdigest()
        route = "/p4/revision/" + sid
        code, body = self.http("GET", route, headers={
            "X-P4-Nonce": read_nonce, "X-P4-Authorization": auth,
        })
        self.assertEqual(code, 200)
        offer = json.loads(body)
        self.assertEqual(offer["media_key"], MEDIA_KEY)
        self.assertEqual(offer["translated_count"], 240)
        self.assertEqual(offer["total_count"], 240)
        self.assertEqual(offer["version"], 1)
        vi = base64.b64decode(offer["payload_b64"], validate=True)
        self.assertEqual(hashlib.sha256(vi).hexdigest(), offer["payload_sha256"])
        self.assertEqual(
            self.http("GET", route, headers={
                "X-P4-Nonce": read_nonce, "X-P4-Authorization": auth,
            })[0], 401)

        # 4. Viewer changes to OFF: source exists but fresh activation blocked.
        self.assertEqual(self.post("/p3/state", self.state("OFF", 2))[0], 204)
        self.assertEqual(self.activate("4" * 32)[0], 403)
        self.assertEqual(self.flow.calls, 1)
        self.assertGreaterEqual(self.reads, 6)

    def test_v2_native_tv_key_binds_completed_vi_across_profile_alias(self):
        # The PC's configured localhost TorrServer alias differs from OMP's
        # native serverProfileId. The signed TV key, not the PC alias, must
        # own both P4 activation and the delivered revision.
        native_key = p4_media_key(Media("tv-native-profile", TORRENT, 2, VIDEO),
                                  vlc_selected=True)
        self.assertNotEqual(native_key, MEDIA_KEY)
        self.assertEqual(self.post(
            "/p3/state", self.state("REQUESTED", 1,
                                      media_key=native_key))[0], 204)
        self.assertEqual(self.post(
            "/p3/selection", self.event("VIEWER_VIETSUB_REQUESTED",
                                         "f" * 32))[0], 204)
        self.assertEqual(poll_private_events(
            owner_root=self.owner,
            processor=self.wiring.trusted_v3_factory(self.flow),
            emit=lambda *_: None), 1)
        self.assertEqual(self.flow.calls, 1)
        code, body = self.activate("9" * 32, media_key=native_key)
        self.assertEqual(code, 200)
        self.assertEqual(json.loads(body)["media_key"], native_key)
        self.assertEqual(self.activate("8" * 32)[0], 403)


class StreamOnlyP3ToOwnerToP4SocketTests(P3ToOwnerToP4SocketTests):
    """Same signed P3→V3→P4 HTTP lifecycle, but real private stream-only policy.

    No synthetic permissive owner policy callbacks; only a per-film approved
    allowlist and independently parsed OMP /ffp inventory can proceed.
    Transport responses and subtitle bytes remain synthetic test fixtures.
    """

    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix="ttv-stream-pipeline-synthetic-")
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name).resolve()
        owner = root / "OwnerBridge"
        owner.mkdir()
        media_root = root / "media"
        media_root.mkdir()
        cache = root / "cache"
        cache.mkdir()
        self.owner = owner
        self.flow = CompletedViSource(cache)
        self.reads = 0
        self.ffp_reads = 0
        ts_path = "Synthetic/" + VIDEO
        meta = json.dumps({
            "hash": TORRENT,
            "file_stats": [{"id": 2, "path": ts_path, "length": 100000}],
        }).encode()

        def local_metadata(url, body, timeout):
            self.reads += 1
            self.assertEqual(url, "http://127.0.0.1:8090/torrents")
            self.assertEqual(json.loads(body), {"action": "get", "hash": TORRENT})
            return meta

        def trusted_ffp(url, timeout):
            self.ffp_reads += 1
            self.assertEqual(
                url, "http://127.0.0.1:8090/ffp/" + TORRENT + "/2")
            self.assertEqual(timeout, 3.0)
            return json.dumps({"streams": [
                {"codec_type": "video", "codec_name": "h264"},
                {"codec_type": "subtitle", "tags": {"language": "eng"}},
            ]}).encode()

        ts = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE, 8090), transport=local_metadata)
        policy_path = owner / "p3-p4-policy.json"
        policy_path.write_text(json.dumps({
            "schema": "TTV-P3-P4-OWNER-POLICY-V1",
            "enabled": True,
            "profile_id": PROFILE,
            "torrserver_port": 8090,
            "private_media_root": str(media_root),
            "media": [{
                "torrent_hash": TORRENT,
                "file_index": 2, "torrserver_path": ts_path,
                "video_path": None, "stream_only": True,
                "rights_approved": True,
            }],
        }), encoding="utf-8")
        policy = PrivateP3P4Policy(
            manifest=policy_path, owner_root=owner,
            private_media_root=media_root, torrserver=ts,
            stream_probe=TorrServerFfpTrackReader(ts, transport=trusted_ffp))
        self.assertTrue(policy.owner_auto_allowed())
        self.assertTrue(policy.media_rights_allowed(PROFILE, TORRENT, 2))
        self.assertIsNone(
            policy.locate_owner_pinned_files(PROFILE,TORRENT,2,ts_path))
        self.wiring = compose_owner_redmi_status(
            p4_gateway=None, paired_device_secret=KEY,
            torrserver_reader=ts, owner_root=owner,
            private_media_root=media_root,
            owner_auto_allowed=policy.owner_auto_allowed,
            media_rights_allowed=policy.media_rights_allowed,
            verified_local_vi_state=policy.verified_local_vi_state,
            locate_owner_pinned_files=policy.locate_owner_pinned_files,
            enable_verified_vietsub_ready=True)
        self.server = HTTPServer(("127.0.0.1", 0), self.wiring.handler)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.thread = threading.Thread(
            target=self.server.serve_forever,
            kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()
        self.addCleanup(self.thread.join, 2)

    def test_real_loopback_full_vi_pipeline_and_off_revocation(self):
        super().test_real_loopback_full_vi_pipeline_and_off_revocation()
        self.assertGreater(self.ffp_reads, 0)


if __name__ == "__main__":
    unittest.main()
