"""Offline pure-policy regression tests; no GitHub, Windows, ADB or network."""
import unittest
import re
from pathlib import Path
from datetime import datetime
from unittest.mock import patch

import tv_brain_merge as tv


HEAD = "a" * 40
BASE = "b" * 40
OWNER = tv.OWNER
NUMBER = 43
PASS = tv.canonical(tv.PASS, NUMBER, HEAD, BASE)
HOLD = tv.canonical(tv.HOLD, NUMBER, HEAD, BASE)


def sample_pr():
    return {
        "number": NUMBER,
        "state": "open",
        "draft": False,
        "merged": False,
        "mergeable": True,
        "mergeable_state": "clean",
        "head": {"sha": HEAD, "repo": {"full_name": tv.REPO}},
        "base": {"ref": "main", "sha": BASE, "repo": {"full_name": tv.REPO}},
        "changed_files": 1,
    }


def sample_event(body=PASS):
    return {
        "action": "submitted",
        "sender": {"login": OWNER},
        "pull_request": {"number": NUMBER},
        "review": {
            "user": {"login": OWNER},
            "author_association": "OWNER",
            "state": "commented",
            "body": body,
            "commit_id": HEAD,
            "submitted_at": "2026-11-05T15:00:00Z",
            "id": 7,
        },
    }


def comment(body, id=1, author=OWNER, association="OWNER", updated=None):
    return {
        "id": id,
        "user": {"login": author},
        "author_association": association,
        "body": body,
        "created_at": "2026-11-05T14:00:00Z",
        "updated_at": updated or "2026-11-05T14:00:00Z",
    }


def check(name, status="completed", conclusion="success", app="github-actions"):
    return {
        "name": name, "status": status, "conclusion": conclusion,
        "app": {"slug": app},
        "details_url": "https://github.com/trung-via/torrent-tv-vietsub/actions/runs/1/job/2",
        "id": 1,
    }


class BrainMergePolicyTests(unittest.TestCase):
    def test_exact_four_line_canonical_format(self):
        self.assertEqual(
            PASS,
            "TORRENT_TV_BRAIN_REVIEW_PASS_V1\npr=43\nhead_sha=" + HEAD +
            "\nbase_sha=" + BASE,
        )

    def test_valid_owner_comment_review_wake(self):
        self.assertEqual(tv.verify_review(sample_event(), sample_pr(), BASE), PASS)

    def test_foreign_actor_cannot_wake(self):
        event = sample_event()
        event["sender"]["login"] = "outsider"
        with self.assertRaises(tv.Hold):
            tv.verify_review(event, sample_pr(), BASE)

    def test_owner_assoc_must_be_owner(self):
        event = sample_event()
        event["review"]["author_association"] = "CONTRIBUTOR"
        with self.assertRaises(tv.Hold):
            tv.verify_review(event, sample_pr(), BASE)

    def test_review_cannot_be_approved_self_review_or_free_text(self):
        event = sample_event()
        event["review"]["state"] = "approved"
        with self.assertRaises(tv.Hold):
            tv.verify_review(event, sample_pr(), BASE)
        event = sample_event("looks good")
        with self.assertRaises(tv.Hold):
            tv.verify_review(event, sample_pr(), BASE)

    def test_stale_head_and_stale_base_are_rejected(self):
        event = sample_event()
        event["review"]["commit_id"] = "c" * 40
        with self.assertRaises(tv.Hold):
            tv.verify_review(event, sample_pr(), BASE)
        with self.assertRaises(tv.Hold):
            tv.verify_review(sample_event(), sample_pr(), "c" * 40)

    def test_draft_or_conflicted_pr_rejected(self):
        p = sample_pr()
        p["draft"] = True
        with self.assertRaises(tv.Hold):
            tv.verify_review(sample_event(), p, BASE)
        p = sample_pr()
        p["mergeable_state"] = "dirty"
        with self.assertRaises(tv.Hold):
            tv.verify_review(sample_event(), p, BASE)

    def test_public_fork_pr_rejected(self):
        p = sample_pr()
        p["head"]["repo"]["full_name"] = "untrusted/fork"
        with self.assertRaises(tv.Hold):
            tv.verify_review(sample_event(), p, BASE)

    def test_owner_pass_comment_required(self):
        with self.assertRaises(tv.Hold):
            tv.verify_verdict([], PASS, sample_event()["review"])
        with self.assertRaises(tv.Hold):
            tv.verify_verdict([comment(PASS, author="outsider")], PASS, sample_event()["review"])
        tv.verify_verdict([comment(PASS)], PASS, sample_event()["review"])

    def test_latest_hold_revokes_earlier_pass(self):
        comments = [comment(PASS, 1), comment(HOLD, 2)]
        self.assertEqual(tv.latest_owner_verdict(comments)["body"], HOLD)
        with self.assertRaises(tv.Hold):
            tv.verify_verdict(comments, PASS, sample_event()["review"])

    def test_edit_after_wake_rejected(self):
        with self.assertRaises(tv.Hold):
            tv.verify_verdict([comment(PASS, updated="2026-11-05T15:01:00Z")],
                              PASS, sample_event()["review"])

    def test_scope_rejects_workflows_as_docs(self):
        self.assertEqual(tv.classify_files([{"filename": "docs/README.md", "status": "added"}]), "docs")
        self.assertEqual(tv.classify_files([{"filename": "docs/X.md", "status": "modified"}, {
            "filename": ".github/workflows/torrent-tv-brain-auto-merge.yml", "status": "added",
        }]), "policy")
        self.assertEqual(tv.classify_files([{
            "filename": ".github/workflows/omp-fast-build.yml", "status": "modified",
        }]), "code")

    def test_hostops_scope_and_mixed_changes(self):
        host = {"filename": tv.HOSTOPS_WORKFLOW, "status": "modified"}
        doc = {"filename": "docs/HOSTOPS_V1.md", "status": "modified"}
        self.assertEqual(tv.classify_files([host, doc]), "hostops")
        self.assertEqual(tv.classify_files([host, {"filename": "src/app.py", "status": "modified"}]), "code")
        self.assertEqual(tv.classify_files([host, {"filename": ".github/scripts/tv_brain_merge.py", "status": "modified"}]), "code")
        self.assertEqual(tv.classify_files([{"filename": tv.HOSTOPS_WORKFLOW, "previous_filename": "src/app.py", "status": "renamed"}]), "code")

    def test_hostops_requires_policy_check_not_product_ci(self):
        for checks in ([], [check(tv.CODE_TEST)], [check(tv.POLICY_TEST, app="third-party")]):
            with self.assertRaises(tv.Hold):
                tv.check_ci(checks, [], "hostops")
        tv.check_ci([check(tv.POLICY_TEST)], [], "hostops")
        with self.assertRaises(tv.Hold):
            tv.check_ci([check(tv.POLICY_TEST), check("other", conclusion="failure")], [], "hostops")

    def test_hostops_workflow_routes_consistent(self):
        source = (Path(__file__).resolve().parents[1] / "workflows" / "torrent-tv-hostops.yml").read_text(encoding="utf-8")
        guards = re.findall(r"github\.event\.issue\.number == (\d+) &&", source)
        destinations = re.findall(r"/issues/(\d+)/comments", source)
        summaries = re.findall(r"Issue: #(\d+)", source)
        self.assertEqual(len(guards), 3)
        self.assertEqual(len(destinations), 2)
        self.assertEqual(len(summaries), 1)
        self.assertEqual(len(set(guards + destinations + summaries)), 1)
        for guard in ("github.repository == 'trung-via/torrent-tv-vietsub'",
                      "github.actor == 'trung-via'",
                      "github.event.comment.user.login == 'trung-via'",
                      "github.event.comment.author_association == 'OWNER'",
                      "github.event.issue.pull_request == null",
                      "startsWith(github.event.comment.body, '/tv-hostops ')"):
            self.assertEqual(source.count(guard), 3)
        self.assertEqual(source.count("runs-on: [self-hosted, Windows, X64, torrent-tv-vietsub]"), 1)
        self.assertEqual(source.count("runs-on: ubuntu-latest"), 2)
        self.assertEqual(source.count("issues: write"), 2)
        self.assertEqual(source.count("contents: none"), 2)
        self.assertIn("permissions:\n  contents: read", source)
        self.assertIn("cancel-in-progress: false", source)
        self.assertIn("branch head differs from approved exact SHA", source)

    def test_renamed_non_document_stays_code(self):
        self.assertEqual(tv.classify_files([{
            "filename": "docs/new.md", "previous_filename": "src/tv.ts",
            "status": "renamed",
        }]), "code")

    def test_docs_allow_zero_checks_but_not_failed_checks(self):
        tv.check_ci([], [], "docs")
        with self.assertRaises(tv.Hold):
            tv.check_ci([check("danger", conclusion="failure")], [], "docs")
        with self.assertRaises(tv.Hold):
            tv.check_ci([], [{"state": "pending"}], "docs")

    def test_policy_requires_trusted_successful_test(self):
        with self.assertRaises(tv.Hold):
            tv.check_ci([], [], "policy")
        with self.assertRaises(tv.Hold):
            tv.check_ci([check(tv.POLICY_TEST, app="third-party")], [], "policy")
        tv.check_ci([check(tv.POLICY_TEST)], [], "policy")

    def test_app_source_requires_dedicated_code_ci(self):
        with self.assertRaises(tv.Hold):
            tv.check_ci([check(tv.POLICY_TEST)], [], "code")
        tv.check_ci([check(tv.CODE_TEST)], [], "code")

    def test_own_in_progress_check_not_self_blocking(self):
        tv.check_ci([check(tv.SELF_CHECK, status="in_progress", conclusion=None)], [], "docs")

    def test_unstable_only_with_trusted_merge_self_check(self):
        p = sample_pr()
        p["mergeable_state"] = "unstable"
        self.assertEqual(tv.verify_review(sample_event(), p, BASE), PASS)
        with self.assertRaises(tv.Hold):
            tv.verify_mergeability(p, [])
        self_check = check(tv.SELF_CHECK, status="in_progress", conclusion=None)
        tv.verify_mergeability(p, [self_check])
        tv.check_ci([self_check], [], "docs")
        with self.assertRaises(tv.Hold):
            tv.check_ci([self_check, check("other", conclusion="failure")], [], "docs")
        with self.assertRaises(tv.Hold):
            tv.check_ci([check(tv.SELF_CHECK, app="third-party", conclusion="failure")], [], "docs")
        p["mergeable_state"] = "blocked"
        with self.assertRaises(tv.Hold):
            tv.verify_mergeability(p, [self_check])

    def test_check_runs_api_envelope(self):
        with patch.object(tv, "api", return_value={"total_count": 1, "check_runs": [check("ok")]}):
            self.assertEqual(len(tv.read_check_runs("/checks", "test")), 1)
        with patch.object(tv, "api", return_value={"total_count": 2, "check_runs": [check("ok")]}):
            with self.assertRaises(tv.Hold):
                tv.read_check_runs("/checks", "test")
        with patch.object(tv, "api", return_value=[]):
            with self.assertRaises(tv.Hold):
                tv.read_check_runs("/checks", "test")


if __name__ == "__main__":
    unittest.main()
