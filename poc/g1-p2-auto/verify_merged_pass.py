"""Fail-closed GitHub-hosted provenance gate for automatic G1+P2 Debug builds.

The only side effect is a one-line GITHUB_OUTPUT approval for the same-commit
workflow. Never imports/executes PR-head Python on the Windows self-host.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
from urllib.request import Request, urlopen

REPO = "trung-via/torrent-tv-vietsub"
OWNER = "trung-via"
FULL = re.compile(r"^[a-f0-9]{40}$")
VERDICT = re.compile(
    r"^(TORRENT_TV_BRAIN_REVIEW_(?:PASS|HOLD)_V1)\n"
    r"pr=([1-9][0-9]*)\n"
    r"head_sha=([0-9a-f]{40})\n"
    r"base_sha=([0-9a-f]{40})$"
)


# Do not rebuild Gradle for a signer-parser-only accepted merge. The path
# classification occurs on the trusted GitHub-hosted gate, not self-host.
SIGNER_ONLY_PATHS = frozenset({
    ".github/workflows/tv-g1p2-auto-debug.yml",
    ".github/workflows/tv-g1p2-auto-policy-ci.yml",
    "poc/g1-p2-auto/apk-signer-digests.ps1",
    "poc/g1-p2-auto/retain-private-arm32.ps1",
    "poc/g1-p2-auto/reverify-retained-arm32.ps1",
    "poc/g1-p2-auto/test_apk_signer_digests.ps1",
    "poc/g1-p2-auto/test_private_retention.py",
    "poc/g1-p2-auto/test_auto_workflow_contract.py",
    "poc/g1-p2-auto/verify_merged_pass.py",
    "poc/g1-p2-auto/test_verify_merged_pass.py",
    "tools/redmi-validation/verify-g1p2-arm32.ps1",
    "tools/redmi-validation/test_private_handoff.py",
})
SIGNER_FIX_PATHS = frozenset({
    "poc/g1-p2-auto/apk-signer-digests.ps1",
    "poc/g1-p2-auto/retain-private-arm32.ps1",
    "poc/g1-p2-auto/reverify-retained-arm32.ps1",
    "tools/redmi-validation/verify-g1p2-arm32.ps1",
})


def select_action(files: list[dict]) -> str:
    if not isinstance(files, list) or not files or len(files) > 100:
        raise Hold("PR_FILE_LIST_INVALID")
    paths = set()
    for record in files:
        name = record.get("filename") if isinstance(record, dict) else None
        if (not isinstance(name, str) or not name
                or record.get("status") not in ("added", "modified")):
            raise Hold("PR_FILES_NOT_SAFE_TO_CLASSIFY")
        paths.add(name)
    if paths.issubset(SIGNER_ONLY_PATHS) and paths.intersection(SIGNER_FIX_PATHS):
        return "reverify"
    return "build"


class Hold(Exception):
    pass


def render_brain_verdict(pr_number: int, head_sha: str, base_sha: str,
                         approve: bool = True) -> str:
    """Render the only receipt accepted by the post-merge provenance gate.

    Use before merge; a human-readable review narrative is NOT this receipt.
    This function never posts a comment or grants build permission.
    """
    if (type(pr_number) is not int or pr_number < 1
            or not FULL.fullmatch(head_sha or "")
            or not FULL.fullmatch(base_sha or "")):
        raise Hold("BRAIN_VERDICT_INPUT_INVALID")
    decision = "PASS" if approve else "HOLD"
    body = (f"TORRENT_TV_BRAIN_REVIEW_{decision}_V1\n"
            f"pr={pr_number}\nhead_sha={head_sha}\nbase_sha={base_sha}")
    if not VERDICT.fullmatch(body):
        raise Hold("BRAIN_VERDICT_RENDER_INVALID")
    return body


def noncanonical_owner_review_present(comments: list[dict]) -> bool:
    """Diagnostic only: never reinterpret a free-form review as authorization."""
    for row in comments:
        if not isinstance(row, dict):
            continue
        author = row.get("user")
        if (not isinstance(author, dict) or author.get("login") != OWNER
                or row.get("author_association") != "OWNER"):
            continue
        body = row.get("body")
        if isinstance(body, str) and "TORRENT_TV_BRAIN_REVIEW" in body:
            return True
    return False


def canonical(comment: dict):
    author = comment.get("user") or {}
    if author.get("login") != OWNER or comment.get("author_association") != "OWNER":
        return None
    body = comment.get("body")
    if not isinstance(body, str):
        return None
    match = VERDICT.fullmatch(body.replace("\r\n", "\n").rstrip("\n"))
    if not match:
        return None
    return {
        "type": match.group(1),
        "number": int(match.group(2)),
        "head": match.group(3),
        "base": match.group(4),
        "created": comment.get("created_at") or "",
        "updated": comment.get("updated_at") or "",
        "id": comment.get("id") or 0,
    }


def validate(repo: str, sha: str, before: str, current: str,
             commit: dict, prs: list[dict], comments: list[dict],
             checks: dict) -> int:
    """Returns the authorized PR number; never equates CI with TV acceptance."""
    if repo != REPO or any(not FULL.fullmatch(x or "") for x in (sha, before, current)):
        raise Hold("REPO_OR_SHA_INVALID")
    if current != sha:
        raise Hold("MAIN_ADVANCED_OR_SOURCE_DRIFT")
    parents = commit.get("parents") or []
    if not parents or parents[0].get("sha") != before or commit.get("sha") != sha:
        raise Hold("PUSH_NOT_FIRST_PARENT_OF_MAIN")
    selected = [p for p in prs if p.get("merge_commit_sha") == sha
                and p.get("merged_at") and p.get("state") == "closed"]
    if len(selected) != 1:
        raise Hold("NO_UNIQUE_MERGED_PR")
    pr = selected[0]
    num = pr.get("number")
    head = (pr.get("head") or {}).get("sha")
    source_repo = ((pr.get("head") or {}).get("repo") or {}).get("full_name")
    target_ref = (pr.get("base") or {}).get("ref")
    if (not isinstance(num, int) or num < 1 or not FULL.fullmatch(head or "")
        or source_repo != REPO or target_ref != "main" or pr.get("draft")):
        raise Hold("PR_SCOPE_INVALID")
    verdicts = [c for c in (canonical(row) for row in comments) if c is not None]
    if not verdicts:
        if noncanonical_owner_review_present(comments):
            raise Hold("BRAIN_VERDICT_NONCANONICAL_FOUR_LINE_REQUIRED")
        raise Hold("BRAIN_VERDICT_MISSING")
    verdicts.sort(key=lambda c: (c["created"], c["id"]))
    last = verdicts[-1]
    if (last["type"] != "TORRENT_TV_BRAIN_REVIEW_PASS_V1"
        or last["number"] != num or last["head"] != head or last["base"] != before
        or not last["created"] or last["created"] > pr["merged_at"]
        or (last["updated"] and last["updated"] > pr["merged_at"])):
        raise Hold("LATEST_BRAIN_PASS_NOT_CURRENT_OR_REVOKED")
    count = checks.get("total_count")
    entries = checks.get("check_runs") or []
    if not isinstance(count, int) or count < 1 or count > 100 or len(entries) != count:
        raise Hold("CI_PAGINATION_OR_EMPTY")
    for run in entries:
        if (run.get("status") != "completed" or run.get("conclusion") != "success"
            or (run.get("app") or {}).get("slug") != "github-actions"):
            raise Hold("PR_HEAD_CI_INCOMPLETE_OR_FAILED")
    if not any(run.get("name") == "TV Verified Code CI" for run in entries):
        raise Hold("REQUIRED_CODE_CI_MISSING")
    return num


def get_api(path: str, token: str):
    url = "https://api.github.com/" + path
    req = Request(url, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "torrent-tv-g1p2-trusted-merge-gate",
    })
    with urlopen(req, timeout=20) as resp:
        # If the result is over a page, HOLD rather than silently discard data.
        if 'rel="next"' in (resp.headers.get("Link") or ""):
            raise Hold("GITHUB_API_PAGINATION")
        data = resp.read(2_000_001)
        if len(data) > 2_000_000:
            raise Hold("GITHUB_API_TOO_LARGE")
        return json.loads(data)


def main() -> int:
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    sha = os.environ.get("GITHUB_SHA", "")
    before = os.environ.get("PUSH_BEFORE", "")
    token = os.environ.get("GH_TOKEN", "")
    if os.environ.get("GITHUB_EVENT_NAME") != "push":
        raise Hold("AUTO_ONLY_ON_PUSH")
    if os.environ.get("GITHUB_REF") != "refs/heads/main" or not token:
        raise Hold("NOT_MAIN_OR_MISSING_AUTH")
    branch = get_api(f"repos/{REPO}/branches/main", token)
    current = (branch.get("commit") or {}).get("sha", "")
    commit = get_api(f"repos/{REPO}/commits/{sha}", token)
    prs = get_api(f"repos/{REPO}/commits/{sha}/pulls?per_page=100", token)
    if not isinstance(prs, list) or len(prs) > 100:
        raise Hold("PR_LIST_INVALID")
    selected = [p for p in prs if p.get("merge_commit_sha") == sha and p.get("merged_at")]
    if len(selected) != 1:
        raise Hold("MERGE_PR_NOT_UNIQUE")
    num = selected[0].get("number")
    comments = get_api(f"repos/{REPO}/issues/{num}/comments?per_page=100", token)
    checks = get_api(f"repos/{REPO}/commits/{selected[0]['head']['sha']}/check-runs?per_page=100", token)
    result = validate(repo, sha, before, current, commit, prs, comments, checks)
    files = get_api(f"repos/{REPO}/pulls/{result}/files?per_page=100", token)
    action = select_action(files)
    out = os.environ.get("GITHUB_OUTPUT")
    if not out:
        raise Hold("GITHUB_OUTPUT_MISSING")
    with Path(out).open("a", encoding="utf-8") as f:
        f.write("approved=true\n")
        f.write("pr=" + str(result) + "\n")
        f.write("source_sha=" + sha + "\n")
        f.write("action=" + action + "\n")
    print(f"AUTO_G1P2_BRAIN_PASS_CI_PROVEN pr={result} commit={sha} action={action}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        # This is an explicit red/hold, not an alternative API fallback.
        print("AUTO_G1P2_HOLD: " + (str(exc) if isinstance(exc, Hold) else type(exc).__name__))
        raise SystemExit(1)
