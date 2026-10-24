# Agent contract for `torrent-tv-vietsub` — OMP-based

Mandatory before any code mutation:

1. Read `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, and ADR-0001/ADR-0002.
2. Confirm target Git root, branch, upstream OMP commit and submodule pin; NEVER mutate `AIOS-renew` as part of this app task.
3. Check actual file/repo state; mark TV/server results UNVERIFIED without real evidence.
4. Operate only within authorized task scope. No implicit repo publishing, CI enabling, Windows firewall/services/startup changes, WAN exposure or credentials.
5. Use **OMP TypeScript/Preact + Capacitor UI, Kotlin native 2160 Player/AndroidX Media3 and VLC** as the target baseline; NOT a new Compose for TV app in P0.
6. **Retain OMP website torrent source-search adapters and user-configured legal sources**. Do not disable/remove them as a side effect of reducing paid-service/billing modules. Do not create unauthorized scrapers, run piracy catalogs, bypass DRM or collect passkeys.
7. Windows TorrServer remains an external LAN streaming server; no torrent engine/third-party server binary embedded in APK.
8. Prefer small, testable, reversible patches. Audit GPL and credential exposure (userinfo stream URLs/Basic Auth) before release. Build/mock tests do not prove real-device PASS.
9. Honor AIOS canonical admission/review only when explicitly authorized, not guessed TASK aliases. `OMP-EVAL-001` is planning only; `TVAPP-001` is superseded.
10. No automatic AIAS? No: do not change AIOS governance, run its internal suites, auto publish, or dispatch from app documents.

Outputs: changed files, verification/evidence, explicit blockers, next handoff. See `chatgpt/PROJECT_INSTRUCTIONS.md`.
