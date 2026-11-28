# Torrent TV HostOps v1 — GitHub → Windows PowerShell (independent project)

> Inbox rollover (2026-11-27): #82 reached GitHub's 2,500-comment limit; its history remains unchanged. #196 is the successor when the trusted workflow is merged. Run 46000758351 executed the Windows job but both receipt posts failed HTTP 403. Reconcile by exact Actions run/job ID before any retry; a missing comment is not evidence of non-execution. Initial probe verifies only the route, not Owner or TV acceptance.

Status: **source prepared; activation requires workflow merge and real runner receipt**. Owner issue: [#196](https://github.com/trung-via/torrent-tv-vietsub/issues/196).

## Purpose

Reduce Human PowerShell work by using the existing dedicated Windows runner (`torrent-tv-vietsub-win`) from this repository only. GitHub-connected ChatGPT can create the job script on an exact `hostops/<job-id>` branch and leave an owner-authorized comment in Issue #196. GitHub Actions executes the pinned script as the **existing runner service account**, collects its exit code and log, and ChatGPT inspects the receipt. No AIOS/AI Commerce runner/service/secret reuse and no extra Windows installer are implied.

## Activation and limitations

1. Review and merge the `torrent-tv-hostops.yml` workflow on `main` so the `issue_comment` event is recognized by GitHub Actions. This new workflow is inert on a feature branch.
2. Post `/tv-hostops probe` as the authenticated owner to Issue #196. Inspect the Actions run, actual runner identity, and exit code. A skipped/queued job is **not** proof of HostOps success. If the runner is offline, this bridge cannot start a Windows service or change its credentials.
3. Post `/tv-hostops write-probe` and inspect the receipt. The test creates, verifies, and removes a disposable file in `RUNNER_TEMP`; it does **not** grant Windows Administrator privileges.
4. For source/build/test jobs: create dedicated branch `hostops/<job-id>`, add `hostops/jobs/<job-id>.ps1` to it, pin its **exact 40-character branch-tip SHA**, and comment `/tv-hostops run <SHA> <job-id>`. The workflow checks the branch head against that SHA before checkout and PowerShell execution. Branch movement requires a new explicit comment.
5. Continue development through ordinary feature branches/PRs, using GitHub connector for persistent source writes. HostOps source/build/test operations run as the runner's Windows identity. Branch jobs are arbitrary PowerShell and thus should only be authored and approved by the owner in this personal-project setup.

## Supported commands

| Owner comment in Issue #196 | Side effect |
| --- | --- |
| `/tv-hostops probe` | Read-only host/runner/git preflight |
| `/tv-hostops write-probe` | One reversible test file in runner temporary directory |
| `/tv-hostops run <sha> <job-id>` | Execute only the script on exact SHA of repo-local `hostops/<job-id>`; full runner-user filesystem permissions apply |

No GitHub App `workflow_dispatch` action is needed; the existing connector can comment on Issue #196 using the authenticated owner identity. Any other comment author or any other Issue is skipped. A public repository does **not** automatically make arbitrary comments authorized to run host commands.

## Scope and evidence

- Expected Windows runner: `torrent-tv-vietsub-win`, labels `self-hosted, Windows, X64, torrent-tv-vietsub`, workspace beneath `C:\TOOL\TorrentTV-Runner\_work`.
- `contents:read` token for runner workflow; PR/branch writes from ChatGPT use the separate authenticated GitHub connector rather than passing write-token access to arbitrary PowerShell scripts.
- This grants **non-elevated local PowerShell execution and normal file writes** the runner account already permits. It does not auto-elevate, install a Windows service, grant ADB access, change firewall/UPnP, access other repositories, or validate a real TV/server.
- Do not include magnet passkeys, tokens, personal media paths/URLs or credentials in scripts, logs or artifacts. Do not use unrelated runner workspace/secrets. Preserve OMP-first architecture and real-TV proof boundaries.
- Required evidence per job: comment ID, exact branch SHA, run/job ID, runner identity, command/exit code, source diff and target-specific test outcome. `HOSTOPS_PINNED_JOB_PASS` only certifies script exit 0; it is **not** TV/Media3/TorrServer E2E acceptance.

## Example jobs

A safe trial script is prepared on branch `hostops/smoke`, path `hostops/jobs/smoke.ps1`. After the bridge is merged and both probe actions pass, use the exact branch-tip SHA to issue `/tv-hostops run <sha> smoke`. This script must remain limited to the dedicated workspace and no external system change.

## Rollback

Delete/disable the workflow on `main` to stop accepting commands. Remove the dedicated job branches if no longer needed. Disable the dedicated runner separately only when owner authorizes the Windows action; changing workflow code does not stop an already running runner service.

## Flow3 production command (source candidate, activation after merge)

The existing owner issue #196 accepts one typed movie command for every title; no per-film branch, workflow or new worker:

```text
/tv-hostops movie {"title":"Authorized fixture","year":2026,"source_url":"https://example.org/","mode":"play","media_authorized":true}
```

Use `mode:"search"` (default) for metadata only; omit media_authorized or set false. Use play only with an authorized public source and media the owner is permitted to acquire/play. Resolution defaults to 1080p. The caller supplies the permitted public HTTPS origin; do not include credentials, private locators, or tokens in public comments. The example is a synthetic command shape, not a real playable source. The film title is visible in the public issue.

Existing authenticated owner guard and run-link/final-result receipts apply. The command identity derives from the source comment ID: repeating the same Actions event cannot resubmit the Owner request. The existing enrolled interactive task reads the data-only sidecar and submits the original G2 request contract, then the runner calls the existing owner_movie_flow.ps1 on a matching Library-ready receipt. No browser preflight, source review, per-film branch or second orchestrator in routine dispatch. Existing Owner and player own runtime errors, media identity and dedupe. Unknown effects are not retried. Workflow success is not evidence of rendered video or subtitles.

The installed helper must be verified to accept the main-pinned manifest and read the sidecar; no live provider or TV acceptance claimed from source CI. An ingress regression can be rolled back by reverting the one workflow route; other HostOps commands remain available.
