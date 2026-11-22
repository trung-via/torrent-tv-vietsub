"""Offline, content-free tests for the owner-bound Matroska Range probe."""
import hashlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).parent / "operations" / "owner-ts-ebml-range-readonly.py"
SPEC = importlib.util.spec_from_file_location("ebml_readonly_probe", SCRIPT)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


class OwnerBoundProbeTests(unittest.TestCase):
    def test_owner_interactive_wrapper_pins_the_python_source(self):
        wrapper = (SCRIPT.parent / "owner-ts-ebml-owner-readonly.ps1").read_text("utf-8")
        source_hash = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()
        self.assertIn("'" + source_hash + "'", wrapper)
        self.assertIn("TTV-OWNER-EBML-CUES-V1", wrapper)

    def test_only_matching_owner_event_is_selected(self):
        profile, wanted = "owner_test", "video-b.mkv"
        fingerprint = hashlib.sha256(
            "\0".join((profile, "b" * 40, "1")).encode()).hexdigest()
        torrents = [
            {"hash": "a" * 40, "file_stats": [{"id": 0, "path": "video-a.mkv"}]},
            {"hash": "b" * 40, "file_stats": [{"id": 1, "path": wanted}]},
        ]
        requested = []

        def fake_api(path, body=None, cap=262144):
            requested.append(path)
            if path == "/torrents":
                return torrents
            if path == "/ffp/" + "b" * 40 + "/1":
                return {"streams": [
                    {"codec_type": "subtitle", "codec_name": "subrip",
                     "tags": {"language": "eng"}}
                ]}
            self.fail("Probed an unrelated torrent")

        with patch.object(PROBE, "recent_owner_selections",
                          return_value=(profile, [(wanted, fingerprint)])):
            with patch.object(PROBE, "api", side_effect=fake_api):
                result = PROBE.candidate()
        self.assertEqual(result, ("b" * 40, 1, 1))
        self.assertEqual(len(requested), 2)

    def test_unmatched_owner_event_cannot_fall_back_to_en_guess(self):
        profile, name, tor = "owner_test", "same.mkv", "c" * 40
        fingerprint = hashlib.sha256(
            "\0".join((profile, "d" * 40, "0")).encode()).hexdigest()
        torrents = [{"hash": tor, "file_stats": [{"id": 0, "path": name}]}]
        with patch.object(PROBE, "recent_owner_selections",
                          return_value=(profile, [(name, fingerprint)])):
            with patch.object(PROBE, "api", return_value=torrents):
                with self.assertRaises(PROBE.DiagnosticStop) as caught:
                    PROBE.candidate()
        self.assertEqual(caught.exception.code, "OWNER_SELECTION_NOT_FOUND")

    def test_small_subtitle_block_needs_only_one_read(self):
        payload = b"\x81\x00\x00\x00sample"  # track, time offset, flags, text
        block = b"\xa3" + bytes([0x80 + len(payload)]) + payload

        class LocalReader:
            def __init__(self):
                self.calls = 0

            def read(self, at, length):
                self.calls += 1
                return (block + b"\x00" * 768)[at:at + length]

        reader = LocalReader()
        kind, content = PROBE.Ranges.small_element(reader, 0)
        self.assertEqual(kind, 0xA3)
        self.assertEqual(content, payload)
        self.assertEqual(reader.calls, 1)

    def test_distant_cues_get_two_bounded_attempts_not_indefinite_retry(self):
        reader = PROBE.Ranges("a" * 40, 0)
        with patch.object(PROBE.OPENER, "open", side_effect=TimeoutError) as opening:
            with patch.object(PROBE.time, "sleep") as sleeping:
                with self.assertRaises(PROBE.DiagnosticStop) as caught:
                    reader.read(1_000_000, 16)
        self.assertEqual(caught.exception.code, "RANGE_TIMEOUT")
        self.assertEqual(reader.requests, 2)
        self.assertEqual([call.kwargs["timeout"] for call in opening.call_args_list],
                         [3, 8])
        sleeping.assert_called_once_with(0.35)

    def test_sparse_timeout_can_recover_without_new_media_identity(self):
        reader = PROBE.Ranges("a" * 40, 0)

        class Response:
            status = 206
            headers = {"Content-Range": "bytes 1000000-1000007/1000010"}

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self, maximum):
                self_max = 8
                return b"x" * min(maximum, self_max)

        with patch.object(PROBE.OPENER, "open", side_effect=[TimeoutError(), Response()]):
            with patch.object(PROBE.time, "sleep"):
                self.assertEqual(reader.read(1_000_000, 8), b"x" * 8)
        self.assertEqual(reader.requests, 2)
        self.assertEqual(reader.bytes, 8)
        self.assertEqual(reader.total, 1000010)

    def test_range_http_error_keeps_status_without_private_url(self):
        reader = PROBE.Ranges("b" * 40, 0)
        error = HTTPError("http://invalid.test", 416, "range unsatisfiable", {}, None)
        with patch.object(PROBE.OPENER, "open", side_effect=error):
            with self.assertRaises(PROBE.DiagnosticStop) as caught:
                reader.read(1_000_000, 16)
        self.assertEqual(caught.exception.code, "RANGE_HTTP_416")
        self.assertEqual(reader.requests, 1)

    def test_header_uses_short_timeout_and_remote_failure_is_classified(self):
        reader = PROBE.Ranges("c" * 40, 0)
        error = URLError(ConnectionRefusedError())
        with patch.object(PROBE.OPENER, "open", side_effect=error) as opening:
            with self.assertRaises(PROBE.DiagnosticStop) as caught:
                reader.read(0, 16)
        self.assertEqual(caught.exception.code, "RANGE_CONNECTION_ERROR")
        self.assertEqual(opening.call_args.kwargs["timeout"], 3)


if __name__ == "__main__":
    unittest.main()
