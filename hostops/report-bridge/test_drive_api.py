import unittest
from unittest.mock import patch
from pathlib import Path
import tempfile
import drive_api as api
import report_bridge as rb

class FakeDrive:
    def __init__(self):
        self.objects = {}
        self.calls = []
        self.generations = 0
        self.fail_ready = False
    def check_folder(self, folder):
        if folder != "folder":
            raise api.Hold("DRIVE_FOLDER_UNVERIFIED")
    def ids(self, count):
        self.generations += 1
        return ["zip-id", "ready-id"]
    def checked_bytes(self, id, folder, name, mime, data):
        self.calls.append(id)
        if id in self.objects and self.objects[id] != data:
            raise api.Hold("DRIVE_BYTES_CONFLICT")
        if self.fail_ready and id == "ready-id":
            raise api.Hold("DRIVE_REQUEST_UNKNOWN_EFFECT")
        self.objects[id] = data

class PublishTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.p = Path(self.tmp.name)
        self.source, self.nonce = "a"*40, "b"*32
        self.bundle = self.p / "report.zip"
        self.ready = self.p / "report.ready.json"
        self.bundle.write_bytes(b"synthetic zip")
        self.ready.write_bytes(b"synthetic ready")
        self.drive = FakeDrive()
        self.verify = patch.object(rb, "verify", return_value={"sha256":rb.digest(b"synthetic zip"),"file_count":10})
        self.verify.start()
        self.addCleanup(self.verify.stop)
    def send(self, folder="folder"):
        return api.publish(self.drive, self.p, folder, self.bundle, self.ready, self.source, self.nonce)
    def test_order_and_duplicate(self):
        a = self.send()
        b = self.send()
        self.assertEqual(a,b)
        self.assertEqual(self.drive.calls, ["zip-id","ready-id"]*2)
        self.assertEqual(self.drive.generations,1)
        self.assertEqual(len(self.drive.objects),2)
    def test_partial_ready_failure(self):
        self.drive.fail_ready = True
        with self.assertRaisesRegex(api.Hold,"UNKNOWN_EFFECT"):
            self.send()
        self.assertEqual(set(self.drive.objects),{"zip-id"})
        self.drive.fail_ready = False
        self.assertEqual(self.send()["state"],"API_UPLOAD_VERIFIED")
        self.assertEqual(self.drive.generations,1)
    def test_journal_conflict(self):
        self.send()
        self.ready.write_bytes(b"changed")
        with self.assertRaisesRegex(api.Hold,"JOURNAL_CONFLICT"):
            self.send()
    def test_wrong_folder(self):
        with self.assertRaisesRegex(api.Hold,"FOLDER_UNVERIFIED"):
            self.send("other")
        self.assertEqual(self.drive.calls,[])
    def test_local_hash_changed(self):
        self.bundle.write_bytes(b"changed")
        with self.assertRaisesRegex(api.Hold,"LOCAL_BYTES_CHANGED"):
            self.send()
    def test_size_limit(self):
        with patch.object(api,"MAX_UPLOAD",1):
            with self.assertRaisesRegex(api.Hold,"MULTIPART_LIMIT"):
                self.send()
        self.assertEqual(self.drive.calls,[])
    def test_conflicting_remote(self):
        self.send()
        self.drive.objects["zip-id"] = b"conflict"
        with self.assertRaisesRegex(api.Hold,"BYTES_CONFLICT"):
            self.send()
        self.assertEqual(self.drive.calls[-1],"zip-id")

if __name__ == "__main__":
    unittest.main()
