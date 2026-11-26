"""Synthetic native callback tests: no Windows/browser/provider effects."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from threading import Event
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
import json
import sqlite3
import os
from contextlib import ExitStack
from unittest import mock
from types import SimpleNamespace

from agy_opensubtitles_acquisition import AgyEnglishUnavailable
from agy_v13_browser_evidence import BrowserRequest, make_v13_acquirer, VERIFICATION_REVISION
from agy_v13_native_producer import (
    NativeBrowserProducer, measured_metadata, native_cache_verified,
    probe_selected, _ensure_browser_listener, NativeNoCall, NativeTerminalNoSource, _terminal_no_source,
    _download_observation, _finish_no_source, _job, _write,
)
from test_agy_v13_browser_evidence import MEDIA, proof
from owner_torrserver_ffp_tracks import TorrServerProbeBlocked


class NativeProducerTests(unittest.TestCase):
    def test_shared_relative_rule_does_not_block_session_or_edit_globals(self):
        from agy_v13_native_producer import _session_settings
        with TemporaryDirectory() as temp:
            home = Path(temp) / "home"
            shared = home / ".gemini/config/config.json"
            primary = home / ".gemini/antigravity-cli/settings.json"
            shared.parent.mkdir(parents=True)
            primary.parent.mkdir(parents=True)
            shared.write_text(json.dumps({"permissions": {
                "deny": ["write_file(.git/aios/)"],
                "allow": ["read_file(.git/aios/)"]}}), encoding="utf-8")
            primary.write_text(json.dumps({"permissions": {
                "deny": ["write_file(.git/aios/)"]}}), encoding="utf-8")
            originals = (shared.read_bytes(), primary.read_bytes())
            run = Path(temp) / "job"
            run.mkdir()
            settings = json.loads(_session_settings(run, home).read_text(encoding="utf-8"))
            self.assertEqual(settings["permissions"]["deny"],
                             ["write_file(" + (run / ".git/aios").as_posix() + ")"])
            self.assertEqual((shared.read_bytes(), primary.read_bytes()), originals)

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
        self.assertTrue(_terminal_no_source(stream(passive, click, result)))
        clicked = {"step_update": {"tool_name": "call_mcp_tool", "tool_info": {
            "parameters": {"ToolName": "evaluate_script"}, "output": {"clicked": True}}}}
        self.assertFalse(_terminal_no_source(stream(passive, clicked, result)))

    def _search_trace(self):
        rows = []
        for name, output in (("list_pages", "0: https://www.opensubtitles.org/"),
                             ("navigate_page", "navigation complete"),
                             ("evaluate_script", {"rows": [], "heading": "English"})):
            params = {"ServerName": "ttv-browser", "ToolName": name}
            rows.extend(({"step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"parameters": params}}},
                {"step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"parameters": params, "output": output}}}))
        rows.append({"event":"result","result":{"status":"SUCCESS",
            "response":'{"status":"NO_PLAUSIBLE_CANDIDATE"}'}})
        return "\n".join(json.dumps(row) for row in rows)

    def test_real_recipe_trace_requires_unchanged_independent_observations(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            baseline = {"browser":"a","history":"b","files":"c"}
            observe = mock.Mock(side_effect=[baseline, baseline])
            wait = mock.Mock()
            self.assertTrue(_finish_no_source(self._search_trace(), root, root, baseline, root,
                observe=observe, wait=wait))
            self.assertEqual(observe.call_count, 2)
            wait.assert_called_once_with(2)
            self.assertTrue((root/"no-source-observation.json").is_file())
            for changed in (None, {**baseline, "history":"new"}, {**baseline, "files":"new"}):
                self.assertFalse(_finish_no_source(self._search_trace(), root, root, baseline, root,
                    observe=mock.Mock(side_effect=[baseline, changed]), wait=mock.Mock()))
            self.assertFalse(_finish_no_source(self._search_trace(), root, root, None, root,
                observe=mock.Mock(), wait=mock.Mock()))

    def test_history_and_directory_observation_detects_downloads_and_partial(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            profile, dest = root/"profile", root/"downloads"
            (profile/"Default").mkdir(parents=True)
            dest.mkdir()
            (profile/"Default/Preferences").write_text(json.dumps({"download":{"default_directory":str(dest)}}))
            history = profile/"Default/History"
            with sqlite3.connect(history) as con:
                con.execute("create table downloads(id integer,state integer,start_time integer,received_bytes integer,total_bytes integer,target_path text,current_path text)")
            with mock.patch("agy_v13_native_producer._browser_identity", return_value=("browser","tab")):
                baseline = _download_observation(profile, dest)
                self.assertIsNotNone(baseline)
                self.assertEqual(_download_observation(profile, dest), baseline)
                partial = dest/"new.crdownload"
                partial.write_bytes(b"partial")
                self.assertIsNone(_download_observation(profile, dest))
                partial.unlink()
                with sqlite3.connect(history) as con:
                    con.execute("insert into downloads values(1,0,123,0,5,'x','x')")
                self.assertIsNone(_download_observation(profile, dest))
                with sqlite3.connect(history) as con:
                    con.execute("update downloads set state=2")
                self.assertNotEqual(_download_observation(profile, dest), baseline)

    def test_old_cache_revision_revalidates_retained_bytes_without_provider(self):
        with TemporaryDirectory() as temp:
            root = Path(temp)
            execute = mock.Mock(return_value=proof())
            producer = NativeBrowserProducer(profile=root, probe=lambda _: (7200, 24), execute=execute)
            asset = make_v13_acquirer(producer)(MEDIA, root)
            job = _job(root, MEDIA)
            receipt = json.loads((job/"verified.json").read_text())
            self.assertEqual(receipt["verification_revision"], VERIFICATION_REVISION)
            receipt.pop("verification_revision")
            _write(job/"verified.json", receipt)
            self.assertTrue(native_cache_verified(root, MEDIA, asset.sha256, asset.cues))
            self.assertEqual(make_v13_acquirer(producer)(MEDIA, root), asset)
            execute.assert_called_once()
            (job/"download.bin").write_bytes(b"changed")
            self.assertFalse(native_cache_verified(root, MEDIA, asset.sha256, asset.cues))
            with self.assertRaises(AgyEnglishUnavailable):
                producer(BrowserRequest(MEDIA), root)
            execute.assert_called_once()

    def test_run_windows_search_no_source_then_b_or_unknown_hold(self):
        import agy_v13_native_producer as native
        for ambiguous in (False, True):
            with self.subTest(ambiguous=ambiguous), TemporaryDirectory() as temp, ExitStack() as stack:
                root = Path(temp)
                profile, dest = root/"profile", root/"downloads"
                profile.mkdir()
                dest.mkdir()
                base = {"browser":"a","history":"b","files":"c"}
                changed = {**base, "history":"changed"}
                browser_calls = []
                observed = mock.Mock(side_effect=[base, changed] if ambiguous else [base, base, base, base])
                def patch(name, **kwargs):
                    return stack.enter_context(mock.patch.object(native, name, **kwargs))
                def fake_run(args, **kwargs):
                    # No redundant help invocation; preserve the job override.
                    self.assertNotIn("--help", args[-1])
                    self.assertIn("--settings $env:TTV_SESSION_SETTINGS", args[-1])
                    self.assertIn("stdout", kwargs)
                    self.assertIn("stderr", kwargs)
                    browser_calls.append(args)
                    if len(browser_calls) == 1:
                        output = self._search_trace()
                    else:
                        rows = [{"step_update":{"tool_name":"call_mcp_tool","tool_info":{
                            "parameters":{"ServerName":"ttv-browser","ToolName":"list_pages"},
                            "output":"0: https://www.opensubtitles.org/"}}}]
                        for event in proof().outcomes:
                            rows.append({"step_update":{"tool_name":"call_mcp_tool","tool_info":{
                                "parameters":{"ServerName":"ttv-browser","ToolName":event["tool"]},
                                "output":event["output"]}}})
                        output = "\n".join(json.dumps(row) for row in rows)
                    kwargs["stdout"].write(output.encode())
                    return SimpleNamespace(returncode=0)
                fake_os = mock.Mock(wraps=os)
                fake_os.name = "nt"
                fake_os.environ = {}
                patch("os", new=fake_os)
                patch("preflight_antigravity", return_value="agy")
                patch("_validated_antigravity_alias", return_value="gemini")
                patch("_verify_browser", return_value="www.opensubtitles.org")
                patch("_session_settings", return_value=root/"session-settings.json")
                patch("_download_destination", return_value=dest)
                patch("_download_observation", new=observed)
                stack.enter_context(mock.patch.object(native.shutil,"which",return_value="pwsh"))
                stack.enter_context(mock.patch.object(native.subprocess,"run",side_effect=fake_run))
                stack.enter_context(mock.patch.object(native.time,"sleep"))
                patch("_fresh_downloads", side_effect=lambda *_: [] if len(browser_calls)==1 else [
                    (proof().download_bytes, proof().artifacts[0])])
                producer = NativeBrowserProducer(profile=profile, probe=lambda _: (7200,24))
                with self.assertRaisesRegex(AgyEnglishUnavailable, "RESULT_UNKNOWN" if ambiguous else "NO_SOURCE"):
                    producer(BrowserRequest(MEDIA),root)
                pending = root/".native-v13/browser.pending"
                self.assertEqual(pending.exists(), ambiguous)
                self.assertEqual((_job(root,MEDIA)/"no-source-observation.json").is_file(), not ambiguous)
                b = replace(MEDIA,file_index=3)
                if ambiguous:
                    with self.assertRaises(AgyEnglishUnavailable):
                        producer(BrowserRequest(b),root)
                    self.assertEqual(len(browser_calls),1)
                else:
                    self.assertEqual(producer(BrowserRequest(b),root).media,b)
                    self.assertEqual(len(browser_calls),2)
                with self.assertRaises(AgyEnglishUnavailable):
                    producer(BrowserRequest(MEDIA),root)
                self.assertEqual(len(browser_calls),1 if ambiguous else 2)

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
