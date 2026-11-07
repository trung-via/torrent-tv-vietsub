# G1+P2 Auto Debug after independent Torrent TV Brain PASS

**Date:** 2026-11-07. **Scope:** automatically start a **Debug source build** on the dedicated Torrent TV Windows runner after an accepted G1/P2-related PR is merged into `main`. This authorizes the build and tests only. It is NOT consent to make an APK public, install it, alter TorrServer, or release to users.

## Exact workflow

`.github/workflows/tv-g1p2-auto-debug.yml` listens to `push` on `main` **only for G1/P2 build-related paths** (including this workflow's first merge). A GitHub-hosted Ubuntu job must independently prove:

1. The push SHA is the **current main SHA**, and its first parent is the event's `before` SHA. This prevents builds from stale pushes or after another main update.
2. Exactly one *merged, non-Draft, same-repo PR* is associated with that exact merge SHA. Direct pushes, forks, unmerged/ambiguous PRs are HOLD.
3. The repository Owner's **latest four-line canonical Conversation verdict** is `TORRENT_TV_BRAIN_REVIEW_PASS_V1`, with that PR number, exact PR HEAD and event `before` base SHA. Missing/stale/edited-after-merge PASS or later HOLD is BLOCKED.
4. GitHub checks on that original PR head are all completed and successful, were produced by GitHub Actions, and at least one is named `TV Verified Code CI`. Incomplete/paginated/failed CI is BLOCKED.

Only then can the Windows self-hosted job run. It checks out the **same merged main SHA** with credentials persistence disabled, validates the source SHA and upstream repo/workflow/runner context, invokes the existing combined builder `poc/p2-source/omp-ui/build-g1p2-on-runner.ps1`, applies G1 then P2 on pinned OMP, runs P2 Vitest and Android Debug/Gradle unit tests, and records `SHA256SUMS-G1P2.txt` and `G1P2-BUILD-EVIDENCE.txt`.

The old `.github/workflows/p2-g1-combined-manual.yml` is **still manual and unchanged**, including its explicit public-APK-artifact confirmation. The builder supports two separately authorized routes; it does not fake `workflow_dispatch` when running on a push.

## PUBLIC repository artifact policy

The repository is currently **PUBLIC**. The automatic workflow uploads **ONLY checksum and build evidence text**, retained 3 days; it **never uploads APK binary**, creates a Release, or shares artifact with a third party. The Debug APK is built only in the dedicated runner's isolated temporary OMP checkout, subject to runner cleanup. No durable or private artifact transfer is asserted. A separate explicit decision is necessary for debug binary export if it would expose APK or secrets publicly.

## Independent gates

- `AUTO_WORKFLOW_SOURCE`: code present/merged on main.
- `BRAIN_PASS_AND_PR_CI`: GitHub-hosted verifier proves exact merged PR.
- `AUTO_WINDOWS_DEBUG_BUILD`: actual self-host job completed on the exact main SHA with Gradle/Unit PASS and SHA manifest.
- `REAL_REDMITV_G1P2`: separate Human-authorized device install/regression/UX. G1 5/5 belongs to **previous installed APK** only.
- `G4_RELEASE`: independently not authorized or proven.

The policy job does not execute on PR head on the Windows self-host. Pull-request policy CI only runs read-only Github-hosted tests. `concurrency` serializes automatic builds; obsolete main runs HOLD rather than building outdated source.

**Rollback:** revert or disable `tv-g1p2-auto-debug.yml` via reviewed main change. Does not affect original G1 or manual G1+P2 workflows. A push to change only unrelated docs will not start the auto-build because of the path filter.

**Known limitation:** a repo merge must carry a canonical Brain PASS and current CI provenance. If a merge lacks the expected review/CI, the automation fails closed (not silently manufacturing approval). Self-host runner readiness, APK SHA, G1 behavior on the new APK and device effects require actual evidence.
