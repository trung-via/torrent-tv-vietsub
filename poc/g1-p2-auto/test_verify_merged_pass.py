"""Offline negative/positive gates; no GitHub, host or network calls."""
import unittest

from verify_merged_pass import Hold, REPO, OWNER, validate

HEAD = "a" * 40
BASE = "b" * 40
MERGE = "c" * 40
PASS = (f"TORRENT_TV_BRAIN_REVIEW_PASS_V1\npr=51\n"
        f"head_sha={HEAD}\nbase_sha={BASE}")
HOLD = PASS.replace("REVIEW_PASS_V1", "REVIEW_HOLD_V1")


def pr():
    return {
        "number": 51, "state": "closed", "merged_at": "2026-11-07T03:00:00Z",
        "merge_commit_sha": MERGE, "draft": False,
        "head": {"sha": HEAD, "repo": {"full_name": REPO}},
        "base": {"ref": "main", "sha": BASE},
    }


def comment(body=PASS, author=OWNER, assoc="OWNER", id=1,
            created="2026-11-07T02:00:00Z", updated=None):
    return {
        "id": id, "user": {"login": author},
        "author_association": assoc, "body": body,
        "created_at": created, "updated_at": updated or created,
    }


def checks():
    return {
        "total_count": 2,
        "check_runs": [
            {"name": "TV Verified Code CI", "status": "completed",
             "conclusion": "success", "app": {"slug": "github-actions"}},
            {"name": "Static Policy CI", "status": "completed",
             "conclusion": "success", "app": {"slug": "github-actions"}},
        ],
    }


def verify(**kw):
    params = {
        "repo": REPO, "sha": MERGE, "before": BASE, "current": MERGE,
        "commit": {"sha": MERGE, "parents": [{"sha": BASE}]},
        "prs": [pr()], "comments": [comment()], "checks": checks(),
    }
    params.update(kw)
    return validate(**params)


class AutoBuildBrainGateTests(unittest.TestCase):
    def test_owner_brain_pass_canonical_current_head_base_and_ci(self):
        self.assertEqual(verify(), 51)

    def test_non_owner_comment_is_not_a_brain_signoff(self):
        with self.assertRaises(Hold):
            verify(comments=[comment(author="outsider")])

    def test_wrong_author_association_fails_closed(self):
        with self.assertRaises(Hold):
            verify(comments=[comment(assoc="CONTRIBUTOR")])

    def test_latest_hold_revokes_previous_pass(self):
        with self.assertRaises(Hold):
            verify(comments=[comment(), comment(HOLD, id=2, created="2026-11-07T02:10:00Z")])

    def test_mismatched_head_base_or_pr_number_rejected(self):
        for body in (
            PASS.replace(HEAD, "d" * 40),
            PASS.replace(BASE, "e" * 40),
            PASS.replace("pr=51", "pr=52"),
        ):
            with self.subTest(body=body):
                with self.assertRaises(Hold):
                    verify(comments=[comment(body)])

    def test_direct_main_push_without_merged_pr_does_not_build(self):
        with self.assertRaises(Hold):
            verify(prs=[])

    def test_ambiguous_associated_prs_rejected(self):
        with self.assertRaises(Hold):
            verify(prs=[pr(), pr()])

    def test_forked_pr_cannot_run_owner_windows_runner(self):
        p = pr()
        p["head"]["repo"]["full_name"] = "outsider/fork"
        with self.assertRaises(Hold):
            verify(prs=[p])

    def test_stale_main_branch_rejected(self):
        with self.assertRaises(Hold):
            verify(current="d" * 40)

    def test_invalid_parent_or_source_merge_sha_rejected(self):
        with self.assertRaises(Hold):
            verify(commit={"sha": MERGE, "parents": [{"sha": "d" * 40}]})
        with self.assertRaises(Hold):
            verify(commit={"sha": "d" * 40, "parents": [{"sha": BASE}]})

    def test_failed_or_running_checks_rejected(self):
        for state, conclusion in (("completed", "failure"), ("in_progress", None)):
            c = checks()
            c["check_runs"][0].update(status=state, conclusion=conclusion)
            with self.subTest(state=state):
                with self.assertRaises(Hold):
                    verify(checks=c)

    def test_untrusted_ci_app_rejected(self):
        c = checks()
        c["check_runs"][0]["app"]["slug"] = "third-party"
        with self.assertRaises(Hold):
            verify(checks=c)

    def test_missing_required_ci_rejected(self):
        c = checks()
        c["check_runs"][0]["name"] = "not-code-test"
        with self.assertRaises(Hold):
            verify(checks=c)

    def test_truncated_ci_results_rejected(self):
        c = checks()
        c["total_count"] = 3
        with self.assertRaises(Hold):
            verify(checks=c)

    def test_brain_pass_created_or_modified_after_merge_rejected(self):
        with self.assertRaises(Hold):
            verify(comments=[comment(created="2026-11-07T04:00:00Z")])
        with self.assertRaises(Hold):
            verify(comments=[comment(updated="2026-11-07T04:00:00Z")])

    def test_malformed_or_extra_comment_content_rejected(self):
        for body in (PASS + "\nOops", "brain pass", PASS + " EXTRA"):
            with self.subTest(body=body):
                with self.assertRaises(Hold):
                    verify(comments=[comment(body)])


if __name__ == "__main__":
    unittest.main()
