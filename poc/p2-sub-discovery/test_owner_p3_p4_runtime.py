"""No-service/no-LAN runtime composition tests on synthetic owner data.

Tests never call a real provider, change Windows, bind sockets or reach TV.
"""
from __future__ import annotations

import json
from pathlib import Path
import ssl
import tempfile
from threading import Event
import unittest
from unittest import mock

from owner_p3_p4_runtime import (
    OwnerRuntimeBlocked, _validate_wiring, _validate_owner_root,
    make_integrated_https_server,
    _serve_and_consume, run_owner_p3_p4_runtime,
)
from owner_torrserver_readonly import OwnerLocalTorrServer, OwnerTorrServerReader
from p3_owner_state_wiring import compose_owner_redmi_status


KEY = bytes(range(32))
TORRENT = "a" * 40


class OwnerIntegratedRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ttv-runtime-synthetic-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.media = self.root / "media"
        self.media.mkdir()
        self.owner = self.root / "owner"
        body = json.dumps({
            "hash": TORRENT, "file_stats": [
                {"id": 2, "path": "Synthetic/Test.Film.2017.mkv", "length": 10000}
            ],
        }).encode()
        reader = OwnerTorrServerReader(
            OwnerLocalTorrServer("test-profile", 8090),
            transport=lambda *_: body,
        )
        self.wiring = compose_owner_redmi_status(
            p4_gateway=None,
            paired_device_secret=KEY,
            torrserver_reader=reader,
            owner_root=self.owner,
            private_media_root=self.media,
            owner_auto_allowed=lambda: True,
            media_rights_allowed=lambda *_: True,
            verified_local_vi_state=lambda *_: "ABSENT",
            locate_owner_pinned_files=lambda *_: None,
            enable_verified_vietsub_ready=True,
        )

    def test_composing_handler_does_not_open_port_or_start_worker(self):
        self.assertIsNotNone(self.wiring.ready_registry)
        self.assertTrue(callable(self.wiring.trusted_v3_factory))
        self.assertTrue(callable(self.wiring.handler))
        self.assertFalse((self.owner / "inbox").exists())
        _validate_wiring(self.wiring)

    def test_signed_p3_and_owner_v3_must_share_one_private_inbox(self):
        _validate_owner_root(self.wiring, self.owner)
        wrong_owner = self.root / "different-inbox"
        with self.assertRaisesRegex(OwnerRuntimeBlocked, "PRIVATE_INBOX_ROOT_MISMATCH"):
            _validate_owner_root(self.wiring, wrong_owner)
        with mock.patch("owner_p3_p4_runtime.make_integrated_https_server") as listener:
            with self.assertRaisesRegex(OwnerRuntimeBlocked, "PRIVATE_INBOX_ROOT_MISMATCH"):
                run_owner_p3_p4_runtime(
                    wiring=self.wiring, owner_root=wrong_owner,
                    cache_root=self.root / "cache",
                    state_root=self.root / "state",
                    host="192.168.1.8", port=8443,
                    tls_cert=self.root / "cert", tls_key=self.root / "key",
                    explicit_start_lan=True)
            listener.assert_not_called()

    def test_refuse_incomplete_wiring_and_loopback_or_wan(self):
        with self.assertRaisesRegex(OwnerRuntimeBlocked, "WIRING_REQUIRED"):
            _validate_wiring(object())
        with mock.patch("owner_p3_p4_runtime.HTTPServer") as server:
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.minimum_version = ssl.TLSVersion.TLSv1_2
            for ip in ("127.0.0.1", "0.0.0.0", "8.8.8.8", "::1"):
                with self.subTest(ip=ip), self.assertRaises(ValueError):
                    make_integrated_https_server(
                        wiring=self.wiring, host=ip, port=8443,
                        tls_context=tls)
            for port in (0, 80, 1023, 65536, True):
                with self.subTest(port=port), self.assertRaises(OwnerRuntimeBlocked):
                    make_integrated_https_server(
                        wiring=self.wiring, host="192.168.1.8", port=port,
                        tls_context=tls)
            server.assert_not_called()

    def test_one_composed_handler_and_tls_wrap_with_fail_cleanup(self):
        class FakeTLS:
            def __init__(self, fail=False):
                self.protocol = ssl.PROTOCOL_TLS_SERVER
                self.minimum_version = ssl.TLSVersion.TLSv1_2
                self.fail = fail
            def wrap_socket(self, sock, *, server_side):
                self.server_side = server_side
                if self.fail:
                    raise OSError("synthetic no certificate")
                return ("tls-only", sock)
        class FakeServer:
            def __init__(self, address, handler):
                self.address = address
                self.handler = handler
                self.socket = object()
                self.closed = False
            def server_close(self):
                self.closed = True
        with (mock.patch("owner_p3_p4_runtime.HTTPServer", FakeServer),
              mock.patch("owner_p3_p4_runtime.ssl.SSLContext", FakeTLS)):
            ctx = FakeTLS()
            result = make_integrated_https_server(
                wiring=self.wiring, host="192.168.1.8", port=8443,
                tls_context=ctx)
            self.assertIs(result.handler, self.wiring.handler)
            self.assertEqual(result.address, ("192.168.1.8", 8443))
            self.assertEqual(result.socket[0], "tls-only")
            self.assertTrue(ctx.server_side)
            with self.assertRaisesRegex(OwnerRuntimeBlocked, "TLS_BIND_FAILED"):
                fail = FakeTLS(fail=True)
                make_integrated_https_server(
                    wiring=self.wiring, host="192.168.1.8", port=8443,
                    tls_context=fail)

    def test_server_lifecycle_passes_existing_v3_factory_and_shuts_down(self):
        class FakeServer:
            def __init__(self):
                self.started = Event()
                self.stop = Event()
                self.closed = False
            def serve_forever(self, poll_interval=0.5):
                self.started.set()
                self.stop.wait(2)
            def shutdown(self):
                self.stop.set()
            def server_close(self):
                self.closed = True
        server = FakeServer()
        captured = []
        def fake_agent(**kwargs):
            self.assertTrue(server.started.wait(2))
            captured.append(kwargs)
            raise RuntimeError("synthetic agent exit")
        with self.assertRaisesRegex(RuntimeError, "synthetic agent exit"):
            _serve_and_consume(
                server=server, wiring=self.wiring,
                owner_root=self.owner,
                cache_root=self.root / "cache",
                state_root=self.root / "state",
                interval_seconds=2.0, agent=fake_agent)
        self.assertTrue(server.stop.is_set())
        self.assertTrue(server.closed)
        self.assertEqual(len(captured), 1)
        self.assertEqual(captured[0]["private_root"], self.owner)
        self.assertEqual(captured[0]["trusted_v3_factory"].__self__, self.wiring)
        self.assertEqual(captured[0]["interval_seconds"], 2.0)
        self.assertTrue(callable(captured[0]["diagnostic_tick"]))
        with mock.patch("owner_p3_p4_runtime.write_diagnostic") as diagnostic:
            captured[0]["diagnostic_tick"]("READY")
            diagnostic.assert_called_once_with(
                owner_root=self.owner, wiring=self.wiring, state="READY")

    def test_no_implicit_live_start_in_ci_or_without_explicit_grant(self):
        with mock.patch("owner_p3_p4_runtime.make_integrated_https_server") as server:
            with self.assertRaisesRegex(OwnerRuntimeBlocked, "EXPLICIT_INTERACTIVE"):
                run_owner_p3_p4_runtime(
                    wiring=self.wiring, owner_root=self.owner,
                    cache_root=self.root / "cache",
                    state_root=self.root / "state",
                    host="192.168.1.8", port=8443,
                    tls_cert=self.root / "cert", tls_key=self.root / "key")
            with mock.patch.dict("os.environ", {"CI": "true"}):
                with self.assertRaisesRegex(OwnerRuntimeBlocked, "EXPLICIT_INTERACTIVE"):
                    run_owner_p3_p4_runtime(
                        wiring=self.wiring, owner_root=self.owner,
                        cache_root=self.root / "cache",
                        state_root=self.root / "state",
                        host="192.168.1.8", port=8443,
                        tls_cert=self.root / "cert", tls_key=self.root / "key",
                        explicit_start_lan=True)
            server.assert_not_called()


if __name__ == "__main__":
    unittest.main()
