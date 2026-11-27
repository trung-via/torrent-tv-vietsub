import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import report_bridge as rb

class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        p = Path(self.tmp.name)
        self.source = "a" * 40
        self.nonce = "b" * 32
        self.root = p / "runs"
        self.run = self.root / ("bt18-hydrogen-opensubtitles-" + self.nonce)
        self.run.mkdir(parents=True)
        self.spool = p / "spool"
        (self.spool / "History").mkdir(parents=True)
        self.receipt = self.spool / "History" / ("receipt-" + self.nonce + ".json")
        self.put(self.receipt, {"schema":"TTV-LAPTOP-HOSTOPS-RECEIPT-V1",
                               "operation":rb.OPERATION,"source_commit":self.source,
                               "nonce":self.nonce,"result":"SUCCESS"})
        self.inbox = p / "inbox"
        self.inbox.mkdir()
        self.handoff = {"source":self.source,"original_source":self.source,
                        "nonce":self.nonce,"mode":"LIVE"}
        self.put(self.run / "BRAIN_HANDOFF.json", self.handoff)
        self.put(self.run / "BRAIN_RESULT.json", {"handoff":self.handoff})
        self.subtitle = b"1\n00:00:01,000 --> 00:00:02,000\nSynthetic fixture\n"
        (self.run / "browser-downloads").mkdir()
        self.artifact = self.run / "browser-downloads" / "fixture.srt"
        self.artifact.write_bytes(self.subtitle)
        self.report = {"source_commit":self.source,"artifacts":[
            {"filename":"fixture.srt","copied_to_job":True,"bytes":len(self.subtitle),
             "sha256":hashlib.sha256(self.subtitle).hexdigest()}]}
        self.put(self.run / "BRAIN_TEACHER_REPORT.json", self.report)
        self.put(self.run / "stream-timing.json", {"elapsed":108})
        self.put(self.run / "BRAIN_FILTER_QA.json", {"accepted":False})
        (self.run / "BRAIN_TEACHER_FULL_RESPONSE.md").write_text("synthetic report")
        (self.run / "session-settings.json").write_text("excluded fixture")
    def put(self, path, data):
        path.write_text(json.dumps(data), encoding="utf-8")
    def export(self):
        return rb.export(self.root, self.spool, self.inbox, self.source, self.nonce)
    def verify(self, r):
        return rb.verify(self.inbox / r["zip"],
                         self.inbox / r["zip"].replace(".zip",".ready.json"),
                         self.source, self.nonce)
    def test_round_trip_idempotency_and_no_config(self):
        r = self.export()
        self.assertEqual(r, self.export())
        self.assertEqual(self.verify(r)["state"], "BRAIN_BUNDLE_VERIFIED")
        self.assertEqual(r["file_count"], 7)
        import zipfile
        with zipfile.ZipFile(self.inbox / r["zip"]) as z:
            self.assertNotIn("session-settings.json", z.namelist())
    def test_bad_receipt(self):
        self.receipt.unlink()
        with self.assertRaisesRegex(ValueError, "RECEIPT_MISSING"):
            self.export()
    def test_wrong_report_source(self):
        self.report["source_commit"] = "c"*40
        self.put(self.run / "BRAIN_TEACHER_REPORT.json", self.report)
        with self.assertRaisesRegex(ValueError, "IDENTITY"):
            self.export()
    def test_changed_artifact(self):
        self.artifact.write_bytes(b"wrong")
        with self.assertRaisesRegex(ValueError, "ARTIFACT_HASH"):
            self.export()
    def test_corrupt_zip(self):
        r = self.export()
        p = self.inbox / r["zip"]
        p.write_bytes(p.read_bytes() + b"modified")
        with self.assertRaisesRegex(ValueError, "BUNDLE_ID_OR_HASH"):
            self.verify(r)
    def test_partial_sync(self):
        r = self.export()
        (self.inbox / r["zip"]).unlink()
        with self.assertRaises(FileNotFoundError):
            self.verify(r)
    def test_missing_required_report(self):
        (self.run / "BRAIN_FILTER_QA.json").unlink()
        with self.assertRaises(FileNotFoundError):
            self.export()
    def test_conflicting_export(self):
        self.export()
        self.put(self.run / "stream-timing.json", {"elapsed":109})
        with self.assertRaisesRegex(ValueError, "EXISTING_OUTPUT_CONFLICT"):
            self.export()

if __name__ == "__main__":
    unittest.main()
