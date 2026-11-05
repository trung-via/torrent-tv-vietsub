"""Offline pure-policy regression tests; no GitHub, Windows, ADB or network."""
import unittest
from datetime import datetime

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


if __name__ == "__main__":
    unittest.main()
