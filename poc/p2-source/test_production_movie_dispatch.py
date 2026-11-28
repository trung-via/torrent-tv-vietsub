"""Offline contract check for the new typed HostOps dispatch. No host or provider."""
from pathlib import Path
import re
import os
import sys
import json
import hashlib
import tempfile
import subprocess
from types import SimpleNamespace
from unittest.mock import patch
import unittest

ROOT=Path(__file__).resolve().parents[2]
WORKFLOW=ROOT/".github/workflows/torrent-tv-hostops.yml"
DOC=ROOT/"docs/PRODUCTION_MOVIE_DISPATCH.md"

class ProductionMovieDispatchTests(unittest.TestCase):
    def test_fixed_dispatch_and_existing_hostops(self):
        source=WORKFLOW.read_text(encoding="utf-8")
        doc=DOC.read_text(encoding="utf-8")
        pin=re.search(r"/tv-hostops movie ([0-9a-f]{40}) search",doc).group(1)
        self.assertIn("$jobId = 'production-movie'",source)
        self.assertIn("$sha -cne '"+pin+"'",source)
        self.assertIn("branch head differs from approved exact SHA",source)
        self.assertIn("use typed movie command",source)
        self.assertIn("github.event.comment.user.login == 'trung-via'",source)
        self.assertIn("github.event.issue.number == 196",source)
        self.assertIn("HOSTOPS_PINNED_JOB_PASS",source)
        self.assertIn("search|play",source)
        self.assertIn("[0-9]{4}",source)
        self.assertIn("HostOps dispatcher",doc)

class ProductionMovieCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get("TTV_PRODUCTION_MOVIE_SOURCE")
        if not source:
            raise unittest.SkipTest("Exact candidate checkout supplied by hosted CI")
        cls.source = Path(source)
        cls.operation = cls.source / "hostops/laptop-ops/operations/production-movie.ps1"
        cls.raw = subprocess.check_output(["git", "-C", str(cls.source), "show",
                                           "HEAD:hostops/laptop-ops/operations/production-movie.ps1"])
        source_lines = cls.raw.decode("utf-8").splitlines()
        start = source_lines.index("$py=@\x27") + 1
        end = source_lines.index("\x27@", start)
        cls.python = "\n".join(source_lines[start:end])
        cls.definitions = "\n".join(source_lines[start:source_lines.index("try: print(main())", start)])

    def test_pinned_operation_and_dispatcher_contract(self):
        manifest = json.loads((self.source / "hostops/laptop-ops/manifests/current.json").read_text())
        self.assertEqual(hashlib.sha256(self.raw).hexdigest(), manifest["script_sha256"])
        dispatcher = (self.source / "hostops/jobs/owner-laptop-ops-dispatch.ps1").read_text()
        self.assertNotIn("PRODUCTION_MOVIE_MEDIA_AUTHORITY_UNVERIFIED", dispatcher)
        self.assertIn("AddSeconds(30)", dispatcher)
        self.assertIn("HOSTOPS_OWNER_OPS_UNRESOLVED_PREVIOUS_REQUEST", dispatcher)
        self.assertIn("PRODUCTION_MOVIE_PRIOR_DISPATCH_RECONCILE", dispatcher)
        self.assertIn("HOSTOPS_OWNER_OPS_TASK_IDENTITY_DRIFT", dispatcher)

    def execute_mock(self, *, title="Sintel", year=2010, mode="play",
                     status="SELECTION_READY", selected_hash="a"*40, library_hash=None):
        nonce = "b"*32
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            run = root / "run"
            run.mkdir()
            spool = root / "spool"
            inbox = root / "OwnerBridge" / "inbox"
            inbox.mkdir(parents=True)
            (inbox / ("g2-"+nonce+".receipt.json")).touch()
            ns = {}
            with patch.object(sys, "argv", ["embedded",str(root),str(run),str(spool),nonce]):
                exec(compile(self.definitions, str(self.operation), "exec"), ns)
            request = {"schema":"TTV-PRODUCTION-MOVIE-V1","request_id":nonce,
                       "mode":mode,"year":year,"title":title}
            row = {"owner_request_id":nonce,"status":status}
            if status == "SELECTION_READY":
                row["selection"] = {"title":title,"source_authorized":True,
                                    "media_authorized":True,"release_matched":True,
                                    "expected_hash":selected_hash}
            receipt = {"schema":"TTV-OWNER-G2-RECEIPT-V1","request_id":nonce,
                       "status":"COMPLETE","results":[row],
                       "selection_published":True,"library_status":"LIBRARY_READY"}
            library = {"schema":"TTV-G2-LIBRARY-RECEIPT-V1","request_id":nonce,
                       "status":"LIBRARY_READY","play":True,"auto_vietsub":True,
                       "torrent_hash":library_hash or selected_hash,"file_id":0}
            docs = {"movie-"+nonce+".json":request,
                    "g2-"+nonce+".receipt.json":receipt,
                    "g2-"+nonce+".library.json":library}
            ns["read_doc"] = lambda p: docs[p.name]
            calls = []
            ns["subprocess"] = SimpleNamespace(run=lambda *args, **kw: (
                calls.append(args), SimpleNamespace(returncode=0,
                stdout=b"OWNER_G2_SUBMIT_ACCEPTED_NOT_RESULT"))[1])
            try:
                result = ns["main"]()
            except ns["Hold"] as exc:
                result = "HOLD_"+str(exc)
            payload = json.loads((run / "private-request.json").read_text())
            self.assertEqual(len(calls), 1)
            return result, payload

    def test_nonfixture_catalog_title_uses_selected_hash(self):
        result, payload = self.execute_mock()
        self.assertEqual(result, "PRODUCTION_MOVIE_LIBRARY_READY")
        self.assertEqual(payload["source_url"], "https://webtorrent.io/free-torrents")
        self.assertEqual(payload["queries"][0]["title"], "Sintel")
        self.assertNotIn("verified_release_hash", payload["queries"][0])

    def test_catalog_no_match_never_launches(self):
        result, payload = self.execute_mock(status="NO_MATCH")
        self.assertEqual(result, "PRODUCTION_MOVIE_SELECTION_NO_MATCH")
        self.assertTrue(payload["queries"][0]["play"])

    def test_library_hash_mismatch_holds(self):
        result, _ = self.execute_mock(library_hash="c"*40)
        self.assertEqual(result, "HOLD_LIBRARY_BIND")

    def test_known_fixture_hash_mismatch_holds(self):
        result, _ = self.execute_mock(title="Big Buck Bunny", year=2008)
        self.assertEqual(result, "HOLD_SELECTION_HASH_BIND")

    def test_metadata_only_does_not_request_play(self):
        result, payload = self.execute_mock(mode="search", status="MATCH_FOUND")
        self.assertEqual(result, "PRODUCTION_MOVIE_METADATA_MATCH_FOUND")
        self.assertFalse(payload["queries"][0]["select_release"])
        self.assertFalse(payload["queries"][0]["play"])

if __name__=="__main__":unittest.main()
