"""Offline HTTPS loopback: new signed P3 POST and legacy P4 on one listener.

Test-generated certificate, fake TV session, fake owner-only TorrServer reader,
fake subtitle bytes. No real TV/TorrServer, network interface, secrets or API.
"""
from __future__ import annotations

from http.client import HTTPSConnection
from http.server import HTTPServer
import json
from pathlib import Path
import sys
import shutil
import ssl
import subprocess
import tempfile
import threading
import time
import unittest

# Discovery's legacy CI invokes unittest with only this directory on
# sys.path. Resolve sibling project modules exactly as earlier P3 tests do.
# Do not rely on GitHub's global PYTHONPATH or import-time cwd.
_POC = Path(__file__).resolve().parent.parent
for _part in ("p3-vietsub-trigger", "p2-aisub"):
    _path = str(_POC / _part)
    if _path not in sys.path:
        sys.path.insert(0, _path)

from activation_gate import PlaybackSelected
from assumed_source_handoff import AssumedEnglishSubtitle
from paired_activation import (
    PairedActivation, activation_request_mac,
)
from p3_p4_shared_https_route import make_p3_p4_handler
from p3_redmi_current_state import SignedRedmiStateCache, sign_synthetic_state
from p3_signed_playback_signal import (
    SignedPlaybackVerifier, sign_synthetic_event,
)
from p3_signed_signal_to_owner import SignedP3ToOwner
from p4_tls import create_tls_context
from synthetic_mock_feed import synthetic_source_srt
from owner_session_bridge import _parse_event


KEY = bytes(range(32))
SESSION = "a" * 32
MOVIE = "Synthetic.Movie.2017.1080p.BluRay.x265-GRP.mkv"
TORRENT = "b" * 40
MEDIA = "media." + "e" * 64


def selected():
    return PlaybackSelected(
        kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
        server_id="owner-paired-torrserver",
        tv_session_id=SESSION, torrent_hash=TORRENT,
        file_index=3, video_name=MOVIE,
        owner_auto_enabled=True, subtitle_choice="ON",
        media_rights_approved=True, local_vi_state="ABSENT",
    )


def signed_wire(*, file_index=3, key=KEY, nonce="c"*32):
    now = int(time.time() * 1000)
    return sign_synthetic_event(
        key, kind="PLAY_REQUEST_ACCEPTED", tv_session_id=SESSION,
        torrent_hash=TORRENT, file_index=file_index,
        sent_at_ms=now, nonce=nonce,
    )


@unittest.skipUnless(shutil.which("openssl"), "local openssl required")
class PairedP3P4HttpsIntegrationTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.owner = self.root / "private_owner"
        self.state = selected()
        self.reads = []
        source = AssumedEnglishSubtitle.from_supplied(
            media_key=MEDIA, fmt="srt", source_bytes=synthetic_source_srt())
        self.p4 = PairedActivation(device_secret=KEY, supplied={MEDIA:source})
        def current():
            self.reads.append("owner_tv")
            return self.state
        self.state_cache = SignedRedmiStateCache(KEY)
        self.p3 = SignedP3ToOwner(
            verifier=SignedPlaybackVerifier(KEY), owner_root=self.owner,
            read_verified_current_selection=current,
        )
        cert = self.root / "loopback-cert.pem"
        private = self.root / "loopback-key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-keyout", str(private), "-out", str(cert), "-days", "1",
            "-subj", "/CN=127.0.0.1",
            "-addext", "subjectAltName=IP:127.0.0.1",
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        context = create_tls_context(cert, private)
        self.server = HTTPServer(
            ("127.0.0.1", 0), make_p3_p4_handler(self.p4, self.p3, self.state_cache))
        self.server.socket = context.wrap_socket(
            self.server.socket, server_side=True)
        worker = threading.Thread(target=self.server.serve_forever,
                                  kwargs={"poll_interval":0.05}, daemon=True)
        worker.start()
        self.addCleanup(worker.join, 3)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.port = self.server.server_address[1]
        self.trusted = ssl.create_default_context(cafile=str(cert))
        self.trusted.check_hostname = True

    def request(self, method, path, body=None, headers=None):
        client = HTTPSConnection("127.0.0.1", self.port,
                                 context=self.trusted, timeout=5)
        try:
            client.request(method, path, body=body, headers=headers or {})
            reply = client.getresponse()
            return reply.status, reply.read()
        finally:
            client.close()

    def test_exact_valid_signed_tv_signal_enqueues_v3_without_p4_or_api_call(self):
        raw = signed_wire()
        status, body = self.request("POST", "/p3/selection", raw,
                                    {"Content-Type":"application/json"})
        self.assertEqual((status, body), (204, b""))
        self.assertEqual(self.reads, ["owner_tv", "owner_tv"])
        [event] = list((self.owner / "inbox").glob("event-*.json"))
        parsed = _parse_event(event)
        self.assertEqual(parsed.tv_session_id, SESSION)
        self.assertEqual(parsed.selected_video_filename, MOVIE)
        self.assertEqual(len(self.p4._PairedActivation__feeds), 0)

    def test_tamper_duplicate_and_wrong_selected_file_never_enqueue(self):
        raw = signed_wire()
        status, _ = self.request("POST", "/p3/selection", raw,
                                  {"Content-Type":"application/json"})
        self.assertEqual(status, 204)
        again, _ = self.request("POST", "/p3/selection", raw,
                                {"Content-Type":"application/json"})
        self.assertEqual(again, 403)
        changed = json.loads(signed_wire(nonce="d"*32))
        changed["file_index"] = 4
        tampered, _ = self.request("POST", "/p3/selection",
                                   json.dumps(changed).encode(),
                                   {"Content-Type":"application/json"})
        self.assertEqual(tampered, 403)
        mismatch = signed_wire(file_index=4,nonce="e"*32)
        wrong, _ = self.request("POST", "/p3/selection", mismatch,
                                {"Content-Type":"application/json"})
        self.assertEqual(wrong, 403)
        self.assertEqual(len(list((self.owner / "inbox").glob("event-*.json"))), 1)

    def test_no_content_or_unknown_p3_paths_block_before_reader(self):
        for path, body, headers, status in (
            ("/p3/selection?debug=1", signed_wire(), {"Content-Type":"application/json"}, 404),
            ("/p3/selection", b"x" * 1100, {"Content-Type":"application/json"}, 413),
            ("/p3/selection", signed_wire(), {"Content-Type":"text/plain"}, 415),
            ("/p3/other", signed_wire(), {"Content-Type":"application/json"}, 404),
        ):
            with self.subTest(path=path, status=status):
                got, _ = self.request("POST", path, body, headers)
                self.assertEqual(got, status)
        self.assertEqual(self.reads, [])
        self.assertFalse(self.owner.exists())

    def test_same_handler_preserves_existing_authenticated_p4_activation(self):
        nonce = "f" * 32
        request = {
            "schema":"TTV-P4-ACTIVATE-V1", "media_key":MEDIA,
            "nonce":nonce,
            "auth":activation_request_mac(KEY, MEDIA, nonce),
        }
        status, raw = self.request(
            "POST", "/p4/activate", json.dumps(request).encode("ascii"),
            {"Content-Type":"application/json"})
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(raw)["schema"], "TTV-P4-ACTIVATED-V1")
        self.assertEqual(self.reads, [])
        self.assertFalse(self.owner.exists())
        bad, _ = self.request("POST", "/p4/activate",
                              json.dumps(dict(request, auth="0"*64)).encode("ascii"),
                              {"Content-Type":"application/json"})
        self.assertEqual(bad, 403)

    def signed_state(self, *, nonce="9"*32, active=True,
                     subtitle_choice="ON", session=SESSION):
        now=int(time.time()*1000)
        return sign_synthetic_state(
            KEY, boot_id="1"*32, sequence=1,
            kind="PLAY_REQUEST_ACCEPTED", tv_session_id=session,
            torrent_hash=TORRENT, file_index=3, active=active,
            subtitle_choice=subtitle_choice, sent_at_ms=now, nonce=nonce)

    def test_status_https_hmac_has_no_side_effects_until_separate_play(self):
        status, body=self.request(
            "POST","/p3/state",self.signed_state(),
            {"Content-Type":"application/json"})
        self.assertEqual((status,body),(204,b""))
        self.assertEqual(self.state_cache.read_fresh().tv_session_id,SESSION)
        self.assertEqual(self.reads,[])
        self.assertFalse(self.owner.exists())
        self.assertEqual(len(self.p4._PairedActivation__feeds),0)
        # HMAC replay remains blocked independently of P3 selected-play route.
        again,_=self.request(
            "POST","/p3/state",self.signed_state(),
            {"Content-Type":"application/json"})
        self.assertEqual(again,403)

    def test_status_auth_tamper_path_and_off_do_not_start_subtitle(self):
        original=json.loads(self.signed_state())
        original["subtitle_choice"]="OFF"   # HMAC no longer authentic
        bad,_=self.request(
            "POST","/p3/state",json.dumps(original).encode(),
            {"Content-Type":"application/json"})
        self.assertEqual(bad,403)
        weird,_=self.request(
            "POST","/p3/state?cache=1",self.signed_state(),
            {"Content-Type":"application/json"})
        self.assertEqual(weird,404)
        self.assertEqual(self.reads,[])
        self.assertFalse(self.owner.exists())

    def test_p3_route_cannot_be_used_to_read_private_p4_revision(self):
        status, _ = self.request("GET", "/p3/selection")
        self.assertEqual(status, 404)
        self.assertEqual(self.reads, [])
        self.assertFalse(self.owner.exists())


if __name__ == "__main__":
    unittest.main()
