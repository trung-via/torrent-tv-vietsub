# P1a G1b — Outside-APK SRT rendering probe (debug-only)

**Status:** `PATCH_PREPARED / STATIC_REVIEW_ONLY / ANDROID_BUILD_UNVERIFIED / G1B_REAL_TV_UNVERIFIED`  
**Type:** proposed small, reversible PoC. Not G1c persistence, production importer, approved APK release or AIOS TASK.  
**Parent:** planning PR #16, source-agnostic AC PR #15, G0 evidence PR #11.  
**Source:** immutable OMP `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` + 2160player `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`.

## Why this PoC is intentionally small

GitHub G0 built an SRT *from the APK asset*. Human ADB evidence separately proves that `p1-g1-external.vi.srt` can be transferred into the debug app's private storage with **145 bytes / matching SHA256**. The G0 APK does not reference this outside-APK file. This patch supplies one debug-only seam to read that existing file and pass it to the existing `QueueItem.subtitles -> PlayerSession -> VLC addSlave` path.

**No G1 SRT asset is present in this branch or built into the APK.** No SMB/SAF picker, phone companion, new backend, database, firewall, Windows service, permissions, AI subtitles or typography patch.

## Behavior, proof boundary and limitations

- Only if `PlayRequest.engine == EngineMode.VLC`, current queue index is valid and `filesDir/p1-g1.enable` exists, inspect `filesDir/p1-g1-external.vi.srt`.
- Validate regular readable file, cap at 256 KiB, strict UTF-8 (no replacement fallback) and the existence of an SRT timestamp cue. This is a **basic** sanity check, not a fully compliant SRT parser or a user-visible error system.
- Add `SubFile(url=file://..., label="P1 G1 - External SRT", ext="srt", lang="vi")` to **only the current item**, before `PlayerSession.load`. Engine and track menus are reused, not modified.
- Consume the enable marker **once** upon a valid registration. This prevents another reopen from being mistaken for persistence and makes any missed injection visible. If a file fails validation or the marker cannot be deleted, no subtitle is injected; existing media playback request is returned unchanged. No user media URL, hash, file path or credential is logged.
- `src/release` implementation is a no-op; `src/debug` alone contains the file reader/marker logic. G4 still needs a real release APK artifact inspection before any distribution.
- **A passed G1b would prove only external-file rendering**, not reliable reopen or storage of subtitle preference. G1c requires a separate durable media association implementation, with the injection OFF, the exact identity binding validated, and user-visible error handling. This patch deliberately does **not** pretend to satisfy G1c/G1d or full `EXTERNAL_SRT_E2E_PASS`.
- With the marker ON, the operator is responsible for opening the intended *lawful* video/torrent. This diagnostic doesn't establish a per-media key. Stop if identity is ambiguous. After the marker is consumed, navigating to another queue item does not inherit the injected file.

## Files and intended diff after apply (do not execute without permission)

| File in this repo | Destination in disposable pinned OMP worktree |
| --- | --- |
| `poc/g1/P1G1SubtitleProbe.debug.kt` | `android/app/src/debug/java/com/spacesarmat/omp/player/P1G1SubtitleProbe.kt` |
| `poc/g1/P1G1SubtitleProbe.release.kt` | `android/app/src/release/java/com/spacesarmat/omp/player/P1G1SubtitleProbe.kt` |
| `poc/g1/apply.ps1` | Checks pins, Git state, dedicated runner and patches exactly one `PlayerActivity.load()` call |
| `poc/g1/verify.ps1` | Static review only: guards, no G1 asset bundled, release no-op |

A single source call-site is modified: `session.load(r, next)` → `session.load(P1G1SubtitleProbe.prepare(this, r), next)`. Refuses to overwrite the existing G0 seam or any dirty OMP clone. Do not apply this patch atop G0; use fresh, clean, disposable pinned OMP checkout. The app repo `main` remains docs-first.

## Build/hardware verification handoff (not authorized by this file)

1. Fresh-check app repo Git SHA, G1 draft PR head/base, OMP/submodule pins, source/license/security, dedicated runner registration/isolation and human execution rights. Never fall back to the `AIOS-renew` runner or assume a canonical AIOS dispatch route.
2. In a **separately authorized session** on a clean pinned OMP worktree, run `poc/g1/apply.ps1 -OmpRoot <WORKTREE> -AppRepoRoot <APP_REPO>` followed by `poc/g1/verify.ps1 -OmpRoot <WORKTREE>`. The scripts have no workflow trigger and do not initiate a build.
3. Only after explicit build authorization: npm/Android sync, Gradle `assembleDebug testDebugUnitTest` on the **dedicated application runner**, verify APK SHA256, ABI split, package ID and that APK has **no** `p1-g1-external.vi.srt` asset. Inspect G4 using a release artifact in a distinct gate.
4. Only with authorized Redmi ADB/install access: verify connected `MiTV-ASTR0`, API 30/Android 11, ABI `armeabi-v7a` and compatible APK. Preserve the externally copied SRT and its SHA256; if install removes app data, transfer the file again using the already verified ADB method. Do **not** assume `adb install -r` guarantees the old private file is kept without checking.
5. Verify marker `p1-g0.enable` is **OFF**. Create `p1-g1.enable` only just before opening the selected rights-cleared video with **VLC explicitly selected**; keep the 145-byte external file in `filesDir`. The one-shot G1 marker should be absent after a successful prepare invocation. Observe the media playhead at 00:00:03 and 00:00:12; select `P1 G1 - External SRT` using D-pad; verify Vietsub cues, picture/audio, Pause/Seek/Resume. Record real-TV evidence with sensitive metadata redacted.
6. Restart the same media **without re-creating** `p1-g1.enable`. This patch must NOT automatically reattach the file; report `G1C_PERSISTENCE_UNIMPLEMENTED`, **not** `EXTERNAL_SRT_E2E_PASS`. Check that a different episode doesn't inherit the file. Run invalid UTF-8 / missing file smoke tests separately and keep error UX as `G1D_UNVERIFIED`.
7. Stop on source pin mismatch, file access/codec failure, wrong track/episode, unexpected audio behavior, private content disclosure, permission/runner mismatch or a request to add SMB/Windows network changes. Rollback by discarding the disposable OMP worktree. No merge, release, public upload, AIOS TASK or workflow dispatch is implied.

## Evidence checklist

`G1_TRANSFER_HASH_PASS` is already Human-supplied. Everything following requires separate evidence: `G1B_ANDROID_BUILD_UNVERIFIED`, `G1B_EXTERNAL_RENDER_UNVERIFIED`, `G1C_PERSISTENCE_UNIMPLEMENTED`, `G1D_ERROR_UX_UNVERIFIED`, `G4_RELEASE_ISOLATION_UNVERIFIED`. Build logs/mock/stub tests are not real-TV PASS. For final P1a, apply AC-01..06 in PR #15 and preserve ADR-0006 G0..G4 boundaries.
