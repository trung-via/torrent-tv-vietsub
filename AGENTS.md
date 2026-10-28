# Agent contract — Torrent TV Vietsub (independent)

**Project identity:** `trung-via/torrent-tv-vietsub`, independent from AIOS. No AIOS canonical TASK, Brain Sync, NEXT, admission, executor, reviewer, dispatch, Runtime, runner or workspace.

## Mandatory before mutation

1. Read `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/DEVELOPMENT_WORKFLOWS.md` and current ADRs, especially ADR-0001/0002/0006/0007. Check GitHub branch/commit and open Draft PRs; older uploaded snapshots are not authoritative.
2. Confirm target repo/branch/worktree and task scope. Prefer branch + PR; no direct `main` rewrite, auto merge or publish. Do not modify `AIOS-renew` or other AIOS repos in this task.
3. Use only Torrent TV GitHub Actions and dedicated self-hosted runner/workspace/credentials. Verify actual runner identity, labels, path and permissions before authorized run; never fallback to AIOS runner. Workflow YAML is not proof of online/pass.
4. **Selective reuse only:** if copying code/script/workflow from AIOS, record exact source commit/path/license, file diff, security/secret review, dependencies, local adaptation and rollback. Do not import AIOS runtime, task transport or canonical governance.
5. Keep OMP TypeScript/Preact + Capacitor UI and Android Kotlin native 2160 Player/Media3/VLC baseline. Windows/NAS TorrServer is external over trusted LAN. No Compose rewrite or torrent engine inside APK in P0.
6. Preserve OMP website torrent source-search adapters and manual magnet/.torrent for **lawful/user-authorized sources**; do not add unauthorized scraping, piracy catalogs, DRM bypass or background crawling.
7. Vietsub: UI `vi`, track `vi/vie`, UTF-8 SRT/VTT. Respect ADR-0006 G0/G1/G2/G3/G4 evidence split; no claim real TV/server PASS from source/mock.
8. Agent/gateway/search ranking and AI voice-over are **proposed phased features**, not implemented capabilities. Require explicit confirmation for side effects, device pairing/auth, consent, legal media, cost and real E2E evidence.
9. No implicit GitHub workflow execution, runner service install, Windows firewall/SMB/router/WAN change, TV root/ADB change, credential use, APK signing or release. Ask for operational approval when required.
10. Audit GPL/license, OMP URL credential/userinfo leakage, secrets/logs and supply chain before import/distribution. Stop on unclear rights or environment.

## Evidence labels

`DECIDED`, `PROPOSED`, `UNVERIFIED`, `BLOCKED`. Use `BUILD_UNVERIFIED`, `RUNNER_UNVERIFIED`, `REAL_TV_UNVERIFIED`, `REAL_SERVER_UNVERIFIED`, `EXTERNAL_SRT_E2E_UNVERIFIED`, `AGENT_E2E_UNVERIFIED` when proof is missing.

## Output

Report changed files, diff intent, exact tests/evidence, blockers, compatibility with open PRs and next handoff. Do not invent workflow runs, successful builds or device results.
