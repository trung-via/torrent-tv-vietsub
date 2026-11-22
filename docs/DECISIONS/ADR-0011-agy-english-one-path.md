# ADR-0011 — One TV request → AGY OpenSubtitles EN → AGY VI → VLC

**Decision:** Human, 2026-11-22. Source implementation candidate in Draft PR #179; not a deployed Owner/Redmi acceptance.

## The one active path

1. **TV:** One explicit `Bật Vietsub AI` tap sends signed current session, selected TorrServer torrent/file index and exact filename to the existing Owner P3 inbox. Playback, pause or a background status tick never initiates AGY on its own.
2. **Owner:** Verify signed request, selected-file identity and consent. For an already verified per-film English SRT, reuse the existing private cache and translation checkpoints; otherwise hand the film identity and non-secret release hints to **one AGY acquisition task**.
3. **AGY:** Independently choose a permitted way to find/download the **matching English timed subtitle on OpenSubtitles.com**. No hardcoded `GET /subtitles`, `POST /download`, VI-first policy, download ranking algorithm, local MKV extraction or OpenSubtitles API key is required in this active path. AGY writes only `english.srt` in its isolated task directory. If the site requires account access, quotas or an API key, AGY must use already authorized access or fail honestly; no login/CAPTCHA/paywall bypass.
4. **Owner → AGY → TV:** Validate original OpenSubtitles page, English release/movie/episode match, SRT byte size/UTF-8/cues/timestamps. Persist an exact-file `ai_en` cache receipt, use the **existing AGY LEAN120** worker for EN→VI with resumable checkpoints and cumulative P4 revisions, and deliver with the **existing** paired P4/G1/G2 VLC path. Never create a parallel translator, receiver, player or queue.

The model decides *how to search*; code validates *what was acquired*. Source-page and release-name evidence plus timed-text checks prevent obvious wrong-film uploads; they do not prove frame-perfect lip sync. Final synchronization must still be observed on the real Redmi. If the requested release cannot be matched, the result is `REVIEW_REQUIRED`, not an invented subtitle. Failed/unknown provider effects remain blocked without blind repeated downloads or model calls.

**Preserve:** A/B background translation independence, old completed caches, per-film IDs, saved checkpoints, OFF/OTHER preventing new work, outdated TV sessions preventing P4 delivery, signed LAN pairing and existing APK/app/Owner data. A finished A translation remains cached even when its TV session is no longer current.

**Inactive compatibility:** Previous local VI/EN, dual-source and OpenSubtitles REST modules may remain in source for test/rollback, but `build_owner_auto_flow` now wires only the agent-acquisition path when uncached. Do not expose the downloaded-VI option as a second `Bật Vietsub AI` branch.

## Operational and evidence boundaries

- The AGY CLI runs under the signed-in Owner's Windows account using `--mode auto --sandbox`, with a temporary task directory and no `--dangerously-skip-permissions`. Google documents that the sandbox denies outbound network access by default unless allowed by `read_url` permissions. The Owner must already have permitted OpenSubtitles web access through its AGY account/settings; if absent, a one-time Owner/HostOps enrollment is needed. Do not change global permissions or perform unrestricted machine shell operations automatically.
- This is a **source-only** change. Offline tests use fake AGY runner/files, never a live OpenSubtitles download, real provider translation, Windows task restart, Android reinstall or TV acceptance.
- Rollout after exact-head independent review: verify that current Windows Owner has no unknown active paid jobs; stage source manifest including the new module and checked hashes; restart only when safe; verify CLI browser/network capability under actual Owner user; then one on-TV real-film tap and inspect AGY match, P2 checkpoints, signed P4 frames, and VLC visible/subtitle timing. Never delete caches or `*.inflight` during upgrade.
- Follow official OpenSubtitles terms, download quotas, usage rights and limits. Source artifacts contain no subtitle content, passwords or personal LAN identifiers.

**Supersedes for active AI route:** #170 VI-first and #179 parallel downloaded-VI candidate routing. Does not undo their historical decisions or discard saved media/subtitles.
