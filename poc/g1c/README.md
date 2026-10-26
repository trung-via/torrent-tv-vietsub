# P1a-G1c — Debug-only media-bound external SRT persistence PoC

**State:** `PATCH_PREPARED / PROPOSED_HOW / KOTLIN_TS_BUILD_UNVERIFIED / REAL_TV_UNVERIFIED / G1C_PARTIAL_SCOPE`  
**Date:** 2026-10-26  
**Parent:** PR #17 (G1b real Redmi: Human-confirmed 3/3 external SRT track/cues), PR #16 (G1 plan), PR #15 (P1a AC), ADR-0006.  
**Pinned OMP:** `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`; **2160player:** `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`.

## Proven identity path — source audit

- `src/store/servers.ts`: `SavedServer.id` is generated once when adding a TorrServer profile and stored in `tsp.servers`. Its `client = new TorrServerClient(activeServer.value)` passes a SavedServer to the client. It is stable while the profile exists; removing/readding changes ID.
- `src/api/torrserver.ts`: `ServerConfig` and `TorrServerClient` originally use URL/user/password and **do not carry/expose the SavedServer.id**. G1c patch adds optional ID, exposed as `profileId`; no URL/auth is used as identity fallback.
- `src/player/nativePlayer.ts`: `toNativeQueue` already forwards `hash` and `fileIndex` for each `PlayItem`. G1c adds the selected client's `profileId` to the existing `playNative` call.
- `NativePlayer.kt`: adds optional `serverProfileId` to `PlayRequest`, parsed from native JSON. `PlayerActivity.load` consults the debug-only registry before `PlayerSession.load`.
- Fail closed when server profile ID is missing/invalid, torrent hash isn't exactly a 40-character hex v1 infohash, or fileIndex is missing/negative. **No mapping by title, film name, SRT filename, stream URL, magnet or credential.** BT v2 (64 hex), standalone videos and uncertain identity are **outside this PoC**, not silently mapped.

## Behavior and limitations

1. **Registration once:** the known independent file `files/p1-g1-external.vi.srt` must still exist on the TV from authorized ADB import. With VLC explicitly chosen and the correct target film/torrent file selected, the operator creates the distinct debug marker `files/p1-g1c.register`. On load, the marker is consumed, SRT is strictly checked (readable regular file, 256 KiB cap, UTF-8, at least one SRT cue) and its SHA256 is saved under a SHA256-derived media key in app-private Android `SharedPreferences`.
2. **Restore without marker:** subsequent play requests with the exact same `SavedServer.id + hash + fileIndex` can add `SubFile("P1 G1c - Saved SRT", ext="srt", lang="vi")` before VLC opens. Checks the file content SHA256 still matches. No test marker is needed or recreated at reopening.
3. **Wrong episode:** queue entries lacking a matching association receive no G1c `SubFile`. Different fileIndex, torrent hash or server profile must not inherit it. A changed/missing/corrupt SRT is rejected safely.
4. **Storage:** `SharedPreferences` only, no backend/DB, SMB, phone, network changes, broad Android storage permission or source file packed into APK. Persistent keys are SHA256 of structured identity and values are SRT SHA256; raw hash, stream URL, magnet and credential are never persisted/logged by this registry. **One external file path is supported** for this bounded test; changing that file invalidates an earlier association by content hash.
5. **Debug/release isolation:** `src/debug` registry does all reads/writes; `src/release` is no-op. The minimal ID wire-field exists in both variants but release has no SRT-association behavior. G4 still requires release binary artifact inspection.
6. **Track selection not solved:** saved **association** does not necessarily preserve whether this external track was selected or OFF by the user. This is a bounded **G1c mapping** experiment, not yet complete G1c acceptance or `EXTERNAL_SRT_E2E_PASS`. Test ON/OFF state restoration separately; do not force English/other tracks or auto-enable subtitles without proof.
7. **No production importer:** registration is ADB/debug-only, not an in-app subtitle picker. G1d error UX, multi-file real usage, BTv2 and VTT remain separately scoped.

## Files in this repo

- `poc/g1c/P1G1CSubtitleRegistry.debug.kt` — strict file verification; per-media hash key; `SharedPreferences` registration/replay.
- `poc/g1c/P1G1CSubtitleRegistry.release.kt` — no-op release class.
- `poc/g1c/apply.ps1` — pinned clean OMP+submodule preflight, narrowly patches four known upstream files, copies only the two source-set helpers. **No build**.
- `poc/g1c/verify.ps1` — structural checks and `git diff --check`, not compiler or device proof.
- `poc/g1c/build-on-runner.ps1` — reuses proven dedicated Torrent TV Windows runner toolchain, clones immutable OMP/2160 to `RUNNER_TEMP/p1-g1c-RUN_ID-ATTEMPT`, applies G1c in the **clean disposable checkout**, runs TypeScript compile in `npm run android:sync` + Android `assembleDebug testDebugUnitTest`, inspects each APK's ZIP entries for absence of external/legacy SRT assets, emits SHA256SUMS and sanitized evidence; only invoked by a separately reviewed **manual workflow**, never automatically.

`apply.ps1` must run only on a new disposable clean upstream worktree (not layered atop previously patched G0/G1b OMP); G1b's PoC still exists separately in PR #17, with distinct filename, label and marker.

## Verification / acceptance matrix for a future authorized G1c APK

| Case | Check and expected observation | Gate |
| --- | --- | --- |
| ID-01 | Exactly one server profile ID survives UI → TorrServerClient → native PlayRequest | Static/TS/Android instrumentation |
| ID-02 | Absent/invalid profile ID, malformed torrent hash or missing fileIndex → NO association | Unit / negative |
| MAP-01 | Register G1 SRT on known legal film/torrent file; marker consumed once; SRT loaded | Real Redmi |
| MAP-02 | **Without any G1b/G1c marker**, close/relaunch same film → saved external SRT appears in menu, renders right cue | G1c core; real Redmi |
| MAP-03 | Same torrent, **different fileIndex** → no SRT inheritance | Wrong-episode |
| MAP-04 | Different torrent hash / server profile → no SRT inheritance | Wrong-title/server |
| MAP-05 | Missing, modified, invalid encoding or malformed SRT → safe fallback, no crash | Negative; no promised UX yet |
| SEL-01 | Remember exact selected external track vs OFF across restart, including embedded if available | **NOT IMPLEMENTED / BLOCKED_FOR_FULL_G1C** |
| AV-01 | Play/pause, seek ±, resume, picture/audio, remote controls | AC-04/05 real Redmi |
| REL-01 | Release build no debug registry behavior or fixture | G4 separate |

Every test reports PASS / FAIL / UNVERIFIED or NOT_APPLICABLE with source SHA, APK SHA and sanitized evidence. A debug marker that silently re-adds SRT on reopen is **not** acceptable proof of persistence; `MAP-02` explicitly requires marker OFF.

## Stop conditions and next authorization

- **STOP** on identity uncertainty, source/submodule SHA mismatch, dirty worktree, unapproved runner, no target TV permission, wrong-episode association, secret-bearing logs, unapproved Windows/TV changes, or new services/SMB.
- Future build requires a separate manual-only, pin-reviewed GitHub Actions workflow with app-runner authorization (existing G1b workflow on main remains **pinned to G1b**; do not reuse it to claim G1c). No automatic dispatch, merging or official AIOS task.
- Rollback: discard disposable patched OMP tree; keep G1c PR Draft. A real-world uninstall or data clear would delete `SharedPreferences`; do not do either without Human authorization.

**Decision needed for completion:** after media-bound reopen is demonstrated, implement/verify exact selection restoration (external ↔ OFF ↔ embedded) before declaring full G1c or G1 E2E PASS. Typeface styling remains deferred.
