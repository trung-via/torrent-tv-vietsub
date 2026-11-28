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
from threading import Lock
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'p2-sub-discovery'))
from owner_movie_handoff import publish_library_receipt
from agy_owner_warm_session import OwnerAgyWarmSession, WarmSessionError, _source_page
from owner_g2_discovery import MovieQuery, _metadata, discover_movie_batch, G2BatchReview, TURN_SECONDS, _selected_metadata, _prompt
from owner_g2_inbox import poll_private_g2, enqueue_g2_metadata, bind_owner_g2, poll_owner_g2_idle
from owner_g2_submit import submit_private_file


class OwnerIntegrationTests(unittest.TestCase):

    def test_warm_session_denial_evidence_and_no_replay(self):
        import time
        from agy_owner_warm_session import warm_reason
        blocked = "AGY_STREAM_ACCESS_BLOCKED"
        unknown = "AGY_STREAM_ACCESS_UNCONFIRMED"
        # Existing source-bound evaluate_script trace format: JSON data rows.
        # Only an explicitly typed benign content field may contain a keyword.
        data = [{"title": "A documentary about captcha", "year": 2026,
                 "resolution": "1080p", "size_mb": 8000, "seeds": 9,
                 "codec": "H264"}]
        cases = (
            ("take_snapshot", "Title: Just a moment...", 3, False, blocked),
            ("take_snapshot", "Title: Just a moment…", 3, False, blocked),
            ("take_snapshot", "Title: Access denied", 3, False, blocked),
            ("take_snapshot", "Title: Access denied", 4, False, unknown),
            ("evaluate_script", "Article mentions captcha and access denied", 3, False, unknown),
            ("evaluate_script", "Ordinary page content", 3, False, None),
            ("evaluate_script", json.dumps(data), 3, False, None),
            ("evaluate_script", json.dumps(data), 4, False, unknown),
            ("evaluate_script", json.dumps(data), 3, True, unknown),
            ("take_snapshot", json.dumps(data), 3, False, unknown),
            ("evaluate_script", json.dumps({"title": "Just a moment", "rows": data}), 3, False, unknown),
            ("evaluate_script", json.dumps([dict(data[0], challenge=True)]), 3, False, unknown),
            ("evaluate_script", json.dumps([dict(data[0], title="Access denied")]), 3, False, unknown),
            ("evaluate_script", json.dumps([dict(data[0], year="unknown")]), 3, False, unknown),
            ("evaluate_script", json.dumps(data) + "\nVerify you are human", 3, False, unknown),
        )
        for tool_name, output, page, error, expected in cases:
            with self.subTest(tool=tool_name, output=output, page=page, error=error), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                session = OwnerAgyWarmSession(ps="unused", env={}, root=root)
                session.process = SimpleNamespace(poll=lambda: None, stdin=io.StringIO())
                def tool(name, output, page=None, error=False):
                    params = {"ToolName": name, "ServerName": "ttv-browser"}
                    if page is not None:
                        params["pageId"] = page
                    info = {"parameters": params, "output": output}
                    if error:
                        info["error"] = True
                    return {"step_update": {"tool_name": "call_mcp_tool", "tool_info": info}}
                for event in (
                    tool("list_pages", "3: https://example.org/"),
                    tool(tool_name, output, page, error),
                    {"event": "result", "result": {
                        "conversation_id": "fixture", "response": "{}"}},
                ):
                    session._queue.put((time.monotonic(), json.dumps(event) + "\n"))
                if expected:
                    with self.assertRaises(WarmSessionError) as failure:
                        session.turn("fixture", root/"turn", source_host="example.org")
                    self.assertEqual(warm_reason(failure.exception), expected)
                    with self.assertRaisesRegex(WarmSessionError, "AGY_STREAM_NOT_READY"):
                        session.turn("fixture", root/"retry", source_host="example.org")
                    self.assertEqual(len(session.process.stdin.getvalue().splitlines()), 1)
                else:
                    self.assertEqual(session.turn("fixture", root/"turn",
                                                  source_host="example.org").response, {})
                    self.assertEqual(len(session.process.stdin.getvalue().splitlines()), 1)


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

    def test_complete_selection_survives_cleanup_hold_without_provider_replay(self):
        from dataclasses import asdict
        for reason, valid in (("G2_BROWSER_EFFECT_REVIEW_REQUIRED", True),
                              ("AGY_STREAM_TURN_TIMEOUT", False)):
            with self.subTest(reason=reason), tempfile.TemporaryDirectory() as d:
                root = Path(d)
                rid = "f"*32
                q = MovieQuery("Licensed fixture", 2026, select_release=True,
                               media_authorized=True, play=True)
                request = {"schema":"TTV-OWNER-G2-SELECTION-V1","request_id":rid,
                           "authorized_source":True,"source_url":"https://example.org/releases",
                           "queries":[asdict(q)]}
                enqueue_g2_metadata(owner_root=root, request=request)
                selection = {"link":"magnet:?xt=urn:btih:"+"a"*40,"expected_hash":"a"*40,
                             "title":q.title,"source_authorized":True,"media_authorized":True,
                             "release_matched":True,"file_id":None}
                row = {"status":"SELECTION_READY","owner_request_id":rid,
                       "query":asdict(q),"selection":selection}
                marker = root/"cache"/".native-v13"/"browser.pending"
                marker.parent.mkdir(parents=True)
                marker.write_text("g2-"+rid)
                discover = Mock(side_effect=G2BatchReview(
                    reason, [row], browser_restored=False,
                    cleanup_reason="G2_BROWSER_EFFECT_REVIEW_REQUIRED"))
                consume = Mock(return_value="LIBRARY_READY")
                args = dict(owner_root=root,cache_root=root/"cache",discover=discover,
                            submit=lambda work:work(),emit=lambda _:None,handoff=consume)
                self.assertEqual(poll_private_g2(**args), 1)
                self.assertEqual(poll_private_g2(**args), 0)
                discover.assert_called_once()
                receipt = json.loads((root/"inbox"/("g2-"+rid+".receipt.json")).read_text())
                self.assertFalse(receipt["browser_restored"])
                self.assertEqual(receipt["cleanup_reason"], "G2_BROWSER_EFFECT_REVIEW_REQUIRED")
                self.assertEqual(marker.read_text(), "g2-"+rid)
                if valid:
                    consume.assert_called_once_with(root/"inbox", rid)
                    self.assertEqual(receipt["status"], "COMPLETE")
                    self.assertEqual(receipt["library_status"], "LIBRARY_READY")
                    self.assertTrue(receipt["selection_published"])
                else:
                    consume.assert_not_called()
                    self.assertEqual(receipt["status"], "REVIEW_REQUIRED")
                    self.assertFalse((root/"inbox"/("g2-"+rid+".selected.json")).exists())

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
                     patch("owner_g2_support.preflight_antigravity", return_value="agy"), \
                     patch("owner_g2_support._validated_antigravity_alias", return_value="fixture"), \
                     patch("owner_g2_discovery.build_opener", return_value=SimpleNamespace(open=open_cdp)), \
                     patch("owner_g2_support._ensure_browser_listener"), \
                     patch("owner_g2_support._session_settings", return_value=root/"settings.json"), \
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


    def test_existing_owner_lock_priority_and_real_handoff_contract(self):
        from dataclasses import asdict
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            outbox=root/"Receipts"
            outbox.mkdir()
            rid="1"*32
            h="a"*40
            q=MovieQuery("Licensed fixture",2026,select_release=True,media_authorized=True,play=True)
            enqueue_g2_metadata(owner_root=root,request={
                "schema":"TTV-OWNER-G2-CONCIERGE-V1","request_id":rid,
                "authorized_source":True,"source_url":"https://example.org","queries":[asdict(q)]})
            row={"status":"SELECTION_READY","owner_request_id":rid,"query":asdict(q),
                 "selection":{"link":"magnet:?xt=urn:btih:"+h,"expected_hash":h,"title":q.title,
                  "source_authorized":True,"media_authorized":True,"release_matched":True,"file_id":None}}
            runner=SimpleNamespace(profile=root,_browser_lock=Lock(),_g1_pending=lambda:False)
            factory=lambda flow:flow
            def discover(*args,**kwargs):
                self.assertFalse(runner._browser_lock.locked())
                self.assertEqual(args[0],root.parent/"CDP9556MovieProfile")
                self.assertEqual(args[1],(q,))
                self.assertEqual(args[2],root/"cache"/"movie-discovery")
                self.assertEqual(kwargs["browser_port"],9556)
                self.assertEqual(kwargs["owner_request_id"],rid)
                return [row]
            post=Mock(side_effect=[[],[],{"hash":h},[{"hash":h}],
                                  {"hash":h,"file_stats":[{"id":7,"path":"fixture.mp4"}]}])
            def handoff(inbox,request_id):
                return publish_library_receipt(inbox,request_id,post=post,outbox=outbox)
            args=dict(factory=factory,owner_root=root,cache_root=root/"cache",
                      submit=lambda work:work(),handoff=handoff,emit=lambda _:None)
            with patch("owner_g2_discovery.discover_movie_batch",side_effect=discover) as call:
                bind_owner_g2(factory,runner)
                self.assertEqual(poll_owner_g2_idle(active={object()},**args),0)
                call.assert_not_called()
                self.assertEqual(poll_owner_g2_idle(active=set(),**args),1)
                self.assertEqual(poll_owner_g2_idle(active=set(),**args),0)
                call.assert_called_once()
            self.assertFalse(runner._browser_lock.locked())
            receipt=json.loads((outbox/("g2-"+rid+".library.json")).read_text())
            self.assertEqual((receipt["request_id"],receipt["torrent_hash"],receipt["file_id"],receipt["play"]),(rid,h,7,True))
            self.assertEqual(sum(c.args[0]["action"]=="add" for c in post.call_args_list),1)
            self.assertIs(receipt["auto_vietsub"],True)

    def test_concierge_cannot_be_search_only(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            with self.assertRaisesRegex(ValueError,"MODE_MISMATCH"):
                enqueue_g2_metadata(owner_root=root, request={
                    "schema":"TTV-OWNER-G2-CONCIERGE-V1","request_id":"2"*32,
                    "authorized_source":True,"source_url":"https://example.org",
                    "queries":[{"title":"Fixture","year":2026,"select_release":True,
                                "media_authorized":True,"play":False}]})
            self.assertFalse((root/"inbox").exists())

if __name__ == "__main__":
    unittest.main()
