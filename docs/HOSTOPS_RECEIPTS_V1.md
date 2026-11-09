# HostOps v1.1 — Issue-linked run receipts (source-only)

## Why
The Torrent TV HostOps owner-only issue-comment workflow previously created an Actions run but never posted its `run_id` back to the command inbox. The ChatGPT GitHub connector can read job logs when the run/job ID is known, but does not list runs. Thus command #6725005504 (`g1thorprobe2`) could not be reconciled to a verified log from the chat alone. **Do not fabricate a run ID.**

## Change, narrowly scoped
- Leave existing `owner-command` Windows job and its `contents: read` workflow token **byte-for-byte unchanged**.
- New `run-link-receipt` GitHub-hosted Ubuntu metadata job posts `HOSTOPS_RUN_LINK_V1` to Issue #82 with triggering comment ID, actual workflow `github.run_id`, and clickable Actions URL, **even while dedicated Windows runner is queued/offline**.
- New `final-result-receipt` GitHub-hosted metadata job runs after `owner-command` reaches a terminal result and posts `HOSTOPS_JOB_RESULT_V1` with `needs['owner-command'].result` (`success`, `failure`, `cancelled`, `skipped`).
- Both metadata jobs require the exact repository, authenticated OWNER `trung-via`, only Issue #82 (not PR), and `/tv-hostops ` prefix. They run *no owner branch code* and do not checkout repository contents.
- Only those GitHub-hosted metadata jobs receive `issues: write`; their `contents: none` and short timeout isolate permissions from Windows PowerShell. No new Windows host privileges, ADB actions, media or TorrServer access.
- GitHub bot's own receipt comments cause skipped event runs, not a new executable owner command, because the actor/author association do not pass the OWNER guard.

## Evidence boundaries
- `HOSTOPS_RUN_LINK_V1` means the command produced a real Actions run identifier, **not** that Windows executed.
- `HOSTOPS_JOB_RESULT_V1` means only the Windows Actions job result; a `success` still **does not** certify Redmi, ADB connection, SRT display, seek, TV G1/G3, G4 release, or license compliance.
- Never include the original raw command or job stdout, device serial, LAN IP, user paths, media text, secrets or subtitles in receipt comments. Pair by numeric command comment ID.
- This change cannot retrospectively attach a run ID to previously created commands. Send a fresh owner-approved probe only after the PR is merged and receipt job is verified.

## Acceptance / fail closed
1. Confirm PR diff contains only `torrent-tv-hostops.yml` metadata jobs and this document, without changing the Windows job.
2. Check `github.actor`, `event.comment.user.login`, author association `OWNER`, issue #82 and non-PR guard on **each** metadata job.
3. Confirm credential separation: Windows `contents: read`, receipt jobs `issues: write` and `contents: none`, no checkout.
4. GitHub Actions YAML/CI validation at exact PR HEAD before merge.
5. After authorized merge, post exactly one `/tv-hostops probe` to Issue #82, verify bot `HOSTOPS_RUN_LINK_V1` includes matching source comment ID and existing Actions run. Then verify `HOSTOPS_JOB_RESULT_V1` matches job conclusion. This is not a real TV proof.
6. Negative test: comments from other actors, PRs, or other Issues produce no receipt and no Windows run. GitHub bot receipt comments must not re-trigger owner jobs.

## Rollback
Revert metadata jobs; Windows command workflow remains unchanged. Existing comments and original logs remain available. Avoid any host, APK, ADB or TorrServer operation to test this PR.
