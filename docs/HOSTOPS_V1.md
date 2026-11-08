# Torrent TV HostOps v1 — GitHub → Windows PowerShell (independent project)

Status: **source prepared; activation requires workflow merge and real runner receipt**. Owner issue: [#82](https://github.com/trung-via/torrent-tv-vietsub/issues/82).

## Purpose

Reduce Human PowerShell work by using the existing dedicated Windows runner (`torrent-tv-vietsub-win`) from this repository only. GitHub-connected ChatGPT can create the job script on an exact `hostops/<job-id>` branch and leave an owner-authorized comment in Issue #82. GitHub Actions executes the pinned script as the **existing runner service account**, collects its exit code and log, and ChatGPT inspects the receipt. No AIOS/AI Commerce runner/service/secret reuse and no extra Windows installer are implied.

## Activation and limitations

1. Review and merge the `torrent-tv-hostops.yml` workflow on `main` so the `issue_comment` event is recognized by GitHub Actions. This new workflow is inert on a feature branch.
2. Post `/tv-hostops probe` as the authenticated owner to Issue #82. Inspect the Actions run, actual runner identity, and exit code. A skipped/queued job is **not** proof of HostOps success. If the runner is offline, this bridge cannot start a Windows service or change its credentials.
3. Post `/tv-hostops write-probe` and inspect the receipt. The test creates, verifies, and removes a disposable file in `RUNNER_TEMP`; it does **not** grant Windows Administrator privileges.
4. For source/build/test jobs: create dedicated branch `hostops/<job-id>`, add `hostops/jobs/<job-id>.ps1` to it, pin its **exact 40-character branch-tip SHA**, and comment `/tv-hostops run <SHA> <job-id>`. The workflow checks the branch head against that SHA before checkout and PowerShell execution. Branch movement requires a new explicit comment.
5. Continue development through ordinary feature branches/PRs, using GitHub connector for persistent source writes. HostOps source/build/test operations run as the runner's Windows identity. Branch jobs are arbitrary PowerShell and thus should only be authored and approved by the owner in this personal-project setup.

## Supported commands

| Owner comment in Issue #82 | Side effect |
| --- | --- |
| `/tv-hostops probe` | Read-only host/runner/git preflight |
| `/tv-hostops write-probe` | One reversible test file in runner temporary directory |
| `/tv-hostops run <sha> <job-id>` | Execute only the script on exact SHA of repo-local `hostops/<job-id>`; full runner-user filesystem permissions apply |

No GitHub App `workflow_dispatch` action is needed; the existing connector can comment on Issue #82 using the authenticated owner identity. Any other comment author or any other Issue is skipped. A public repository does **not** automatically make arbitrary comments authorized to run host commands.

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
