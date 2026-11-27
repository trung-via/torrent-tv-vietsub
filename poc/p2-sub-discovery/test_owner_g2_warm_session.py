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

from agy_owner_warm_session import OwnerAgyWarmSession, WarmSessionError, _source_page
from owner_g2_discovery import MovieQuery, _metadata, discover_movie_batch, G2BatchReview, TURN_SECONDS, _selected_metadata, _prompt
from agy_v13_native_producer import NativeBrowserProducer
from owner_session_bridge import poll_private_g2, enqueue_g2_metadata
from owner_g2_submit import submit_private_file


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
            self.assertEqual(decide([dict(missing, year=2025)])["status"],"NO_EXACT_MATCH_REPORTED")
            self.assertEqual(decide([dict(missing, title="Other film")])["status"],"NO_EXACT_MATCH_REPORTED")
            q = replace(q, verified_release_hash="b"*40)
            self.assertEqual(decide([missing])["status"],"NO_EXACT_MATCH_REPORTED")
            self.assertNotIn("b"*40, _prompt(q,"https://example.org","turn"))
            self.assertEqual(decide([exact],observed=[])["status"],"SELECTED_LOCATOR_UNVERIFIED")
            self.assertEqual(decide([exact],status="ACCESS_BLOCKED")["status"],"ACCESS_BLOCKED")
            self.assertIn("Never reject an exact-film release solely", _prompt(q,"https://example.org","turn"))

    def test_selection_private_consumer_publishes_exact_g22_input_once(self):
        from dataclasses import asdict
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            rid="f"*32
            q=MovieQuery("Licensed fixture",2026,select_release=True,media_authorized=True,play=True)
            request={"schema":"TTV-OWNER-G2-SELECTION-V1","request_id":rid,
                     "authorized_source":True,"source_url":"https://example.org/releases","queries":[asdict(q)]}
            enqueue_g2_metadata(owner_root=root,request=request)
            selection={"link":"magnet:?xt=urn:btih:"+"a"*40,"expected_hash":"a"*40,
                       "title":q.title,"source_authorized":True,"media_authorized":True,
                       "release_matched":True,"file_id":None}
            discover=Mock(return_value=[{"status":"SELECTION_READY","owner_request_id":rid,
                                        "query":asdict(q),"selection":selection}])
            def handoff(inbox, request_id):
                self.assertEqual(request_id, rid)
                self.assertEqual(json.loads((inbox/("g2-"+rid+".selected.json")).read_text())["selection"], selection)
                return "LIBRARY_READY"
            consume=Mock(side_effect=handoff)
            args=dict(owner_root=root,cache_root=root/"cache",discover=discover,
                      submit=lambda work:work(),emit=lambda _:None,handoff=consume)
            self.assertEqual(poll_private_g2(**args),1)
            output=root/"inbox"/("g2-"+rid+".selected.json")
            self.assertEqual(json.loads(output.read_text()),{"schema":"TTV-G2-SELECTED-RELEASE-V1",
                             "request_id":rid,"selection":selection,"play":True})
            self.assertEqual(poll_private_g2(**args),0)
            discover.assert_called_once()
            consume.assert_called_once_with(root/"inbox",rid)
            self.assertEqual(json.loads((root/"inbox"/("g2-"+rid+".receipt.json")).read_text())["library_status"],"LIBRARY_READY")

    def test_selection_authority_required_before_provider(self):
        with patch("owner_g2_discovery.preflight_antigravity") as provider:
            with self.assertRaisesRegex(ValueError,"G2_QUERY_INVALID"):
                discover_movie_batch(None,[MovieQuery("Fixture",2026,select_release=True)],None,
                                     source_url="https://example.org",authorized_source=True)
            provider.assert_not_called()

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

    def test_blank_baseline_preserved_and_changed_baseline_holds(self):
        # Full native batch lifecycle with a fake CDP transport and no provider.
        for changed, timeout in ((False, False), (True, False), (False, True), (True, True)):
            with self.subTest(changed=changed, timeout=timeout), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                baseline_id, target_id = "a"*32, "b"*32
                tabs = {baseline_id: "about:blank"}
                source = "https://example.org/"
                commands = []
                def open_cdp(request, timeout):
                    path = request.full_url.split("9555", 1)[1]
                    commands.append(path)
                    if path == "/json/version":
                        obj = {"Browser": "Chrome/1",
                               "webSocketDebuggerUrl": "ws://127.0.0.1:9555/devtools/browser/fixture"}
                    elif path == "/json/list":
                        obj = [{"type": "page", "id": i, "url": url} for i, url in tabs.items()]
                    elif path == "/json/new?" + source:
                        tabs[target_id] = source
                        obj = {"id": target_id, "url": source}
                    elif path == "/json/close/" + target_id:
                        del tabs[target_id]
                        obj = {}
                    else:
                        raise AssertionError(path)
                    return io.BytesIO(json.dumps(obj).encode())
                session = Mock(started=True, clean_exit=True)
                session.__enter__ = Mock(return_value=session)
                session.__exit__ = Mock(return_value=False)
                budgets = []
                def turn(prompt, run, **kwargs):
                    run.mkdir()
                    budgets.append(session.timeout)
                    if timeout and len(budgets) == 2:
                        if changed:
                            tabs[baseline_id] = "https://other.example/"
                        raise WarmSessionError("AGY_STREAM_TURN_TIMEOUT")
                    if changed and not timeout:
                        tabs[baseline_id] = "https://other.example/"
                    return SimpleNamespace(response={}, first_mcp_ms=1, final_ms=2,
                                           mcp_outcomes=1, mcp_errors=0)
                session.turn.side_effect = turn
                with patch("owner_g2_discovery.os", SimpleNamespace(name="nt", environ={}, fsync=os.fsync)), \
                     patch("owner_g2_discovery.shutil.which", return_value="pwsh"), \
                     patch("owner_g2_discovery.preflight_antigravity", return_value="agy"), \
                     patch("owner_g2_discovery._validated_antigravity_alias", return_value="fixture"), \
                     patch("owner_g2_discovery.build_opener", return_value=SimpleNamespace(open=open_cdp)), \
                     patch("agy_v13_native_producer._ensure_browser_listener"), \
                     patch("agy_v13_native_producer._session_settings", return_value=root/"settings.json"), \
                     patch("owner_g2_discovery._metadata", return_value={"status":"NO_MATCH","candidates":[]}):
                    queries = [MovieQuery("Example", 2026)] * (2 if timeout else 1)
                    args = (root, queries, root/"cache")
                    rid = "f"*32
                    kwargs = dict(source_url=source, authorized_source=True, owner_request_id=rid,
                                  session_factory=Mock(return_value=session))
                    if changed and not timeout:
                        with self.assertRaises(G2BatchReview) as ctx:
                            discover_movie_batch(*args, **kwargs)
                        self.assertEqual(ctx.exception.reason, "G2_TASK_SOURCE_CHANGED")
                        self.assertEqual(ctx.exception.cleanup_reason, "G2_BROWSER_EFFECT_REVIEW_REQUIRED")
                    elif timeout:
                        with self.assertRaises(G2BatchReview) as ctx:
                            discover_movie_batch(*args, **kwargs)
                        self.assertEqual(ctx.exception.reason, "AGY_STREAM_TURN_TIMEOUT")
                        self.assertEqual(len(ctx.exception.rows), 1)
                        self.assertEqual(ctx.exception.browser_restored, not changed)
                        self.assertEqual(ctx.exception.cleanup_reason,
                                         "G2_BROWSER_EFFECT_REVIEW_REQUIRED" if changed else None)
                        self.assertEqual(budgets, [TURN_SECONDS, TURN_SECONDS])
                        saved = root/"cache"/".native-v13"/("g2-"+rid)/"checkpoint.json"
                        self.assertEqual(json.loads(saved.read_text())["owner_request_id"], rid)
                        self.assertEqual(json.loads((saved.parent/"request.json").read_text())["owner_request_id"], rid)
                        self.assertEqual(len(json.loads(saved.read_text())["results"]), 1)
                        self.assertEqual(json.loads((saved.parent/"terminal.json").read_text())["reason"],
                                         "AGY_STREAM_TURN_TIMEOUT")
                        self.assertEqual(json.loads((saved.parent/"terminal.json").read_text())["cleanup_reason"],
                                         "G2_BROWSER_EFFECT_REVIEW_REQUIRED" if changed else None)
                    else:
                        rows = discover_movie_batch(*args, **kwargs)
                        self.assertEqual(len(rows), 1)
                    with self.assertRaisesRegex(WarmSessionError, "PRIOR_BATCH_REVIEW_REQUIRED"):
                        discover_movie_batch(*args, **kwargs)
                    self.assertEqual(session.turn.call_count, 2 if timeout else 1)
                pending = root/"cache"/".native-v13"/"browser.pending"
                self.assertEqual(pending.exists(), changed)
                self.assertEqual("/json/close/"+target_id in commands, not changed)
                if not changed:
                    self.assertEqual(tabs, {baseline_id:"about:blank"})
                    self.assertEqual(len(list((root/"cache"/".native-v13").glob("g2-*/completed.json"))), 0 if timeout else 1)

    def test_g2_batch_limit_before_provider(self):
        with patch("owner_g2_discovery.preflight_antigravity") as call:
            with self.assertRaisesRegex(ValueError, "BATCH_LIMIT"):
                discover_movie_batch(None, (MovieQuery("Example", 2026) for _ in range(3)),
                                     None, source_url="https://example.org", authorized_source=True)
            call.assert_not_called()

    def test_private_g2_request_consumed_once(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            inbox = root/"inbox"
            inbox.mkdir()
            rid = "a"*32
            payload = {"schema": "TTV-OWNER-G2-METADATA-V1", "request_id": rid,
                       "authorized_source": True, "source_url": "https://example.org/",
                       "queries": [{"title": "Example", "year": 2026}]}
            event = inbox/("g2-"+rid+".json")
            event.write_text(json.dumps(payload), encoding="utf-8")
            discover = Mock(return_value=[{"status": "NO_MATCH", "candidates": []}])
            args = dict(owner_root=root, cache_root=root/"cache", discover=discover,
                        submit=lambda work: work(), emit=lambda _: None)
            self.assertEqual(poll_private_g2(**args), 1)
            self.assertEqual(poll_private_g2(**args), 0)
            discover.assert_called_once_with((MovieQuery("Example", 2026),), root/"cache",
                                              source_url="https://example.org/", authorized_source=True, owner_request_id=rid)
            receipt = json.loads((inbox/("g2-"+rid+".receipt.json")).read_text("utf-8"))
            self.assertEqual(receipt["status"], "COMPLETE")
            self.assertTrue((inbox/("g2-"+rid+".claim")).is_file())

    def test_private_g2_request_does_not_replay_unknown_effect(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            inbox = root/"inbox"
            inbox.mkdir()
            rid = "b"*32
            (inbox/("g2-"+rid+".json")).write_text(json.dumps({
                "schema": "TTV-OWNER-G2-METADATA-V1", "request_id": rid,
                "source_url": "https://example.org/", "authorized_source": True,
                "queries": [{"title": "Example", "year": 2026}]}), encoding="utf-8")
            discover = Mock(side_effect=WarmSessionError("UNKNOWN"))
            args = dict(owner_root=root, cache_root=root/"cache", discover=discover,
                        submit=lambda work: work(), emit=lambda _: None)
            self.assertEqual(poll_private_g2(**args), 1)
            self.assertEqual(poll_private_g2(**args), 0)
            self.assertEqual(discover.call_count, 1)
            self.assertEqual(json.loads((inbox/("g2-"+rid+".receipt.json")).read_text("utf-8"))["status"],
                             "REVIEW_REQUIRED")

    def test_private_g2_partial_receipt_no_replay(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            rid = "e"*32
            enqueue_g2_metadata(owner_root=root, request={
                "schema": "TTV-OWNER-G2-METADATA-V1", "request_id": rid,
                "source_url": "https://example.org/", "authorized_source": True,
                "queries": [{"title": "Example", "year": 2026}]*2})
            row = {"status": "NO_MATCH", "candidates": [], "turn_index": 0}
            discover = Mock(side_effect=G2BatchReview(
                "AGY_STREAM_TURN_TIMEOUT", [row], browser_restored=False,
                cleanup_reason="G2_BROWSER_EFFECT_REVIEW_REQUIRED"))
            args = dict(owner_root=root, cache_root=root/"cache", discover=discover,
                        submit=lambda work: work(), emit=lambda _: None)
            self.assertEqual(poll_private_g2(**args), 1)
            self.assertEqual(poll_private_g2(**args), 0)
            discover.assert_called_once()
            receipt = json.loads((root/"inbox"/("g2-"+rid+".receipt.json")).read_text())
            self.assertEqual(receipt["status"], "REVIEW_REQUIRED")
            self.assertEqual(receipt["reason"], "AGY_STREAM_TURN_TIMEOUT")
            self.assertEqual(receipt["results"], [row])
            self.assertFalse(receipt["browser_restored"])
            self.assertEqual(receipt["cleanup_reason"], "G2_BROWSER_EFFECT_REVIEW_REQUIRED")

    def test_private_writer_reuses_identity_and_consumer_receipt(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            rid = "c"*32
            payload = {"schema": "TTV-OWNER-G2-METADATA-V1", "request_id": rid,
                       "authorized_source": True, "source_url": "https://example.org/",
                       "queries": [{"title": "Example", "year": 2026}]}
            input_file = root/"request.json"
            input_file.write_text(json.dumps(payload), encoding="utf-8")
            self.assertEqual(submit_private_file(root, input_file), rid)
            inbox = root/"inbox"
            event = inbox/("g2-"+rid+".json")
            original = event.read_bytes()
            self.assertEqual(submit_private_file(root, input_file), rid)
            self.assertEqual(event.read_bytes(), original)
            discover = Mock(return_value=[{"status": "NO_MATCH", "candidates": []}])
            args = dict(owner_root=root, cache_root=root/"cache", discover=discover,
                        submit=lambda work: work(), emit=lambda _: None)
            self.assertEqual(poll_private_g2(**args), 1)
            self.assertEqual(submit_private_file(root, input_file), rid)
            self.assertEqual(poll_private_g2(**args), 0)
            self.assertEqual(discover.call_count, 1)
            changed = dict(payload, queries=[{"title": "Other", "year": 2026}])
            with self.assertRaisesRegex(ValueError, "ID_CONFLICT"):
                enqueue_g2_metadata(owner_root=root, request=changed)
            self.assertEqual(event.read_bytes(), original)
            self.assertFalse(list(inbox.glob("*.tmp")))

    def test_private_writer_refuses_unapproved_and_orphan_claim(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            rid = "d"*32
            payload = {"schema": "TTV-OWNER-G2-METADATA-V1", "request_id": rid,
                       "authorized_source": False, "source_url": "https://example.org/",
                       "queries": [{"title": "Example", "year": 2026}]}
            with self.assertRaisesRegex(ValueError, "REQUEST_INVALID"):
                enqueue_g2_metadata(owner_root=root, request=payload)
            self.assertFalse((root/"inbox").exists())
            payload["authorized_source"] = True
            inbox = root/"inbox"
            inbox.mkdir()
            (inbox/("g2-"+rid+".claim")).write_text("CLAIMED", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "PRIOR_EFFECT_REVIEW"):
                enqueue_g2_metadata(owner_root=root, request=payload)
            self.assertFalse((inbox/("g2-"+rid+".json")).exists())


if __name__ == "__main__":
    unittest.main()
