"""Synthetic native callback tests: no Windows/browser/provider effects."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from threading import Event
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import json
from unittest import mock
from types import SimpleNamespace

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import BrowserRequest, make_v13_acquirer
from agy_v13_native_producer import (
    NativeBrowserProducer, measured_metadata, native_cache_verified,
    probe_selected, _ensure_browser_listener, NativeNoCall, NativeTerminalNoSource, _terminal_no_source,
)
from test_agy_v13_browser_evidence import MEDIA, proof
from owner_torrserver_ffp_tracks import TorrServerProbeBlocked


class NativeProducerTests(unittest.TestCase):
    def test_measured_metadata(self):
        self.assertEqual(measured_metadata(b'{"format":{"duration":"7200"},"streams":[{"codec_type":"video","avg_frame_rate":"24/1"}]}'), (7200, 24))
        for raw in (b'{}', b'{"format":{"duration":"7200"},"streams":[{"codec_type":"video","avg_frame_rate":"0/0"}]}'):
            with self.assertRaises(AgyEnglishUnavailable):
                measured_metadata(raw)

    def test_ffp_failure_uses_only_exact_local_metadata_probe(self):
        record = SimpleNamespace(id=MEDIA.file_index, path=MEDIA.filename,
                                 torrent_title=MEDIA.torrent_title, length=10000)
        reader = mock.Mock(return_value=record)
        reader.config.localhost_port = 8090
        metadata = b'{"format":{"duration":"7200"},"streams":[{"codec_type":"video","avg_frame_rate":"24/1"}]}'
        ffp = mock.Mock(side_effect=TorrServerProbeBlocked("P3_FFP_LOCAL_READ_UNAVAILABLE"))
        fallback = mock.Mock(return_value=metadata)
        self.assertEqual(probe_selected(reader, MEDIA, ffp, fallback), (7200, 24))
        ffp.assert_called_once_with(f"http://127.0.0.1:8090/ffp/{MEDIA.torrent_hash}/{MEDIA.file_index}", 8.0)
        fallback.assert_called_once_with(f"http://127.0.0.1:8090/play/{MEDIA.torrent_hash}/{MEDIA.file_index}")
        self.assertTrue(all(call.args == MEDIA.key for call in reader.call_args_list))
        fallback.reset_mock()
        self.assertEqual(probe_selected(reader, MEDIA, mock.Mock(return_value=metadata), fallback), (7200, 24))
        fallback.assert_not_called()
        reader.return_value = SimpleNamespace(id=MEDIA.file_index + 1, path=MEDIA.filename,
                                              torrent_title=MEDIA.torrent_title, length=10000)
        with self.assertRaisesRegex(AgyEnglishUnavailable, "MEDIA_CHANGED"):
            probe_selected(reader, MEDIA, ffp, fallback)
        fallback.assert_not_called()

    def test_ffp_failure_does_not_probe_if_selected_record_changed(self):
        original = SimpleNamespace(id=MEDIA.file_index, path=MEDIA.filename,
                                   torrent_title=MEDIA.torrent_title, length=10000)
        changed = SimpleNamespace(**{**vars(original), "length": 20000})
        reader = mock.Mock(side_effect=[original, changed])
        reader.config.localhost_port = 8090
        fallback = mock.Mock(side_effect=AssertionError("must not read changed file"))
        with self.assertRaisesRegex(AgyEnglishUnavailable, "MEDIA_CHANGED"):
            probe_selected(reader, MEDIA, mock.Mock(side_effect=TorrServerProbeBlocked("UNAVAILABLE")), fallback)
        fallback.assert_not_called()

    def test_browser_recovery_uses_single_bounded_owner_command(self):
        with mock.patch("agy_v13_native_producer.subprocess.run", return_value=SimpleNamespace(returncode=0)) as run:
            _ensure_browser_listener("pwsh", Path("existing-profile"))
            run.assert_called_once()
            cmd = run.call_args.args[0][-1]
            self.assertIn("Start-Process", cmd)
            self.assertIn("remote-debugging-port=9555", cmd)
            self.assertNotIn("Stop-Process", cmd)
            self.assertNotIn("9444", cmd)
            self.assertEqual(run.call_args.kwargs["timeout"], 40)
        with mock.patch("agy_v13_native_producer.subprocess.run", return_value=SimpleNamespace(returncode=4)):
            with self.assertRaisesRegex(AgyEnglishUnavailable, "BROWSER_PROFILE_RUNNING_NO_LISTENER"):
                _ensure_browser_listener("pwsh", Path("existing-profile"))

    def test_one_call_retained_evidence_and_cache_receipt(self):
        calls = []
        def execute(*args):
            calls.append(args)
            return proof()
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            acquire = make_v13_acquirer(producer)
            first = acquire(MEDIA, root)
            second = acquire(MEDIA, root)
            self.assertEqual(first, second)
            self.assertEqual(len(calls), 1)
            self.assertTrue(native_cache_verified(root, MEDIA, first.sha256, first.cues))
            self.assertFalse(native_cache_verified(root, replace(MEDIA, file_index=3), first.sha256, first.cues))

    def test_other_film_waits_for_browser_without_dropping_request(self):
        entered, release = Event(), Event()
        calls = []
        def execute(req, *args):
            calls.append(req.media.file_index)
            if req.media == MEDIA:
                entered.set()
                if not release.wait(5):
                    raise AssertionError("test did not release browser")
            return replace(proof(), media=req.media)
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with ThreadPoolExecutor(max_workers=2) as workers:
                a = workers.submit(producer, BrowserRequest(MEDIA), root)
                self.assertTrue(entered.wait(2))
                b = workers.submit(producer, BrowserRequest(replace(MEDIA, file_index=3)), root)
                try:
                    self.assertEqual(calls, [2])
                finally:
                    release.set()
                self.assertEqual(a.result(timeout=5).media.file_index, 2)
                self.assertEqual(b.result(timeout=5).media.file_index, 3)
            self.assertEqual(calls, [2, 3])

    def test_completed_invalid_source_does_not_block_other_films(self):
        calls = []
        def execute(req, *args):
            calls.append(req.media.file_index)
            return replace(proof(), media=req.media, fresh_download_verified=req.media.file_index != 2)
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with self.assertRaisesRegex(AgyEnglishUnavailable, "SOURCE_REJECTED"):
                producer(BrowserRequest(MEDIA), root)
            self.assertFalse((root / ".native-v13/browser.pending").exists())
            self.assertTrue(list(root.rglob("terminal.json")))
            with self.assertRaises(AgyEnglishUnavailable):
                producer(BrowserRequest(MEDIA), root)
            self.assertEqual(producer(BrowserRequest(replace(MEDIA, file_index=3)), root).media.file_index, 3)
            self.assertEqual(calls, [2, 3])

    def test_preprovider_recovery_retains_receipt_and_calls_only_once(self):
        import agy_v13_native_producer as native
        attempts = []
        def execute(req, run, *args):
            attempts.append(req.media)
            if len(attempts) == 1:
                raise AgyEnglishUnavailable("AGY_EN_NATIVE_TASK_TAB_UNAVAILABLE")
            native._write(run / "provider.started.json", {"started": 1})
            return proof()
        with TemporaryDirectory() as temp, mock.patch.object(native, "run_windows", execute):
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with self.assertRaises(NativeNoCall):
                producer(BrowserRequest(MEDIA), root)
            self.assertFalse((root / ".native-v13/browser.pending").exists())
            self.assertEqual(producer(BrowserRequest(MEDIA), root), proof())
            self.assertEqual(producer(BrowserRequest(MEDIA), root), proof())
            self.assertEqual(len(attempts), 2)
            archives = list((root / ".native-v13").glob("*.preprovider-*"))
            self.assertEqual(len(archives), 1)
            self.assertIn("PRE_PROVIDER_BLOCKED", (archives[0] / "terminal.json").read_text())

    def test_metadata_error_is_proven_no_call(self):
        with TemporaryDirectory() as temp:
            execute = mock.Mock(side_effect=AssertionError("no provider"))
            producer = NativeBrowserProducer(profile=Path(temp), execute=execute,
                probe=mock.Mock(side_effect=AgyEnglishUnavailable("AGY_EN_NATIVE_VIDEO_PROBE_REQUIRED")))
            with self.assertRaises(NativeNoCall):
                producer(BrowserRequest(MEDIA), Path(temp))
            execute.assert_not_called()

    def test_terminal_no_source_releases_browser_but_not_same_job(self):
        calls = []
        def execute(req, *args):
            calls.append(req.media.file_index)
            if req.media == MEDIA:
                raise NativeTerminalNoSource("AGY_EN_NATIVE_NO_SOURCE")
            return replace(proof(), media=req.media)
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            with self.assertRaises(NativeTerminalNoSource):
                producer(BrowserRequest(MEDIA), root)
            with self.assertRaises(AgyEnglishUnavailable):
                producer(BrowserRequest(MEDIA), root)
            self.assertEqual(producer(BrowserRequest(replace(MEDIA, file_index=3)), root).media.file_index, 3)
            self.assertEqual(calls, [2, 3])

    def test_no_source_requires_terminal_and_passive_observed_tools(self):
        passive = {"step_update": {"tool_name": "call_mcp_tool", "tool_info": {
            "parameters": {"ToolName": "list_pages"}, "output": "0: page"}}}
        result = {"event": "result", "result": {"status": "SUCCESS",
            "response": '{"status":"NO_PLAUSIBLE_CANDIDATE"}'}}
        stream = lambda *rows: "\n".join(json.dumps(row) for row in rows)
        self.assertTrue(_terminal_no_source(stream(passive, result)))
        call = {"step_update": {"tool_name": "call_mcp_tool", "tool_info": {
            "parameters": {"ToolName": "list_pages"}}}}
        self.assertTrue(_terminal_no_source(stream(call, passive, result)))
        self.assertFalse(_terminal_no_source(stream(call, result)))
        self.assertFalse(_terminal_no_source(stream(passive)))
        click = {"step_update": {"tool_name": "call_mcp_tool", "tool_info": {
            "parameters": {"ToolName": "evaluate_script"}, "output": "unknown"}}}
        self.assertFalse(_terminal_no_source(stream(passive, click, result)))

    def test_unknown_effect_blocks_same_and_other_media(self):
        calls = []
        def execute(*args):
            calls.append(args)
            raise TimeoutError()
        with TemporaryDirectory() as temp:
            root = Path(temp)
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            for media in (MEDIA, MEDIA, replace(MEDIA, file_index=3)):
                with self.assertRaises(AgyEnglishUnavailable):
                    producer(BrowserRequest(media), root)
            self.assertEqual(len(calls), 1)


if __name__ == "__main__":
    unittest.main()
