"""Synthetic Redmi current playback heartbeat and real V3 owner reader QA."""
from __future__ import annotations

import hashlib
import hmac
import json
from pathlib import Path
import tempfile
import unittest

from p3_redmi_current_state import (
    SignedRedmiStateCache, RedmiStateRejected, sign_synthetic_state, mac_body,
)
from p3_owner_current_redmi import OwnerCurrentRedmiReader, OwnerTvStateUnavailable
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from p3_signed_playback_signal import SignedPlaybackVerifier, sign_synthetic_event
from p3_signed_signal_to_owner import SignedP3ToOwner
from owner_session_bridge import _parse_event


KEY=bytes(range(32))
WHEN=1_800_000_000_000
BOOT="a"*32
SESSION="b"*32
HASH="c"*40
PROFILE="owner-laptop"
FILENAME="Synthetic.Film.2017.1080p.BluRay-GRP.mkv"


def packet(**change):
    args=dict(boot_id=BOOT,sequence=1,kind="PLAY_REQUEST_ACCEPTED",
              tv_session_id=SESSION,torrent_hash=HASH,file_index=4,
              active=True,subtitle_choice="ON",sent_at_ms=WHEN,nonce="d"*32)
    args.update(change)
    return sign_synthetic_state(KEY,**args)


def selected(**change):
    data=dict(kind="PLAY_REQUEST_ACCEPTED",tv_session_id=SESSION,
              torrent_hash=HASH,file_index=4,sent_at_ms=WHEN,nonce="f"*32)
    data.update(change)
    return sign_synthetic_event(KEY,**data)


class StateTests(unittest.TestCase):
    def test_cross_language_hmac_fixed_vector(self):
        obj=json.loads(packet())
        self.assertEqual(mac_body(obj),(
            "TTV-P3-TV-STATE-V1\n"+BOOT+"\n1\nPLAY_REQUEST_ACCEPTED\n"
            +SESSION+"\n"+HASH+"\n4\n1\nON\n1800000000000\n"
            +"d"*32).encode("ascii"))
        self.assertEqual(len(obj["signature"]),64)
        self.assertEqual(obj["signature"],hmac.new(KEY,mac_body(obj),hashlib.sha256).hexdigest())

    def test_state_fresh_ttl_not_play_event(self):
        c=SignedRedmiStateCache(KEY)
        st=c.receive(packet(),now_ms=WHEN,monotonic_s=10.0)
        self.assertEqual((st.active,st.subtitle_choice), (True,"ON"))
        self.assertEqual(c.read_fresh(monotonic_s=18.0).tv_session_id,SESSION)
        with self.assertRaisesRegex(RedmiStateRejected,"STALE"):
            c.read_fresh(monotonic_s=18.0001)

    def test_on_off_other_and_stopped_never_attested_active(self):
        for change in ({"subtitle_choice":"OFF"},{"subtitle_choice":"OTHER"},
                       {"active":False}):
            with self.subTest(change=change):
                c=SignedRedmiStateCache(KEY)
                c.receive(packet(**change),now_ms=WHEN,monotonic_s=100)
                with self.assertRaisesRegex(RedmiStateRejected,"OFF_OR_INACTIVE"):
                    c.read_fresh(monotonic_s=101)

    def test_tamper_and_duplicate_and_clock_skew_refused(self):
        for key,value in (
            ("active",False),("subtitle_choice","OFF"),
            ("tv_session_id","a"*32),("torrent_hash","f"*40),
            ("file_index",5),("sequence",2),("kind","NEXT_QUEUE_ITEM_ACCEPTED"),
            ("sent_at_ms",WHEN+100),("nonce","e"*32)):
            with self.subTest(key=key):
                o=json.loads(packet());o[key]=value
                with self.assertRaisesRegex(RedmiStateRejected,"AUTH_FAILED"):
                    SignedRedmiStateCache(KEY).receive(json.dumps(o).encode(),now_ms=WHEN,monotonic_s=1)
        c=SignedRedmiStateCache(KEY)
        c.receive(packet(),now_ms=WHEN,monotonic_s=10)
        with self.assertRaisesRegex(RedmiStateRejected,"REPLAY"):
            c.receive(packet(),now_ms=WHEN,monotonic_s=11)
        with self.assertRaisesRegex(RedmiStateRejected,"CLOCK_SKEW"):
            SignedRedmiStateCache(KEY).receive(packet(),now_ms=WHEN+15001,monotonic_s=1)

    def test_ordered_a_to_b_to_a_with_new_session_and_sequence(self):
        c=SignedRedmiStateCache(KEY)
        c.receive(packet(),now_ms=WHEN,monotonic_s=10)
        c.receive(packet(tv_session_id="e"*32,sequence=2,nonce="f"*32,
                         kind="NEXT_QUEUE_ITEM_ACCEPTED"),
                  now_ms=WHEN,monotonic_s=11)
        self.assertEqual(c.read_fresh(monotonic_s=12).tv_session_id,"e"*32)
        with self.assertRaisesRegex(RedmiStateRejected,"OUT_OF_ORDER"):
            c.receive(packet(tv_session_id=SESSION,sequence=1,nonce="1"*32),
                      now_ms=WHEN,monotonic_s=13)
        c.receive(packet(tv_session_id=SESSION,sequence=3,nonce="2"*32),
                  now_ms=WHEN,monotonic_s=14)
        self.assertEqual(c.read_fresh(monotonic_s=15).tv_session_id,SESSION)

    def test_new_boot_requires_prior_status_expiry(self):
        c=SignedRedmiStateCache(KEY)
        c.receive(packet(),now_ms=WHEN,monotonic_s=10)
        other=packet(boot_id="9"*32,nonce="8"*32)
        with self.assertRaisesRegex(RedmiStateRejected,"BOOT_CHANGE"):
            c.receive(other,now_ms=WHEN,monotonic_s=11)
        c.receive(other,now_ms=WHEN,monotonic_s=19)
        self.assertEqual(c.read_fresh(monotonic_s=20).boot_id,"9"*32)

    def test_invalid_type_and_extra_or_duplicated_fields(self):
        raw=json.loads(packet())
        for data in (
            dict(raw,sequence=True), dict(raw,active=1),
            dict(raw,file_index=-1),dict(raw,boot_id="../bad"),
            dict(raw,media_title="stolen title"),dict(raw,torrent_hash="bad")):
            with self.assertRaises(RedmiStateRejected):
                SignedRedmiStateCache(KEY).receive(json.dumps(data).encode(),
                                                    now_ms=WHEN,monotonic_s=10)
        with self.assertRaises(RedmiStateRejected):
            SignedRedmiStateCache(KEY).receive(
                b'{"schema":"TTV-P3-TV-STATE-V1","schema":"TTV-P3-TV-STATE-V1"}',
                now_ms=WHEN,monotonic_s=10)


class OwnerBridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve()/"private-owner"
        self.cache=SignedRedmiStateCache(KEY)
        self.reads=[]
        payload=json.dumps(dict(
            hash=HASH,file_stats=[dict(id=4,path="Feature/"+FILENAME,length=123456)]),
            separators=(",",":")).encode()
        def transport(url,body,timeout):
            self.reads.append((url,json.loads(body)))
            return payload
        self.torrent=OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE,8090),transport=transport)
        self.consent=True
        self.rights=True
        self.vi="ABSENT"
        self.reader=OwnerCurrentRedmiReader(
            state_cache=self.cache,torrserver=self.torrent,
            owner_auto_allowed=lambda:self.consent,
            media_rights_allowed=lambda *_:self.rights,
            verified_local_vi_state=lambda *_:self.vi)

    def test_no_p3_play_signal_can_invent_verified_current_tv(self):
        with self.assertRaises(OwnerTvStateUnavailable):
            self.reader.read_playback()
        self.assertEqual(self.reads,[])

    def test_signed_state_plus_exact_owner_torrserver_yields_real_v3_identity(self):
        self.cache.receive(packet(),now_ms=WHEN,monotonic_s=10)
        # Use injected monotonic clock for fresh state at deterministic test time
        import p3_redmi_current_state as mod
        previous=mod.time.monotonic
        mod.time.monotonic=lambda:11.0
        try:
            playback=self.reader.read_playback()
            v3=self.reader.read_v3()
        finally:
            mod.time.monotonic=previous
        self.assertEqual(playback.video_name,FILENAME)
        self.assertEqual(playback.server_id,PROFILE)
        self.assertEqual(playback.tv_session_id,SESSION)
        self.assertEqual(v3.video_name,playback.video_name)
        self.assertEqual((v3.viewer_choice,v3.attested),("ON",True))
        self.assertEqual(self.reads[0][1],{"action":"get","hash":HASH})

    def test_unauthorized_on_off_or_unknown_vi_blocks(self):
        self.cache.receive(packet(),now_ms=WHEN,monotonic_s=10)
        import p3_redmi_current_state as mod
        previous=mod.time.monotonic;mod.time.monotonic=lambda:11
        try:
            self.vi="UNKNOWN"
            self.assertEqual(self.reader.read_playback().local_vi_state,"UNKNOWN")
            self.rights=False
            self.assertFalse(self.reader.read_playback().media_rights_approved)
            self.consent=False
            self.assertFalse(self.reader.read_playback().owner_auto_enabled)
        finally:
            mod.time.monotonic=previous

    def test_real_signed_selection_requires_separate_fresh_status_and_owner_policy(self):
        import p3_redmi_current_state as mod
        previous=mod.time.monotonic;mod.time.monotonic=lambda:11
        adapter=SignedP3ToOwner(
            verifier=SignedPlaybackVerifier(KEY),owner_root=self.root,
            read_verified_current_selection=self.reader.read_playback)
        try:
            # Selection HMAC alone cannot enable search or create private V3.
            self.assertEqual(adapter.on_wire(selected(),now_ms=WHEN).status,"HOLD")
            self.assertFalse(self.root.exists())
            self.cache.receive(packet(),now_ms=WHEN,monotonic_s=10)
            resp=adapter.on_wire(selected(nonce="a"*32),now_ms=WHEN)
            self.assertEqual(resp.status,"DISPATCH")
            event,=list((self.root/"inbox").glob("event-*.json"))
            self.assertEqual(_parse_event(event).tv_session_id,SESSION)
        finally:
            mod.time.monotonic=previous


if __name__=="__main__":
    unittest.main()
