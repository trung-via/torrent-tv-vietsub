#!/usr/bin/env python3
"""Torrent TV-only, fail-closed Brain PASS GitHub PR merge gate.

Invoked by a *trusted main checkout* on pull_request_review:submitted.
Never executes PR code, contacts TV/Windows, or relies on AIOS/AI Commerce.
The GitHub owner review is a wake; the latest owner PR Conversation verdict
is the canonical decision. GitHub identity does not prove a model identity.
"""
from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

REPO = "trung-via/torrent-tv-vietsub"
OWNER = "trung-via"
MAIN = "main"
PASS = "TORRENT_TV_BRAIN_REVIEW_PASS_V1"
HOLD = "TORRENT_TV_BRAIN_REVIEW_HOLD_V1"
SHA = re.compile(r"^[0-9a-f]{40}$")
DOC_PREFIXES = ("docs/", "planning/", "chatgpt/")
DOC_FILES = frozenset({"README.md", "AGENTS.md", "PRD.md", "ROADMAP.md", "PROJECT_CONTRACT.md", "CHANGELOG.md"})
POLICY_FILES = frozenset({
    ".github/workflows/torrent-tv-brain-auto-merge.yml",
    ".github/workflows/torrent-tv-brain-policy-tests.yml",
    ".github/scripts/tv_brain_merge.py",
    ".github/scripts/test_tv_brain_merge.py",
})
POLICY_TEST = "TV Brain Policy Tests"
CODE_TEST = "TV Verified Code CI"
SELF_CHECK = "TV Brain Trusted Merge"


class Hold(Exception):
    pass


def ensure(condition: bool, reason: str) -> None:
    if not condition:
        raise Hold(reason)


def canonical(kind: str, number: int, head: str, base: str) -> str:
    return f"{kind}\npr={number}\nhead_sha={head}\nbase_sha={base}"


def normalized(body: object) -> str:
    return body.rstrip("\r\n") if isinstance(body, str) else ""


def latest_owner_verdict(comments: list[dict]) -> dict | None:
    candidates = [
        c for c in comments
        if c.get("user", {}).get("login") == OWNER
        and normalized(c.get("body")).split("\n", 1)[0] in {PASS, HOLD}
    ]
    return max(candidates, key=lambda c: int(c["id"]), default=None)


def is_document(path: str) -> bool:
    return path in DOC_FILES or path.startswith(DOC_PREFIXES)


def classify_files(files: list[dict]) -> str:
    ensure(bool(files), "NO_CHANGED_FILES")
    changed = []
    for f in files:
        ensure(f.get("status") in {"added", "modified", "removed", "renamed", "copied", "changed"}, "UNKNOWN_FILE_STATUS")
        changed.append(f["filename"])
        if f.get("previous_filename"):
            changed.append(f["previous_filename"])
    if all(is_document(p) for p in changed):
        return "docs"
    if all(is_document(p) or p in POLICY_FILES for p in changed):
        return "policy"
    return "code"


def verify_review(event: dict, pr: dict, main_sha: str) -> str:
    epr = event.get("pull_request") or {}
    r = event.get("review") or {}
    number = pr["number"]
    head = pr["head"]["sha"]
    base = pr["base"]["sha"]
    expected = canonical(PASS, number, head, base)

    ensure(event.get("action") == "submitted", "UNEXPECTED_EVENT")
    ensure(epr.get("number") == number, "EVENT_PR_MISMATCH")
    ensure(event.get("sender", {}).get("login") == OWNER, "EVENT_ACTOR_NOT_OWNER")
    ensure(r.get("user", {}).get("login") == OWNER, "REVIEW_NOT_OWNER")
    ensure(r.get("author_association") == "OWNER", "REVIEW_ASSOCIATION_NOT_OWNER")
    ensure(str(r.get("state", "")).lower() == "commented", "REVIEW_NOT_COMMENT_WAKE")
    ensure(normalized(r.get("body")) == expected, "REVIEW_BODY_NOT_EXACT_PASS")
    ensure(r.get("commit_id") == head, "STALE_REVIEW_HEAD")
    ensure(pr["state"] == "open" and not pr["draft"] and not pr["merged"], "PR_NOT_OPEN_READY")
    ensure(pr["base"]["ref"] == MAIN and base == main_sha, "BASE_NOT_CURRENT_MAIN")
    ensure(pr["head"]["repo"]["full_name"] == REPO, "FORK_OR_UNTRUSTED_HEAD")
    ensure(pr["base"]["repo"]["full_name"] == REPO, "WRONG_BASE_REPO")
    ensure(SHA.fullmatch(head) is not None and SHA.fullmatch(base) is not None, "INVALID_SHA")
    ensure(pr["mergeable"] is True and pr["mergeable_state"] == "clean", "NOT_MERGEABLE_CLEAN")
    ensure(bool(r.get("submitted_at")), "NO_REVIEW_TIME")
    return expected


def verify_verdict(comments: list[dict], expected: str, review: dict) -> None:
    winner = latest_owner_verdict(comments)
    ensure(winner is not None, "CANONICAL_CONVERSATION_VERDICT_MISSING")
    ensure(winner.get("author_association") == "OWNER", "VERDICT_ASSOCIATION_NOT_OWNER")
    ensure(normalized(winner.get("body")) == expected, "LATEST_VERDICT_IS_NOT_EXACT_PASS")
    def dt(value: str) -> datetime:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    ensure(dt(winner["created_at"]) <= dt(review["submitted_at"]), "PASS_COMMENT_AFTER_REVIEW_WAKE")
    ensure(dt(winner["updated_at"]) <= dt(review["submitted_at"]), "PASS_EDITED_AFTER_REVIEW_WAKE")


def check_ci(check_runs: list[dict], statuses: list[dict], scope: str) -> None:
    ensure(all(s.get("state") == "success" for s in statuses), "COMMIT_STATUS_NOT_SUCCESS")
    winners: set[str] = set()
    for c in check_runs:
        name = c.get("name", "")
        if name == SELF_CHECK:
            continue
        ensure(
            c.get("status") == "completed" and c.get("conclusion") in {"success", "neutral", "skipped"},
            "CI_CHECK_INCOMPLETE_OR_FAILED:" + name[:80],
        )
        if c.get("conclusion") == "success" and c.get("app", {}).get("slug") == "github-actions":
            winners.add(name)
    if scope == "policy":
        ensure(POLICY_TEST in winners, "MISSING_TRUSTED_POLICY_TEST")
    elif scope == "code":
        ensure(CODE_TEST in winners, "MISSING_TRUSTED_CODE_CI")
    # Docs-only: a genuine owner Brain PASS + no failing/pending available checks is sufficient.


def api(path: str, token: str, method: str = "GET", data: dict | None = None):
    url = "https://api.github.com" + path
    body = json.dumps(data).encode("utf-8") if data is not None else None
    request = Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "torrent-tv-brain-merge",
            "Content-Type": "application/json",
        },
    )
    with urlopen(request, timeout=25) as response:
        return json.load(response)


def pages(path: str, token: str, max_pages: int = 10) -> list[dict]:
    all_items = []
    for page in range(1, max_pages + 1):
        separator = "&" if "?" in path else "?"
        items = api(f"{path}{separator}per_page=100&page={page}", token)
        ensure(isinstance(items, list), "EXPECTED_PAGINATED_LIST")
        all_items.extend(items)
        if len(items) < 100:
            return all_items
    raise Hold("PAGINATION_LIMIT_REACHED")


def verify_pr_snapshot(token: str, number: int, head: str, base: str) -> None:
    p = api(f"/repos/{REPO}/pulls/{number}", token)
    current = api(f"/repos/{REPO}/branches/{MAIN}", token)
    ensure(
        p["state"] == "open" and not p["draft"] and not p["merged"]
        and p["head"]["sha"] == head and p["base"]["sha"] == base
        and current["commit"]["sha"] == base and p["mergeable"] is True
        and p["mergeable_state"] == "clean",
        "PR_OR_MAIN_CHANGED_BEFORE_MERGE",
    )


def execute(event: dict, token: str) -> str:
    ensure(os.environ.get("GITHUB_REPOSITORY") == REPO, "WRONG_GITHUB_REPOSITORY")
    ensure(os.environ.get("GITHUB_ACTOR") == OWNER, "WRONG_GITHUB_ACTOR")
    number = int((event.get("pull_request") or {}).get("number", 0))
    ensure(number > 0, "NO_PR_NUMBER")
    pr = api(f"/repos/{REPO}/pulls/{number}", token)
    main = api(f"/repos/{REPO}/branches/{MAIN}", token)["commit"]["sha"]
    expected = verify_review(event, pr, main)
    # Independently re-read the immutable review, not only webhook-controlled JSON.
    review_id = event["review"]["id"]
    stored_review = api(f"/repos/{REPO}/pulls/{number}/reviews/{review_id}", token)
    ensure(stored_review.get("commit_id") == pr["head"]["sha"], "STORED_REVIEW_HEAD_MISMATCH")
    ensure(normalized(stored_review.get("body")) == expected, "STORED_REVIEW_BODY_MISMATCH")
    ensure(stored_review.get("user", {}).get("login") == OWNER, "STORED_REVIEW_USER_MISMATCH")
    comments = pages(f"/repos/{REPO}/issues/{number}/comments", token)
    verify_verdict(comments, expected, event["review"])

    files = pages(f"/repos/{REPO}/pulls/{number}/files", token)
    ensure(len(files) == int(pr["changed_files"]), "INCOMPLETE_DIFF_FILE_LIST")
    scope = classify_files(files)
    check_shas = {pr["head"]["sha"]}
    if pr.get("merge_commit_sha") and SHA.fullmatch(pr["merge_commit_sha"]):
        check_shas.add(pr["merge_commit_sha"])
    observed = {}
    statuses = []
    for sha in check_shas:
        for c in pages(f"/repos/{REPO}/commits/{sha}/check-runs", token):
            observed[(c.get("name"), c.get("id"))] = c
        statuses += api(f"/repos/{REPO}/commits/{sha}/status", token).get("statuses", [])
    check_ci(list(observed.values()), statuses, scope)

    head, base = pr["head"]["sha"], pr["base"]["sha"]
    verify_pr_snapshot(token, number, head, base)
    # Fail closed if a HOLD superseded PASS while the CI checks were read.
    verify_verdict(pages(f"/repos/{REPO}/issues/{number}/comments", token), expected, event["review"])
    result = api(
        f"/repos/{REPO}/pulls/{number}/merge", token, "PUT",
        {
            "sha": head, "merge_method": "merge",
            "commit_title": f"Merge Torrent TV PR #{number} (Brain accepted)",
            "commit_message": f"Trusted exact HEAD/base Brain PASS. Source: {head}, base: {base}.",
        },
    )
    ensure(result.get("merged") is True and SHA.fullmatch(result.get("sha", "")), "MERGE_EFFECT_UNKNOWN")
    readback = api(f"/repos/{REPO}/pulls/{number}", token)
    ensure(readback.get("merged") is True and readback.get("merge_commit_sha") == result["sha"], "MERGE_READBACK_UNVERIFIED")
    return f"TV_BRAIN_AUTO_MERGE_VERIFIED pr={number} sha={result['sha']} scope={scope}"


def main() -> int:
    try:
        token = os.environ.get("GITHUB_TOKEN", "")
        ensure(bool(token), "TOKEN_MISSING")
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
        print(execute(event, token))
        return 0
    except (Hold, KeyError, ValueError, TypeError, HTTPError, URLError, TimeoutError) as e:
        print("TV_BRAIN_AUTO_MERGE_HOLD: " + str(e), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
