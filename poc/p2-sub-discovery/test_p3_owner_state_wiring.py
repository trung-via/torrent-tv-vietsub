"""Synthetic one-wiring proof: state HMAC + selected event + V3 consumer.

Never starts owner Windows server or calls real API. All movie identifiers,
pairing keys and PC profile are artificial and private to temporary fixture.
"""
from __future__ import annotations

from pathlib import Path
import sys
import json

# Legacy D1/D2 CI loads this test without PYTHONPATH for siblings.
_POC = Path(__file__).resolve().parent.parent
for _part in ("p2-aisub", "p3-vietsub-trigger"):
    _sub = str(_POC / _part)
    if _sub not in sys.path:
        sys.path.insert(0, _sub)
import tempfile
import unittest

from paired_activation import PairedActivation
from automatic_vietsub_flow import AutoResult
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from owner_session_bridge import poll_private_events
from p3_owner_state_wiring import compose_owner_redmi_status
from p3_signed_playback_signal import sign_synthetic_event
from p3_redmi_current_state import sign_synthetic_state, RedmiStateRejected


KEY=bytes(range(32))
WHEN=1_800_000_000_000
TORRENT="a"*40
PROFILE="owner-test-profile"
VIDEO="Synthetic.Film.2017.1080p.BluRay-GRP.mkv"
SESSION="b"*32
BOOT="c"*32


class FakeExistingWorker:
    def __init__(self): self.calls=[]
    def selected_media(self, name, **options):
        self.calls.append((name, options))
        return AutoResult("VI_READY")


def state(*, choice="ON", active=True, session=SESSION, seq=1,nonce="d"*32):
    return sign_synthetic_state(
        KEY,boot_id=BOOT,sequence=seq,kind="PLAY_REQUEST_ACCEPTED",
        tv_session_id=session,torrent_hash=TORRENT,file_index=2,
        active=active,subtitle_choice=choice,sent_at_ms=WHEN,nonce=nonce)


def selected(nonce="e"*32,session=SESSION):
    return sign_synthetic_event(
        KEY,kind="PLAY_REQUEST_ACCEPTED",tv_session_id=session,
        torrent_hash=TORRENT,file_index=2,sent_at_ms=WHEN,nonce=nonce)


class CompleteStatusWiringTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.media=Path(self.tmp.name).resolve()/"owner-media"
        self.media.mkdir()
        self.owner=Path(self.tmp.name).resolve()/"owner-private"
        self.reads=0
        response=json.dumps({"hash":TORRENT,"file_stats":[
            {"id":2,"path":"Authorized/"+VIDEO,"length":100000}
        ]}).encode()
        def read_local(url, payload, timeout):
            self.reads+=1
            self.assertTrue(url.startswith("http://127.0.0.1:"))
            self.assertEqual(json.loads(payload),{"action":"get","hash":TORRENT})
            return response
        ts=OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE,8090),transport=read_local)
        self.rights=True
        self.consent=True
        self.vi="ABSENT"
        self.wiring=compose_owner_redmi_status(
            p4_gateway=PairedActivation(device_secret=KEY,supplied={}),
            paired_device_secret=KEY,
            torrserver_reader=ts,owner_root=self.owner,
            private_media_root=self.media,
            owner_auto_allowed=lambda:self.consent,
            media_rights_allowed=lambda *_:self.rights,
            verified_local_vi_state=lambda *_:self.vi,
            locate_owner_pinned_files=lambda *_:None,
        )

    def test_status_required_then_exact_selected_event_and_existing_worker(self):
        # Origin-only event is not a current status proof.
        self.assertEqual(self.wiring.signal.on_wire(
            selected(),now_ms=WHEN).status,"HOLD")
        self.assertEqual(self.reads,0)
        self.assertFalse(self.owner.exists())

        self.wiring.cache.receive(state(),now_ms=WHEN)
        self.assertFalse(self.owner.exists()) # status itself never triggers
        decision=self.wiring.signal.on_wire(selected(nonce="f"*32),now_ms=WHEN)
        self.assertEqual(decision.status,"DISPATCH")
        self.assertEqual(self.wiring.current.read_v3().video_name,VIDEO)
        worker=FakeExistingWorker()
        result=[]
        processed=poll_private_events(
            owner_root=self.owner,
            processor=self.wiring.trusted_v3_factory(worker),
            emit=result.append)
        self.assertEqual(processed,1)
        self.assertEqual(result,["OWNER_BRIDGE_EVENT_COMPLETE"])
        self.assertEqual(len(worker.calls),1)
        name, options=worker.calls[0]
        self.assertEqual(name,VIDEO)
        self.assertEqual(options["verified_media"].torrent_hash,TORRENT)
        self.assertEqual(options["verified_media"].file_index,2)
        self.assertIsNone(options["local_source"])
        self.assertGreaterEqual(self.reads,3)

    def test_off_and_missing_vi_state_never_call_existing_worker(self):
        self.wiring.cache.receive(state(choice="OFF"),now_ms=WHEN)
        self.assertEqual(self.wiring.signal.on_wire(selected(),now_ms=WHEN).status,
                         "HOLD")
        with self.assertRaises(RedmiStateRejected):
            self.wiring.cache.read_fresh()

    def test_no_real_listener_or_extra_translator_is_constructed(self):
        self.assertTrue(callable(self.wiring.handler))
        self.assertTrue(callable(self.wiring.trusted_v3_factory))
        self.assertFalse(self.owner.exists())
        self.assertEqual(self.reads,0)


if __name__=="__main__":
    unittest.main()
