# Torrent TV P3/P4 R0–R2 source repair — 2026-11-16

## STATE_RECONCILED / provenance

- Repository: `trung-via/torrent-tv-vietsub` (PUBLIC at audit time).
- Merged `main`: `ad853ebd5acdbb1e16656bde8da3c68950d0de2c` at R0 inspection.
- Integrated TV + Owner **candidate**: Draft PR #162 at `e3520dda28b49be9df96f8459edee0800edf9a2a`.
- Owner V2 offline activation **candidate**: Draft PR #167 at `3762d9f00ea149e84ebc54835dade378c4a4be17`, this repair's parent.
- Source-only, stacked candidate: `feature/p3p4-r0-r2-single-tap-20261116`.
- Existing required per-film consent: Issue #157, TV PR #159, owner PR #160. Do not authorize discovery, OpenSubtitles or Gemini on Play/Next.
- Human report: integrated PC runtime has READY heartbeat, `P3_STATE_FRESH=MISSING`, zero accepted P3 HTTPS statuses, TorrServer TCP reachable but selected metadata unverified. **Not** a demonstrated pair/TLS root cause.
- No APK install, PC restart, Windows Task, new listener, ADB pairing, real provider or movie-content write was performed by this change.

## R1 — one primary TV action, with existing authenticated trust

1. The existing **Bật Vietsub AI** menu action now tries the one-shot *already staged* private Owner-PC bootstrap, enables P3 metadata signals, and issues the signed per-film REQUESTED event in order. The existing bounded P4 activation retry later waits for a verified subtitle source. Only this explicit button grants per-film discovery/translation consent.
2. **Tắt Vietsub AI** clears the per-film intent, pending retries and metadata signal. OFF/OTHER manual native selection remains authoritative; Play/Next alone do not authorize any provider call.
3. The redundant standalone **Bật tín hiệu tự tìm Vietsub** toggle is removed. Optional **Ngắt ghép đôi PC Vietsub AI (nâng cao)** is visible only when a paired PC identity exists, clears P3 consent before AndroidKeyStore revocation and does not serve as a prerequisite step.
4. The Windows one-time ADB bootstrap helper no longer mistakes an old `adb-staged-v1.receipt` for proof of *current* TV pairing. A deliberate local rerun can restage the private one-shot bootstrap after owner/TV approval. **A revoked key cannot reappear magically**: if TV has no valid local trust and no owner-staged private bootstrap, the single-button action stops and gives safe re-pair instructions. No unauthenticated discovery or new network pairing endpoint is introduced.
5. Unify the exact 40/64 lowercase hexadecimal torrent identity used by P3 signed selection/state, native G1 mediaKey and PC P4 mapping. The key derivation itself remains unchanged.

## R2 — inspect the next blocked gate without inventing proof

- A **new companion**, `p3_p4_triage_readonly.py`, prints only `TTV_P3P4_NEXT_GATE=<fixed code>` based on already collected private in-process status and bounded HTTPS counters. The SHA-pinned Owner V2 runtime and deployment scripts remain byte-for-byte unchanged.
- When the owner is READY, P3 fresh state is MISSING and all state accept counters are zero, the next gate is **MEASURE_TV_PAIRING_TLS_AND_SIGNAL_PATH**. That observation cannot discriminate TV turned off, bad pairing, blocked LAN/TLS, unreachable PC or absent user tap.
- When signed state becomes FRESH_REQUESTED and TorrServer remains `TCP_REACHABLE_METADATA_UNTESTED`, verify exact selected-file `POST /torrents` metadata bound to signed TV hash/index; do not treat TCP connect as successful metadata verification.
- Do not disclose media filenames, infohashes, local PC address, tokens or subtitles in PUBLIC PR/CI logs. The real provider and end-to-end TV gates stay NOT_RUN.

## Acceptance and handoff

- Source: fail-closed P4→P3 patch application, single menu action, native 40/64 identity, signed HMAC/replay/negative tests, one-shot restaging contract, owner fixed-code diagnostic triage.
- CI: hosted source/mock tests on **exact new PR HEAD**, no Windows self-host/ADB/TV. A Windows Android `assembleDebug` and exact APK SHA must be checked separately on an authorized dedicated runner.
- Field, only after separate scoped authorization: bind correct APK/SHA and trusted owner/task identity; run read-only `owner_p3_p4_diagnostics.py --owner-root <private-root>` and optional `p3_p4_triage_readonly.py --owner-root <private-root>`; confirm paired HTTPS status acceptance increases after one actual TV click; independently bind TorrServer selected metadata; ensure no provider call from Play alone; observe P4 no-picker cue rendering, OFF/OTHER, A→B→A, seek/pause/audio.
- Merge policy: Draft/HOLD pending independent Brain exact-HEAD/base review, applicable CI, and physical proof when required by Issue #42. This PR alone does not satisfy G4/release.
