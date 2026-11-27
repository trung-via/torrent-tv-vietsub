"""Synthetic tests only: no provider, browser, network, TV or Windows side effects."""
import io
import json
from pathlib import Path
import queue
import tempfile
import unittest
from unittest.mock import patch, Mock

from agy_owner_warm_session import OwnerAgyWarmSession, WarmSessionError
from owner_g2_discovery import MovieQuery, _metadata, discover_movie_batch
from agy_v13_native_producer import NativeBrowserProducer


class FakePipe:
    def __init__(self, owner):
        self.owner = owner
    def write(self, line):
        msg = json.loads(line)
        self.owner.messages.append(msg)
        n = len(self.owner.messages)
        for e in [
            {"event": "step_update", "step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"parameters": {"ToolName": "evaluate_script", "ServerName": "ttv-browser"}}}},
            {"event": "step_update", "step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"output": "fixture metadata"}}},
            {"event": "result", "result": {
                "conversation_id": self.owner.ids[n-1],
                "response": json.dumps({"turn": n})}},
        ]:
            self.owner.lines.put(json.dumps(e) + "\n")
    def flush(self):
        pass
    def close(self):
        self.owner.lines.put(None)


class FakeProcess:
    pid = 42
    def __init__(self, ids):
        self.ids = ids
        self.messages = []
        self.lines = queue.Queue()
        self.stdin = FakePipe(self)
        self.stdout = self
        self.returncode = None
    def __iter__(self):
        while True:
            line = self.lines.get()
            if line is None:
                return
            yield line
    def poll(self):
        return self.returncode
    def wait(self, timeout):
        self.returncode = 0
        return 0


class WarmTests(unittest.TestCase):
    def test_two_turns_one_process_and_separate_logs(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            proc = FakeProcess(["conversation-A", "conversation-A"])
            launch = Mock(return_value=proc)
            with OwnerAgyWarmSession(ps="pwsh", env={}, root=root, popen=launch) as s:
                a = s.turn("first", root/"one")
                b = s.turn("second", root/"two")
                self.assertEqual(a.response, {"turn": 1})
                self.assertEqual(b.response, {"turn": 2})
                self.assertEqual(a.conversation_id, b.conversation_id)
                self.assertEqual(b.mcp_outcomes, 1)
            self.assertTrue(s.clean_exit)
            self.assertEqual(launch.call_count, 1)
            self.assertEqual(len(proc.messages), 2)
            self.assertIn("--input-format stream-json", launch.call_args.args[0][-1])
            self.assertTrue((root/"two"/"agy-stdout.jsonl").is_file())

    def test_conversation_drift_prevents_replay(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            proc = FakeProcess(["first", "other"])
            with OwnerAgyWarmSession(ps="pwsh", env={}, root=root, popen=Mock(return_value=proc)) as s:
                s.turn("first", root/"one")
                with self.assertRaisesRegex(WarmSessionError, "CONVERSATION_CHANGED"):
                    s.turn("second", root/"two")
                with self.assertRaisesRegex(WarmSessionError, "NOT_READY"):
                    s.turn("third", root/"three")
            self.assertEqual(len(proc.messages), 2)

    def test_metadata_exact_identity_soft_size_and_resolution(self):
        q = MovieQuery("Example", 2026)
        def row(title="Example", year=2026, resolution="1080p", size=8000, seeds=1):
            return {"title":title, "year":year, "resolution":resolution, "size_mb":size, "seeds":seeds}
        result = _metadata({"request_id":"x", "status":"MATCH_FOUND", "candidates":[
            row(title="Other", seeds=9999), row(year=2025, seeds=9999),
            row(size=2000, seeds=90), row(size=7000, seeds=2),
            row(size=9000, seeds=7), row(resolution="2160p", seeds=999)]}, q, "x")
        self.assertEqual([r["seeds"] for r in result["candidates"]], [7,2,90,999])
        self.assertEqual(result["evidence"], "MODEL_REPORTED_METADATA")
        with self.assertRaisesRegex(WarmSessionError, "REQUEST_MISMATCH"):
            _metadata({"request_id":"old"}, q, "x")

    def test_unapproved_source_never_calls_provider(self):
        with patch("owner_g2_discovery.preflight_antigravity") as call:
            with self.assertRaisesRegex(ValueError, "AUTHORITY_REQUIRED"):
                discover_movie_batch(None, [MovieQuery("Example", 2026)], None,
                                     source_url="https://example.org", authorized_source=False)
            call.assert_not_called()

    def test_owner_entrypoint_reuses_browser_lock(self):
        producer = NativeBrowserProducer(profile=Path("fixture"), probe=lambda m: None)
        def execute(*args, **kwargs):
            self.assertTrue(producer._browser_lock.locked())
            return ["fixture"]
        with patch("owner_g2_discovery.discover_movie_batch", side_effect=execute) as call:
            result = producer.discover_movies([MovieQuery("Example", 2026)], Path("cache"),
                                             source_url="https://example.org", authorized_source=True)
            self.assertEqual(result, ["fixture"])
            self.assertEqual(call.call_count, 1)
        self.assertFalse(producer._browser_lock.locked())


if __name__ == "__main__":
    unittest.main()
