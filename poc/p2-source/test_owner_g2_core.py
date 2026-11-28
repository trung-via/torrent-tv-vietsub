"""Synthetic tests only: no provider, browser, network, TV or Windows side effects."""
import io
import os
from types import SimpleNamespace
import json
from pathlib import Path
import queue
import tempfile
import unittest
from unittest.mock import patch, Mock

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'p2-sub-discovery'))

from agy_owner_warm_session import OwnerAgyWarmSession, WarmSessionError, _source_page
from owner_g2_discovery import MovieQuery, _metadata, discover_movie_batch, G2BatchReview, TURN_SECONDS, _selected_metadata, _prompt


class FakePipe:
    def __init__(self, owner):
        self.owner = owner
    def write(self, line):
        msg = json.loads(line)
        self.owner.messages.append(msg)
        n = len(self.owner.messages)
        for e in (self.owner.events if self.owner.events is not None else [
            {"event": "step_update", "step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"parameters": {"ToolName": "evaluate_script", "ServerName": "ttv-browser"}}}},
            {"event": "step_update", "step_update": {"tool_name": "call_mcp_tool",
                "tool_info": {"output": "fixture metadata"}}},
            {"event": "result", "result": {
                "conversation_id": self.owner.ids[n-1],
                "response": json.dumps({"turn": n})}},
        ]):
            self.owner.lines.put(json.dumps(e) + "\n")
    def flush(self):
        pass
    def close(self):
        self.owner.lines.put(None)


class FakeProcess:
    pid = 42
    def __init__(self, ids, events=None):
        self.events = events
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
                terminal = json.loads((root/"two"/"turn-terminal.json").read_text())
                self.assertEqual(terminal["reason"], "AGY_STREAM_CONVERSATION_CHANGED")
                with self.assertRaisesRegex(WarmSessionError, "NOT_READY"):
                    s.turn("third", root/"three")
            self.assertEqual(len(proc.messages), 2)

    def test_authorized_selection_is_exact_top_release_and_observed_locator(self):
        with tempfile.TemporaryDirectory() as d:
            trace = Path(d)/"agy-stdout.jsonl"
            q = MovieQuery("Licensed fixture", 2026, select_release=True, media_authorized=True, play=True)
            def event(params=None, output=None):
                info = {"parameters": params} if params else {"output": output}
                return {"step_update": {"tool_name": "call_mcp_tool", "tool_info": info}}
            def row(name, seeds, resolution="1080p", size=8000, h="a", title="Licensed fixture"):
                return {"title":title,"year":2026,"resolution":resolution,
                        "size_mb":size,"seeds":seeds,"release_name":name,
                        "link":"magnet:?xt=urn:btih:"+h*40}
            exact=row("Exact",9,h="a")
            large=row("Large",100,size=20000,h="b")
            lower=row("Lower",900,"720p",h="c")
            higher=row("Higher",999,"2160p",h="d")
            wrong=row("Wrong",9999,h="e",title="Other film")
            unknown=row("Unknown",None,None,None,h="f")
            def decide(rows, observed=None, status="MATCH_FOUND"):
                observed=rows if observed is None else observed
                events=[
                    event({"ToolName":"list_pages","ServerName":"ttv-browser"}),
                    event(output="1: https://example.org/releases"),
                    event({"ToolName":"evaluate_script","ServerName":"ttv-browser","Arguments":{"pageId":1}}),
                    event(output=json.dumps([{"release_name":x["release_name"],"link":x["link"]} for x in observed])),
                ]
                trace.write_text("\n".join(json.dumps(e) for e in events),encoding="utf-8")
                payload={"request_id":"turn","status":status,"candidates":rows,
                         "selected":{"release_name":"Exact","link":exact["link"]}}
                return _selected_metadata(payload,q,"turn","example.org",trace)
            result=decide([exact,large,lower,higher,wrong])
            self.assertEqual(result["status"],"SELECTION_READY")
            self.assertEqual(result["release_name"],"Large")
            self.assertFalse(result["quality_fallback"])
            result=decide([lower,higher,unknown,wrong])
            self.assertEqual(result["release_name"],"Lower")
            self.assertTrue(result["quality_fallback"])
            self.assertEqual(decide([unknown])["release_name"],"Unknown")
            tied=row("Tied.preferred",100,h="1")
            self.assertEqual(decide([large,tied])["release_name"],"Tied.preferred")
            self.assertEqual(decide([exact],status="NO_MATCH")["release_name"],"Exact")
            self.assertEqual(decide([large,exact],observed=[exact])["release_name"],"Exact")
            self.assertEqual(decide([large,lower],observed=[lower])["release_name"],"Lower")
            self.assertEqual(decide([wrong])["status"],"NO_EXACT_MATCH_REPORTED")
            # Native Sintel failure: source lists exact film and locator, year null.
            from dataclasses import replace
            missing = dict(exact, year=None)
            self.assertEqual(decide([missing])["status"],"NO_EXACT_MATCH_REPORTED")
            q = replace(q, verified_release_hash="a"*40)
            accepted = decide([missing])
            self.assertEqual(accepted["status"],"SELECTION_READY")
            self.assertEqual(accepted["identity_evidence"],"TRUSTED_RELEASE_HASH")
            # Native snapshot: exact title and locator in the same bound read,
            # with no release_name/link JSON object.
            def plain(text, page=1, host="example.org"):
                events=[
                    event({"ToolName":"list_pages","ServerName":"ttv-browser"}),
                    event(output="1: https://"+host+"/releases"),
                    event({"ToolName":"take_snapshot","ServerName":"ttv-browser","Arguments":{"pageId":page}}),
                    event(output=text),
                ]
                trace.write_text("\n".join(json.dumps(e) for e in events),encoding="utf-8")
                payload={"request_id":"turn","status":"MATCH_FOUND","candidates":[missing],
                         "selected":{"release_name":"Exact","link":exact["link"]}}
                return _selected_metadata(payload,q,"turn","example.org",trace)
            snapshot="row Exact\n  link "+exact["link"]
            self.assertEqual(plain(snapshot)["status"],"SELECTION_READY")
            self.assertEqual(plain(snapshot,page=2)["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(plain(snapshot,host="other.org")["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(plain("row Exact")["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(plain("row Other\n  link "+exact["link"])["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(plain("row Exact\n  link "+large["link"])["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(decide([dict(missing, year=2025)])["status"],"NO_EXACT_MATCH_REPORTED")
            self.assertEqual(decide([dict(missing, title="Other film")])["status"],"NO_EXACT_MATCH_REPORTED")
            q = replace(q, verified_release_hash="b"*40)
            self.assertEqual(decide([missing])["status"],"NO_EXACT_MATCH_REPORTED")
            self.assertNotIn("b"*40, _prompt(q,"https://example.org","turn"))
            self.assertEqual(decide([exact],observed=[])["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(decide([exact],status="ACCESS_BLOCKED")["status"],"ACCESS_BLOCKED")
            self.assertIn("Never reject an exact-film release solely", _prompt(q,"https://example.org","turn"))

    def test_metadata_exact_identity_soft_size_and_resolution(self):
        q = MovieQuery("Example", 2026)
        def row(title="Example", year=2026, resolution="1080p", size=8000, seeds=1):
            return {"title":title, "year":year, "resolution":resolution, "size_mb":size, "seeds":seeds}
        result = _metadata({"request_id":"x", "status":"MATCH_FOUND", "candidates":[
            row(title="Other", seeds=9999), row(year=2025, seeds=9999),
            row(size=2000, seeds=90), row(size=7000, seeds=2),
            row(size=9000, seeds=7), row(resolution="2160p", seeds=999)]}, q, "x")
        self.assertEqual([r["seeds"] for r in result["candidates"]], [90,7,2,999])
        self.assertEqual(result["evidence"], "MODEL_REPORTED_METADATA")
        with self.assertRaisesRegex(WarmSessionError, "REQUEST_MISMATCH"):
            _metadata({"request_id":"old"}, q, "x")

    def test_native_list_pages_prefix_and_ambiguity(self):
        host = "example.org"
        self.assertEqual(_source_page("1: Other https://other.example/\n2: Movie title - https://example.org/ [selected]", host), 2)
        self.assertEqual(_source_page("2: https://example.org/", host), 2)
        self.assertIsNone(_source_page("2: title https://example.org/\n3: title https://example.org/other", host))
        self.assertIsNone(_source_page("2: https://example.org/ https://other.example/", host))
        self.assertIsNone(_source_page("2: title https://example.org.evil.example/", host))
        self.assertIsNone(_source_page("2: title https://example.org@other.example/", host))
        self.assertIsNone(_source_page("2: title http://example.org/", host))

    def test_source_page_requires_fresh_matching_read(self):
        def outcome(tool, args, output):
            return {"event": "step_update", "step_update": {"tool_name": "call_mcp_tool",
                    "tool_info": {"parameters": {"ToolName": tool, "ServerName": "ttv-browser",
                                                  "Arguments": json.dumps(args)}, "output": output}}}
        for page_id, allowed in ((2, True), (3, False)):
            with self.subTest(page_id=page_id), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                events = [outcome("list_pages", {}, "1: OpenSubtitles https://www.opensubtitles.org/\n2: Movie title https://example.org/"),
                          outcome("evaluate_script", {"pageId": page_id}, "metadata"),
                          {"event": "result", "result": {"conversation_id": "A", "response": "{}"}}]
                proc = FakeProcess(["A"], events=events)
                with OwnerAgyWarmSession(ps="pwsh", env={}, root=root, popen=Mock(return_value=proc)) as session:
                    if allowed:
                        self.assertEqual(session.turn("query", root/"turn", source_host="example.org").mcp_outcomes, 2)
                    else:
                        with self.assertRaisesRegex(WarmSessionError, "SOURCE_PAGE_UNBOUND"):
                            session.turn("query", root/"turn", source_host="example.org")

    def test_authority_and_batch_validation_before_runtime_import(self):
        with self.assertRaisesRegex(ValueError, "AUTHORITY_REQUIRED"):
            discover_movie_batch(None, [MovieQuery("Example", 2026)], None,
                                 source_url="https://example.org", authorized_source=False)
        with self.assertRaisesRegex(ValueError, "G2_QUERY_INVALID"):
            discover_movie_batch(None, [MovieQuery("Example", 2026, select_release=True)], None,
                                 source_url="https://example.org", authorized_source=True)
        with self.assertRaisesRegex(ValueError, "BATCH_LIMIT"):
            discover_movie_batch(None, [MovieQuery("Example", 2026)]*3, None,
                                 source_url="https://example.org", authorized_source=True)
        self.assertEqual(discover_movie_batch(None, [], None,
                         source_url="https://example.org", authorized_source=True), [])

    def test_missing_owner_dependencies_no_browser_or_cache_effect(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with patch("owner_g2_discovery.os", SimpleNamespace(name="nt", environ={})), \
                 patch("owner_g2_discovery.shutil.which", return_value="pwsh"), \
                 patch.dict(sys.modules, {"owner_g2_support": None}):
                with self.assertRaisesRegex(WarmSessionError, "G2_OWNER_RUNTIME_DEPENDENCY_MISSING"):
                    discover_movie_batch(root, [MovieQuery("Example", 2026)], root/"cache",
                                         source_url="https://example.org", authorized_source=True)
            self.assertFalse((root/"cache").exists())

if __name__ == "__main__":
    unittest.main()
