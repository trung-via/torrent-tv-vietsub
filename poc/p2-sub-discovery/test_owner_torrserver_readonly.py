"""Owner Windows TorrServer exact-file metadata: synthetic + local loopback."""
from __future__ import annotations

from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import threading
import unittest

from owner_torrserver_readonly import (
    OwnerLocalTorrServer, OwnerTorrServerReader, OwnerTorrServerReadError,
    _local_post,
)
from owner_selected_file_resolver import TorrServerSelectedFile


HASH = "a" * 40
PROFILE = "owner-main-laptop-torrserver"
NAME = "Synthetic.Movie.2017.1080p.BluRay.x265-GRP.mkv"


def torrent(**update):
    obj = {
        "hash": HASH,
        "file_stats": [
            {"id": 0, "path": "Feature/" + NAME,
             "length": 1_000_000_000},
            {"id": 1, "path": "Feature/extras.txt", "length": 100},
        ],
    }
    obj.update(update)
    return json.dumps(obj, separators=(",", ":")).encode("utf-8")


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.records = []
        def fake(url, payload, timeout):
            self.records.append((url, payload, timeout))
            return torrent()
        self.reader = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE, 8090), transport=fake)

    def test_only_owner_pinned_profile_and_readonly_get_action(self):
        value = self.reader(PROFILE, HASH, 0)
        self.assertEqual(value, TorrServerSelectedFile(
            0, "Feature/" + NAME, 1_000_000_000))
        self.assertEqual(len(self.records), 1)
        url, body, timeout = self.records[0]
        self.assertEqual(url, "http://127.0.0.1:8090/torrents")
        self.assertEqual(json.loads(body), {"action":"get","hash":HASH})
        self.assertEqual(timeout, 4.0)
        self.assertNotIn(b"add", body)
        self.assertNotIn(b"rem", body)
        self.assertNotIn(b"stream", body)

    def test_fallback_to_torrserver_embedded_files_compatible_with_omp(self):
        fallback = torrent(file_stats=[], data=json.dumps({
            "TorrServer": {"Files": [
                {"id":0,"path":"Feature/" + NAME,"length":1234}]}}))
        reader = OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE,8090),
            transport=lambda *_: fallback)
        self.assertEqual(reader(PROFILE,HASH,0).length,1234)

    def test_wrong_profile_or_hash_or_index_prevents_even_local_request(self):
        invalids = [
            ("different-server",HASH,0), (PROFILE,"x"*40,0),
            (PROFILE,HASH,True), (PROFILE,HASH,-1), (PROFILE,HASH,90000),
            (PROFILE,HASH.upper(),0),
        ]
        for args in invalids:
            with self.subTest(args=args):
                with self.assertRaisesRegex(OwnerTorrServerReadError,
                                            "IDENTITY_INVALID"):
                    self.reader(*args)
        self.assertEqual(self.records, [])

    def test_duplicate_file_index_and_wrong_source_hash_never_return_path(self):
        for payload in (
            torrent(hash="b"*40),
            torrent(file_stats=[
                {"id":0,"path":"A.mkv","length":100},
                {"id":0,"path":"B.mkv","length":200}]),
            torrent(file_stats=[{"id":1,"path":"One.mkv","length":2}]),
            torrent(file_stats=[{"id":0,"path":"Wrong.mkv","length":True}]),
            torrent(file_stats=[{"id":0,"path":"Wrong.mkv","length":0}]),
        ):
            reader = OwnerTorrServerReader(
                OwnerLocalTorrServer(PROFILE,8090),
                transport=lambda *_: payload)
            with self.subTest(payload=payload[:70]):
                with self.assertRaises(OwnerTorrServerReadError):
                    reader(PROFILE,HASH,0)

    def test_rejects_invalid_owner_port_without_network_call(self):
        for port in (0, 80, 1023, 65536, -1, True, "8090"):
            with self.subTest(port=port):
                with self.assertRaisesRegex(
                    OwnerTorrServerReadError, "TS_OWNER_PROFILE_INVALID"):
                    OwnerLocalTorrServer(PROFILE,port)
        with self.assertRaises(OwnerTorrServerReadError):
            OwnerLocalTorrServer("../host",8090)

    def test_raw_errors_never_leak_endpoint_or_torrent_filename(self):
        def danger(*_):
            raise OSError("private://owner-machine/secret-path?apikey=secret")
        reader=OwnerTorrServerReader(
            OwnerLocalTorrServer(PROFILE,8090),transport=danger)
        with self.assertRaises(OwnerTorrServerReadError) as cm:
            reader(PROFILE,HASH,0)
        self.assertEqual(str(cm.exception), "TS_GET_UNAVAILABLE")


class LoopbackOnlyTests(unittest.TestCase):
    def test_real_localhost_http_uses_post_get_and_no_redirects(self):
        state = {"requests":[],"redirect":False}
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_): pass
            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length","0")))
                state["requests"].append((self.path, json.loads(body)))
                if state["redirect"]:
                    self.send_response(302)
                    self.send_header("Location","http://198.51.100.1/evil")
                    self.end_headers()
                    return
                data=torrent()
                self.send_response(200)
                self.send_header("Content-Type","application/json")
                self.send_header("Content-Length",str(len(data)))
                self.end_headers()
                self.wfile.write(data)
        server=HTTPServer(("127.0.0.1",0),Handler)
        worker=threading.Thread(target=server.serve_forever,
                                kwargs={"poll_interval":0.05},daemon=True)
        worker.start()
        try:
            cfg=OwnerLocalTorrServer(PROFILE,server.server_address[1])
            reader=OwnerTorrServerReader(cfg)
            self.assertEqual(reader(PROFILE,HASH,0).path,
                             "Feature/" + NAME)
            self.assertEqual(state["requests"], [
                ("/torrents", {"action":"get","hash":HASH})])
            state["redirect"]=True
            with self.assertRaisesRegex(
                OwnerTorrServerReadError,"TS_GET_UNAVAILABLE"):
                reader(PROFILE,HASH,0)
            # Exactly two localhost requests; redirect target was never
            # followed. No WAN/hostname or media bytes involved.
            self.assertEqual(len(state["requests"]),2)
        finally:
            server.shutdown()
            server.server_close()
            worker.join(timeout=3)


if __name__ == "__main__":
    unittest.main()
