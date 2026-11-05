# Torrent TV Vietsub — Brain PASS → trusted PR auto-merge (Issue #42)

**Decision date:** 2026-11-05. **Owner:** Torrent TV Vietsub, not AI Commerce or AIOS. **Repository:** `trung-via/torrent-tv-vietsub` (GitHub currently reports PUBLIC). **Authority:** the Human standing authorization recorded in [Issue #42](https://github.com/trung-via/torrent-tv-vietsub/issues/42). This supersedes the older per-PR Human merge approval step only for GitHub source PR merges meeting every gate.

## Decision and scope

`ENGINEERING_CANDIDATE → Independent Torrent TV Brain review → PASS → automatic PR merge without another Human question`.

This is **not** approval for a new APK install, ADB/Windows/TorrServer change, runner or firewall update, release/signing, publishing, media/rights change or broad service/credential access. G0/G1/G2/G3/G4 have separate acceptance scopes. A passing unit test or a completed workflow is not itself an actual Redmi/TorrServer acceptance receipt.

Brain must review exact HEAD, exact base/main, changed files, relevant contracts/ADRs, required tests and observed evidence; UNKNOWN/FAIL/HOLD never generates PASS. Do not replay old PASS after source or base drift. Human retains product direction and explicitly privileged host/media actions.

## Two-part exact authorization (ChatGPT Brain ↔ GitHub)

The *canonical* Brain product acceptance is a four-line **PR Conversation comment**, authored via the authenticated GitHub account **after** an independent Brain review. Replace placeholders with live exact values; no header, footer or code fence:

```text
TORRENT_TV_BRAIN_REVIEW_PASS_V1
pr=<decimal>
head_sha=<40 lowercase hex>
base_sha=<40 lowercase hex>
```

For rejection/revocation, the same four-line structure starts with `TORRENT_TV_BRAIN_REVIEW_HOLD_V1`. The most recent canonical owner Conversation verdict wins. A PASS must then be followed by a separate GitHub **COMMENT review**, carrying the *identical* four-line text and pinned to the exact PR HEAD. This review is a wake only; it is not a GitHub APPROVE action and cannot substitute for the canonical Conversation verdict.

The default-branch workflow `.github/workflows/torrent-tv-brain-auto-merge.yml` listens only to `pull_request_review: submitted` and checks GitHub Owner identity `trung-via`. It checks the event review and re-fetches the saved review, canonical owner Conversation verdict, PR metadata, changed files, latest main, all available CI results and mergeability. It executes only the trusted **main** copy of `.github/scripts/tv_brain_merge.py`; it never checks out or executes PR-head code using a write token. All permission and GitHub API errors fail closed. The merge API binds to the exact HEAD SHA, and the workflow independently reads back `merged` and merge commit SHA.

**Important trust limit:** GitHub Owner authentication does not cryptographically identify a particular Brain model/session. A real independent Brain review in ChatGPT must occur before publishing the canonical PASS; GitHub checks the owner's exact signed account action and document content, not the model's inner reasoning.

## Fail-closed gates

- Exact repo, Owner account, COMMENT review, canonical four-line conversation PASS, same PR/HEAD/base and review timestamp; latest HOLD cancels PASS.
- PR `open`, **not Draft**, no fork, base branch `main`, base SHA equals latest `main`, HEAD unchanged and GitHub `mergeable_state=clean`. No force push, default-branch write or auto-update of PR source.
- Diff is classified by all changed paths (including the old path in a rename). Documentation-only paths: `docs/`, `planning/`, `chatgpt/`, and explicitly listed root Markdown files. These can merge after genuine Brain PASS and absence of any failed/pending available checks; a new full Android build is not required for docs-only changes.
- Changes restricted to the four new Brain-merge policy workflow/script paths plus docs require a trusted successful GitHub-hosted `TV Brain Policy Tests` check. New/mixed source or any other workflow/runner code requires an actual trusted `TV Verified Code CI` check on this exact PR head/merge-ref, in addition to Brain's relevant acceptance evidence.
- Currently, `TV Verified Code CI` is **not yet deployed**. Non-policy source PRs therefore HOLD even if their owner publishes PASS, until a separately reviewed and verified code CI gate exists. Do **not** fabricate that gate, reuse AIOS runner evidence, or weaken it per-PR.
- Existing unrelated failures, incomplete checks and commit-status failures block. Because GitHub may report PR workflow checks on a synthetic merge commit, the verifier checks both the PR head and its current GitHub merge ref, tied to the unchanged base.
- GitHub API response errors, incomplete pagination, policy classification ambiguity, missing tests, stale comment or concurrent main changes stop without merge.
- Repo PUBLIC does not by itself block this owner-only trusted-review workflow. Self-hosted Windows runners must not run untrusted fork PR code. The policy gate runs on GitHub-hosted Ubuntu because it is GitHub API-only and does **not** test Windows/Android software.

## Evidence, activation and rollback

This PR contains the policy script, 17 pure regression tests and two separate workflows: a hosted read-only `pull_request` policy-test job, and the privileged owner review-wake workflow. A green *policy* test proves the gate logic under mocks only. It does not prove a real GitHub merge, Android build, actual Brain identity or media runtime.

The new merge workflow cannot accept live events until its reviewed code lands on `main`. The bootstrap PR must be independently reviewed and merged with existing authenticated repository tools under the Human standing authorization; do not claim self-activation. After merge, validate the first permitted PR with exact review/check/merge receipt and independent GitHub main readback before labeling `LIVE_AUTO_MERGE_VERIFIED`.

A previous Owner HOLD, head/base drift, failed or absent required CI, or changed default-branch workflow causes a safe HOLD. Emergency rollback: revert or disable the exact main auto-merge workflow via a separately reviewed PR (or authorized GitHub settings change); it has no persistent Windows/TV services to stop. Never retry an ambiguous merge effect without fetching the actual PR merged state first.

## Independent project invariant

No AIOS or AI Commerce TASK, runner, approval signer, brain automation or live agent endpoint. No PULSE/CDP workflow reuse. No general PR bot execution beyond this explicitly owned Torrent TV policy. GitHub source merge permissions are separate from user content rights and release approvals.
