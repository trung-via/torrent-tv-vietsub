"""Full in-process P3 signed Redmi → existing V3 owner → signed P4 VI.
No LIVE provider, Windows socket/Task Scheduler, ADB, or real TV traffic.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

_POC=Path(__file__).resolve().parent.parent
for _part in ("p2-aisub","p3-vietsub-trigger"):
    _v=str(_POC / _part)
    if _v not in sys.path:sys.path.insert(0,_v)

from matcher import Media
from p3_p4_media_key import p4_media_key
from automatic_vietsub_flow import AutoResult
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from owner_session_bridge import poll_private_events
from p3_owner_state_wiring import compose_owner_redmi_status
from p3_signed_playback_signal import sign_synthetic_event
from p3_redmi_current_state import sign_synthetic_state
from paired_activation import activation_request_mac
from synthetic_mock_feed import synthetic_source_srt, decode_latest_test_only

KEY=bytes(range(32))
WHEN=1_800_000_000_000
TORRENT="a"*40
PROFILE="owner-test-profile"
VIDEO="Synthetic.Film.2017.1080p.BluRay-GRP.mkv"
SESSION="b"*32
BOOT="c"*32
MEDIA=Media(PROFILE,TORRENT,2,VIDEO)
MEDIA_KEY=p4_media_key(MEDIA,vlc_selected=True)


def state(choice="REQUESTED",seq=1,nonce="d"*32):
    return sign_synthetic_state(
        KEY,boot_id=BOOT,sequence=seq,kind="PLAY_REQUEST_ACCEPTED",
        tv_session_id=SESSION,torrent_hash=TORRENT,file_index=2,
        active=True,subtitle_choice=choice,sent_at_ms=WHEN,nonce=nonce)


def event(kind="VIEWER_VIETSUB_REQUESTED",nonce="e"*32):
    return sign_synthetic_event(
        KEY,kind=kind,tv_session_id=SESSION,torrent_hash=TORRENT,
        file_index=2,sent_at_ms=WHEN,nonce=nonce)


def activation(nonce="1"*32):
    return dict(schema="TTV-P4-ACTIVATE-V1",media_key=MEDIA_KEY,nonce=nonce,
                auth=activation_request_mac(KEY,MEDIA_KEY,nonce))


class ExistingV3ViFlowFixture:
    def __init__(self,cache:Path):
        self.cache_root=cache
        self.worker=object() # VI_FAST requires NO P2 worker invocation
        self.calls=0

    def selected_media(self,video_name,*,source_fingerprint,verified_media,
                       local_source=None):
        self.calls+=1
        if video_name!=VIDEO or verified_media!=MEDIA or local_source is not None:
            raise AssertionError("V3 EXACT VERIFIED MEDIA EXPECTED")
        raw=synthetic_source_srt()
        digest=hashlib.sha256(raw).hexdigest()
        (self.cache_root/(digest+".srt")).write_bytes(raw)
        (self.cache_root/(".auto-source-"+source_fingerprint+".json")).write_text(
            json.dumps(dict(schema="TTV-LOCAL-AUTO-SOURCE-V1",
                            file=digest+".srt",language="vi",sha256=digest,cues=240)),
            encoding="utf-8")
        return AutoResult("VI_READY",cue_count=240)


class SignedViewerToReadyP4Tests(unittest.TestCase):
    def setUp(self):
        t=tempfile.TemporaryDirectory(prefix="p3-owner-e2e-synthetic-")
        self.addCleanup(t.cleanup)
        self.root=Path(t.name).resolve()
        self.owner=self.root/"owner"
        self.media=self.root/"media"
        self.media.mkdir()
        self.cache_root=self.root/"cache"
        self.cache_root.mkdir()
        self.flow=ExistingV3ViFlowFixture(self.cache_root)

        response=json.dumps({"hash":TORRENT,"file_stats":[
            {"id":2,"path":"Authorized/"+VIDEO,"length":100000}
        ]}).encode()
        self.reads=0
        def local_only(url,payload,timeout):
            self.reads+=1
            if not url.startswith("http://127.0.0.1:"):
                raise AssertionError("OWNER LOOPBACK ONLY")
            if json.loads(payload)!={"action":"get","hash":TORRENT}:
                raise AssertionError("CURRENT TORRENT READ")
            return response
        reader=OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE,8090),transport=local_only)
        self.wire=compose_owner_redmi_status(
            p4_gateway=None,paired_device_secret=KEY,
            torrserver_reader=reader,owner_root=self.owner,
            private_media_root=self.media,
            owner_auto_allowed=lambda:True,
            media_rights_allowed=lambda *_:True,
            verified_local_vi_state=lambda *_:"ABSENT",
            locate_owner_pinned_files=lambda *_:None,
            enable_verified_vietsub_ready=True,
        )

    def test_open_only_waits_tap_then_vi_cache_to_same_p4_signed_feed(self):
        self.assertIsNotNone(self.wire.ready_registry)
        self.wire.cache.receive(state(),now_ms=WHEN)
        # Opening video never creates an AI task or makes P4 source ready.
        self.assertEqual(self.wire.signal.on_wire(
            event(kind="PLAY_REQUEST_ACCEPTED",nonce="f"*32),now_ms=WHEN).status,
            "SKIP")
        self.assertFalse((self.owner/"inbox").exists())
        with self.assertRaises(ValueError):
            self.wire.p4_gateway.activate(activation(nonce="2"*32))
        self.assertEqual(self.wire.signal.on_wire(event(),now_ms=WHEN).status,
                         "DISPATCH")
        result=[]
        self.assertEqual(poll_private_events(
            owner_root=self.owner,processor=self.wire.trusted_v3_factory(self.flow),
            emit=result.append),1)
        self.assertEqual(result,["OWNER_BRIDGE_EVENT_COMPLETE"])
        self.assertEqual(self.flow.calls,1)
        activated=self.wire.p4_gateway.activate(activation(nonce="3"*32))
        feed=self.wire.p4_gateway.feed_for(activated["session_id"])
        self.assertIsNotNone(feed)
        receipt=decode_latest_test_only(feed)
        self.assertEqual(receipt["media_key"],MEDIA_KEY)
        self.assertEqual(receipt["source_sha256"],activated["source_sha256"])
        self.assertEqual(receipt["translated_count"],240)
        self.assertGreaterEqual(self.reads,6)

    def test_off_after_registered_source_never_reactivates_p4(self):
        self.wire.cache.receive(state(),now_ms=WHEN)
        self.assertEqual(self.wire.signal.on_wire(event(),now_ms=WHEN).status,
                         "DISPATCH")
        self.assertEqual(poll_private_events(
            owner_root=self.owner,processor=self.wire.trusted_v3_factory(self.flow),
            emit=lambda _:None),1)
        self.wire.cache.receive(state("OFF",seq=2,nonce="4"*32),now_ms=WHEN)
        with self.assertRaises(ValueError):
            self.wire.p4_gateway.activate(activation(nonce="5"*32))
        self.assertEqual(self.flow.calls,1)

    def test_bad_unpaired_tap_never_creates_source(self):
        self.wire.cache.receive(state(),now_ms=WHEN)
        malformed=json.loads(event())
        malformed["file_index"]=4
        self.assertEqual(self.wire.signal.on_wire(
            json.dumps(malformed).encode(),now_ms=WHEN).status,"HOLD")
        self.assertFalse((self.owner/"inbox").exists())
        self.assertEqual(self.flow.calls,0)


if __name__=="__main__":
    unittest.main()
