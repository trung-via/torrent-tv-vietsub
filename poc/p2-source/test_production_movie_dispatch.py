"""Offline contract check for the new typed HostOps dispatch. No host or provider."""
from pathlib import Path
import re
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

if __name__=="__main__":unittest.main()
