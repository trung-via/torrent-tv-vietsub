# G1 Production Vietsub — user-selected external SRT/VTT (source-only Draft)

**Status:** `G1_PRODUCTION_SOURCE_DRAFT / BUILD_UNVERIFIED / REAL_REDMi_UX_UNVERIFIED / RELEASE_UNVERIFIED`  
**Date:** 2026-10-27. **Authority:** Human agreed to proceed after P0 Windows TorrServer→Redmi one-pass smoke **Human PASS** (PR #37). `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, ADR-0006 and `planning/P1A-ACCEPTANCE-CRITERIA-20261025.md` remain authoritative. This is a **source-only implementation candidate**, not permission to build/CI, alter Windows, install on Redmi, merge or release.

## Purpose and isolation from G1c debug PoC

The G1c PoC in Draft PR #29 proves a debug-only ADB-delivered SRT with a debug source-set registry, while the **real product** requires users to select their own subtitle without a test marker and preserve ON/OFF per exact film/episode. The new `P1ProductionSubtitles.kt` is deliberately copied to **Android `src/main/java`** (compiled in **both debug and release variants** when the patch is successfully built), rather than activating G1c's `src/debug` marker. Do **not** layer both prototypes over the same OMP checkout or merge the old debug hook into a production APK without an explicit migration review.

This Draft branches directly from repository `main`; it is not stacked on PR #29–#37 and changes no existing OMP upstream or application installed on TV.

## First bounded user experience

1. With a supported OMP profile and lawful media playing through **explicit VLC engine** (not Auto or Built-in), open player menu using TV remote. The proposed rows are **Chọn SRT/VTT rời...** and, when an association exists, **Xóa SRT/VTT đã lưu**.
2. `ActivityResultContracts.OpenDocument` opens the Android system document provider. The user chooses an SRT or VTT themselves; the application does not browse SMB, launch a crawler or silently import from a torrent. On a TV without a compatible Android DocumentsUI/provider, mark **PICKER_BLOCKED**. Do not bypass using ADB or request storage-all-files privileges.
3. Only a strict UTF-8 document (no invalid byte sequences or NUL, at most **256 KiB**, SRT cue or VTT `WEBVTT` header/timestamp) is copied to app-private storage. The **original URI** and raw server URL/credential, torrent hash, media title, or provider filename are **not** persisted. Storage path is derived from a SHA-256 identity digest plus subtitle content checksum; no arbitrary filesystem path accepted from a document.
4. The association key requires `serverProfileId` from OMP's saved profile, a well-formed torrent hash, and nonnegative file index; any missing identity is fail-closed. On reopening, the source prepares `SubFile(file://...)` for that specific queue item only, verifies checksum and reselects the remembered **ON** choice. Existing remote subtitle menu handles **OFF** / selecting an embedded or other track, stored separately.
5. The first slice intentionally **does not live-add** during playback. The native overlay says **mở lại phim** after selecting/removing a file. Audio and video are not restarted by the picker callback.
6. Missing or modified/unreadable associated files cause a **generic nonblocking warning only if this exact media had saved ON**, without exposing path/content/credentials or inserting damaged subtitles.

## Files in this Draft

| Path | Responsibility |
| --- | --- |
| `poc/g1-prod/P1ProductionSubtitles.kt` | Release-capable per-media SHA-256 association, read-limited content-provider import, SRT/VTT UTF-8 validation, app-private copy, OFF/OTHER/ON selection and read/verify on reopen |
| `poc/g1-prod/apply.ps1` | **Not executed.** Source patcher guarded by pinned clean OMP upstream and submodule SHAs + four exact upstream file blobs + helper blob + disposable checkout folder. Patches `src/api/torrserver.ts`, `src/player/nativePlayer.ts`, `NativePlayer.kt`, `PlayerActivity.kt`; copies helper into `android/app/src/main/java/com/spacesarmat/omp/player`. |
| `poc/g1-prod/README-G1-PRODUCTION-DRAFT.md` | Scope, review, acceptance boundaries |

**Upstream pins:** `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, submodule `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`. Upstream's `VlcEngine.addNextSlave()` already consumes a `SubFile` whose URL is `file://`; we use its *pre-open* path and do not rewrite VLC.

## Mandatory review before any execution

- **Compile & integration (currently UNVERIFIED):** independent, separately authorized isolated OMP build on the **dedicated app runner**, first static patch/parser verification, then `npm ci` / `android:sync` / `assembleDebug testDebugUnitTest` (not `assembleRelease` yet), compile both variants if the reviewer authorizes. Check correct source-set and AndroidX Activity Result dependencies. No AIOS-renew runner fallback.
- **Functional matrix (one consolidated Human TV cycle after build, not UX01–05 rerun):** open-picker availability and focus/Back; SRT UTF-8 Vietnamese diacritics; separate VTT case; restart A preserves ON; select OFF → reopen A remains OFF; select embedded/OTHER → reopen does not force G1 ON; B without imported subtitle remains unaffected; import/remove and reopen A; mismatched profile/hash/index; malformed/oversized/invalid UTF-8; file inaccessible when ON shows only generic warning; D-pad/AV/seek remain usable.
- **Isolation/security:** do not reuse sensitive G1c debug saved registry, never persist content URI or raw key fields, no user-controlled path traversal, no unapproved broad-storage permission, no URL credential leakage, never auto-import. Documented `ActivityResultContracts.OpenDocument` *may be unavailable on this Redmi firmware*; keep it BLOCKED until observed. Provider copy may fail; no global permission should be requested.
- **Production Release:** previously observed G4 unsigned audit validates debug **absence** only for the old PR29 candidate. A new product release must be audited again and must intentionally contain this **user-facing production import** while not containing G1c debug-only hooks, fixtures, settings or warnings. A source-level main placement is **not** binary or TV PASS. Existing GPL attribution/security/credentials gate remains open.

## Known first-slice limitations

The importer is a new draft implementation, **not yet compiled or manually tested on the Redmi**. The first validation recognizes timestamp patterns but is **not a complete formal SRT/VTT grammar validator**; malicious/unusual subtitle text requires fuzzing/security review. Import currently accepts generic provider MIME matches, validates file **content** rather than trusting extension. No hot add, SMB, phone transfer, source search integration, Android TV document-provider fallback, TV language-wide i18n, subtitle font styling, cue-sync G3 or migration of a G1c debug selection. Persistent `file://` access by the release engine is a **hypothesis to test**, informed by G1c debug success only. Old G1d 5/5 error fixtures and P0 server smoke are already PASS **on their old scope** and should not be repeated unless a regression requires it.

## Definition of next decision

Review source and pin all commits; if accepted, **separately authorize one build+test batch** on the dedicated app runner. Only after a compile PASS may Human try the resulting APK on Redmi, following a guarded keep-data install that **does not overwrite the existing PR29 debug APK without explicit authorization**. If file picker is unavailable, do not modify Windows shares/firewall or silently broaden permissions; return a P1b transport-choice proposal instead.

**Stop:** no PR merge, GitHub Actions dispatch, Windows/TV/ADB state changes, credential collection, automatic file transfer, production APK or G1 overall E2E PASS within this Draft.
