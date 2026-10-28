# ADR-0003 — Dedicated Git repository, workspace and self-hosted runner

**Historical status:** `ACCEPTED_RUNNER_ISOLATION / AIOS_DISPATCH_CLAUSES_SUPERSEDED_BY_ADR_0007`.  
**Current authority note (2026-10-28):** ADR-0007 xác định Torrent TV Vietsub độc lập hoàn toàn AIOS. Mọi đoạn bên dưới nói AIOS có thể giữ canonical governance, admission hoặc dispatch tới runner ứng dụng chỉ còn là **bối cảnh lịch sử, không được dùng làm yêu cầu thực thi**. Yêu cầu repo/workspace/self-hosted runner riêng vẫn còn hiệu lực. Xem [ADR-0007](ADR-0007-independent-project-and-selective-reuse.md).

**Decision:** ACCEPTED — reaffirmed directly by Human on 2026-10-25 in this project conversation.  
**Implementation:** UNVERIFIED — repository exists; runner registration/online, workspace and dispatch bridge have not been independently proven.  
**Scope:** infrastructure/execution for `trung-via/torrent-tv-vietsub`; complements ADR-0001 (Windows/NAS TorrServer) and ADR-0002 (OMP app).

## Context

Human had already decided Torrent TV Vietsub should have an independent repository, independent workspace, and independent runner. Prior OMP-EVAL planning referenced AIOS cross-repo execution in a way that could be misread as using `AIOS-renew`'s runner or Runtime worktree. That is not the authorized product architecture.

## Human decision (DECIDED at 2026-10-25; see supersession note above)

1. `trung-via/torrent-tv-vietsub` is a separate PRIVATE GitHub repository with its own Git root and history.
2. App development, build, verification and APK artifacts use a **dedicated Torrent TV Vietsub self-hosted runner identity** and an isolated Git workspace, not the `AIOS-renew` runner, worktree or Runtime state.
3. `AIOS-renew` retains only its own canonical governance/Brain/task admission authority where invoked. It is not automatically the app's execution environment. Its self-hosted runner, `.git/aios` runtime journal/locks and task transport state are not fallback infrastructure for the app.
4. Source import/build/CI/release may run only after proving correct runner identity, workspace isolation, Git permissions and authorized routing. No silent runner substitution, auto-dispatch, repo-publication or production release.

## Identity and boundaries (historical diagram, superseded where AIOS appears)

```text
AIOS canonical source (governance/admission if authenticated)
         | cross-repo dispatch bridge: UNVERIFIED
         v
Dedicated Torrent TV Vietsub runner (provisioned/online: UNVERIFIED)
         |
         v
Dedicated Torrent TV Vietsub workspace / Git root
         |
         +--> PRIVATE trung-via/torrent-tv-vietsub
         +--> isolated OMP clone/build/tests/APK
```

The dedicated runner's name, labels, executor toolchain, physical host, exact path and credentials were **not prescribed by this ADR**. Separate runner identity does not prove a different physical machine. Do not assume an AIOS origin/source/workspace/runner binding grants this new runner permissions.

## Verification gate (historical; current workflow authority is ADR-0007)

- Read-only evidence of runner registration/labels, access scope, online status and isolation, validated against actual target repo and host.
- Exact authorized target workspace root and Git remotes; ensure no shared AIOS Runtime journals/locks/credentials, no cross-repo mutation.
- Bounded harmless test on the **dedicated project runner** only when Human has authorized enabling/triggering it.
- Confirm that a lawful AIOS authoring/admission/dispatch mechanism can reach this runner; if not, report the integration gap, not an invented RUN/PRIMARY.
- Evidence states: `DEDICATED_RUNNER_UNVERIFIED`, `DISPATCH_BRIDGE_UNVERIFIED`, `BLOCKED` until specifically validated. `BUILD_UNVERIFIED`, `REAL_TV_UNVERIFIED`, `REAL_SERVER_UNVERIFIED` remain independent.
- Do not register a runner, install service, create workflows, change firewall/router/secrets or execute remote commands without separate operational authorization.

## Consequences (historical)

The project can evolve and build without sharing AIOS-renew's runtime/executor environment. Integration with AIOS may require an explicit supported cross-repo carrier or target-repo adapter. Do not implement a shortcut inside AIOS-renew to force it. Future changes to this separation require a new Human-approved ADR/diff.

**Current interpretation:** no AIOS integration is required or authorized for Torrent TV; use GitHub Actions/PR/runner owned by Torrent TV, per ADR-0007.
