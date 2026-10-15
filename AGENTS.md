# Agent contract for `torrent-tv-vietsub`

Mandatory before any code mutation:

1. Read `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, and relevant ADRs.
2. Confirm Git root and branch; NEVER mutate `AIOS-renew` as part of this app task.
3. Check actual file/repo status. Mark device/server claims UNVERIFIED unless real evidence is provided.
4. Operate only within the authorized task scope. No implicit repo publishing, CI workflow enabling, Windows firewall/services/startup changes, external Internet exposure, or credentials.
5. Use Kotlin + Compose for TV + Media3 for the app; integrate externally managed TorrServer via isolated adapter, not a reimplementation of BitTorrent.
6. Prefer small, testable patches. Fail explicitly with categorized reason. Mock/emulator tests do not establish TV/server real-world PASS.
7. Follow AIOS canonical task authority when explicitly dispatched, not guessed task numbers or historical repo snapshots.
8. Respect copyright, third-party licenses and restrictions on illegal scraping and DRM circumvention.

Outputs: changed files, verification run, evidence limitations, unresolved blockers, next explicit handoff. See `chatgpt/PROJECT_INSTRUCTIONS.md` for conversation-wide instructions.
