"""R0 HTTPS response/classification regression; no sockets, TV or providers."""
from __future__ import annotations

from email.message import Message
from io import BytesIO
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

_POC = Path(__file__).resolve().parent.parent
for _part in ("p3-vietsub-trigger", "p2-aisub"):
    _path = str(_POC / _part)
    if _path not in sys.path:
        sys.path.insert(0, _path)

from paired_activation import PairedActivation
from activation_gate import TriggerDecision
from p3_redmi_current_state import SignedRedmiStateCache, sign_synthetic_state
from p3_signed_playback_signal import SignedPlaybackVerifier
from p3_signed_signal_to_owner import SignedP3ToOwner
from p3_ingress_telemetry import P3IngressTelemetry
from p3_p4_shared_https_route_r0 import make_p3_p4_handler_r0
from test_p3_p4_shared_https_route import KEY, SESSION, TORRENT, selected, signed_wire


class R0SelectionHandlerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.owner = Path(temp.name).resolve() / "private"
        self.state = selected()
        self.p3 = SignedP3ToOwner(
            verifier=SignedPlaybackVerifier(KEY), owner_root=self.owner,
            read_verified_current_selection=lambda: self.state)
        self.ingress = P3IngressTelemetry()
        gateway = PairedActivation(device_secret=KEY, supplied={})
        self.handler = make_p3_p4_handler_r0(gateway, self.p3,
                                             ingress=self.ingress)

    def request(self, body: bytes):
        handler = self.handler.__new__(self.handler)
        handler.path = "/p3/selection"
        handler.headers = Message()
        handler.headers["Content-Type"] = "application/json"
        handler.headers["Content-Length"] = str(len(body))
        handler.rfile = BytesIO(body)
        handler.send_error = mock.Mock()
        handler.send_response = mock.Mock()
        handler.send_header = mock.Mock()
        handler.end_headers = mock.Mock()
        return handler

    def test_wait_track_inventory_classified_and_http_reset_once(self):
        from dataclasses import replace
        self.state = replace(self.state, local_vi_state="UNKNOWN")
        handler = self.request(signed_wire(nonce="1" * 32))
        handler.send_error.side_effect = ConnectionResetError(10054, "closed")
        handler.do_POST()
        handler.send_error.assert_called_once_with(403)
        counts = self.ingress.snapshot()
        self.assertEqual(counts["selection_rejected"], 1)
        self.assertEqual(counts[
            "selection_rejected_current_tv_or_torrserver_unavailable"], 1)
        self.assertEqual(counts["selection_rejected_unknown"], 0)
        self.assertFalse(self.owner.exists())

    def test_successful_dispatch_client_reset_does_not_forge_403(self):
        handler = self.request(signed_wire(nonce="2" * 32))
        handler.send_response.side_effect = ConnectionResetError(10054, "closed")
        handler.do_POST()
        handler.send_error.assert_not_called()
        self.assertEqual(self.ingress.snapshot()["selection_dispatched"], 1)
        self.assertEqual(self.ingress.snapshot()["selection_rejected"], 0)
        self.assertEqual(len(list((self.owner / "inbox").glob("event-*.json"))), 1)

    def test_bad_hmac_is_one_reject_with_no_enqueue(self):
        handler = self.request(signed_wire(key=bytes([99]) * 32, nonce="3" * 32))
        handler.do_POST()
        handler.send_error.assert_called_once_with(403)
        self.assertEqual(self.ingress.snapshot()["selection_rejected_bad_wire"], 1)
        self.assertFalse(self.owner.exists())

    def test_status_heartbeat_is_not_blocked_by_slow_selection(self):
        """R0 threading cannot serialize a slow metadata read with status."""
        cache = SignedRedmiStateCache(KEY)
        gateway = PairedActivation(device_secret=KEY, supplied={})
        handler_type = make_p3_p4_handler_r0(
            gateway, self.p3, state_cache=cache, ingress=self.ingress)
        slow = self.request(signed_wire(nonce="4" * 32))
        slow.__class__ = handler_type
        entered = threading.Event()
        release = threading.Event()
        exited = threading.Event()
        def waiting_wire(_body):
            entered.set()
            if not release.wait(3):
                raise AssertionError("synthetic selection held too long")
            return TriggerDecision("SKIP", "MEDIA_IDENTIFIED_AWAIT_VIEWER_REQUEST")
        def run_selection():
            try:
                slow.do_POST()
            finally:
                exited.set()
        with mock.patch.object(self.p3, "on_wire", side_effect=waiting_wire):
            worker = threading.Thread(target=run_selection, daemon=True)
            worker.start()
            try:
                self.assertTrue(entered.wait(1))
                body = sign_synthetic_state(
                    KEY, boot_id="1" * 32, sequence=1,
                    kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
                    torrent_hash=TORRENT, file_index=3, active=True,
                    subtitle_choice="REQUESTED", sent_at_ms=int(time.time() * 1000),
                    nonce="5" * 32)
                status = self.request(body)
                status.__class__ = handler_type
                status.path = "/p3/state"
                status.do_POST()
                status.send_response.assert_called_once_with(204)
                self.assertEqual(cache.read_fresh().tv_session_id, SESSION)
                self.assertFalse(exited.is_set())
            finally:
                release.set()
                worker.join(3)
            self.assertTrue(exited.is_set())
