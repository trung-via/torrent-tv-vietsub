import json
import unittest
from flow3_ingress import build_request, PREFIX


class Flow3IngressTests(unittest.TestCase):
    def command(self, **changes):
        p = {"title": "Authorized fixture", "year": 2026,
             "source_url": "https://example.org/"}
        p.update(changes)
        return PREFIX + json.dumps(p)

    def test_search_and_play_use_existing_consumer(self):
        from pathlib import Path
        import sys
        sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "p2-sub-discovery"))
        from owner_g2_inbox import _g2_request
        for mode in ("search", "play"):
            p = build_request(self.command(mode=mode, media_authorized=mode=="play"), "123")
            q = _g2_request(p, p["request_id"])[0]
            self.assertEqual(q.title, "Authorized fixture")
            self.assertEqual(q.play, mode=="play")
            self.assertEqual(q.select_release, mode=="play")
            self.assertEqual(q.resolution, "1080p")

    def test_same_comment_same_identity(self):
        c = self.command()
        self.assertEqual(build_request(c,"123"),build_request(c,"123"))
        self.assertNotEqual(build_request(c,"123")["request_id"],build_request(c,"124")["request_id"])

    def test_no_implicit_media_authority(self):
        for c in (self.command(mode="play"),self.command(media_authorized=True),
                  self.command(mode="play", media_authorized="true")):
            with self.assertRaises(ValueError):
                build_request(c,"123")

    def test_private_or_invalid_inputs_rejected(self):
        for c in (self.command(source_url="https://example.org/?token=x"),
                  self.command(source_url="https://127.0.0.1/"),
                  self.command(source_url="https://user:pass@example.org/"),
                  self.command(title="line\nbreak"), self.command(year=True),
                  PREFIX+'{"title":"a","title":"b","year":2026,"source_url":"https://example.org"}',
                  "/tv-hostops movie not-json"):
            with self.assertRaises(ValueError):
                build_request(c,"123")


    def test_workflow_routes_and_manifest_matches_operation(self):
        from pathlib import Path
        import hashlib
        root = Path(__file__).resolve().parents[2]
        workflow = (root/".github/workflows/torrent-tv-hostops.yml").read_text()
        self.assertIn("HOSTOPS_COMMENT_ID: " + "$" + "{{ github.event.comment.id }}", workflow)
        self.assertIn("StartsWith('/tv-hostops movie '", workflow)
        self.assertIn("hostops\\jobs\\flow3-dispatch.ps1", workflow)
        manifest = json.loads((root/"hostops/laptop-ops/manifests/current.json").read_text())
        self.assertEqual(manifest["operation"],"owner-flow3-dispatch")
        self.assertEqual(hashlib.sha256((root/manifest["script_path"]).read_bytes()).hexdigest(),manifest["script_sha256"])
        runner = (root/"hostops/jobs/flow3-dispatch.ps1").read_text()
        owner = (root/manifest["script_path"]).read_text()
        self.assertIn("owner_movie_flow.ps1",runner)
        self.assertIn("owner_g2_submit.py",owner)
        self.assertIn("FLOW3_PRIOR_REQUEST_NO_REPLAY",runner)
        self.assertNotIn("Get-NetTCPConnection",runner)
        self.assertNotIn("browser.pending",runner)


if __name__ == "__main__":
    unittest.main()
