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
| `poc/g1-prod/apply.ps1` | **Not executed.** Source patcher guarded by pinned clean OMP upstream and submodule SHAs + six exact upstream file blobs + helper blob + disposable checkout folder. Patches `src/api/torrserver.ts`, `src/player/nativePlayer.ts`, `NativePlayer.kt`, `PlayerActivity.kt`, `EngineSwitcher.kt`, `PlayerSession.kt`; copies helper into Android `main` and new `P1ProductionSubtitlesTest.kt` into Android `test`. |
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

## Human one-run Debug build authorization and manual dispatch (2026-10-27)

After the source-only Draft PR #38 was prepared, Human expressly answered **"ok đồng ý"** to the proposed **one G1 Production `assembleDebug testDebugUnitTest` batch on the dedicated app runner**. This approves the scoped build/check on the isolated worktree, **not TV installation, app-data migration, Release signing, merge or publication**.

**Implementation prepared, not dispatched:** Branch-only GitHub Actions variant at the **existing** default-branch workflow path `.github/workflows/p1-g1d-ux-pr29-manual.yml`. The source on the G1 branch is G1 Production, while **the same path on `main` remains the old PR29 Debug build**. The workflow requires `workflow_dispatch` from `feature/g1-production-sidecar-picker-20261027`, exact input `BUILD_G1_PROD_DEBUG_ONCE` and exact self-hosted Windows runner identity `torrent-tv-vietsub-win`; only checkout of the reviewed immutable app source commit `401f5bbda871e5ad96b39b83d750a6b3fbc56c7d`, not the current moving head.

The pinned `poc/g1-prod/build-on-runner.ps1` uses a fresh `p1-g1-prod-<run-id>-<attempt>` disposable OMP checkout under that runner's temp directory, verifies OMP/submodule SHAs, calls `apply.ps1` (six upstream blobs + helper/test hashes) then `verify.ps1`, performs `npm ci`, `npm run android:sync`, and `android/gradlew.bat assembleDebug testDebugUnitTest --no-daemon --console plain`. It inspects ZIP assets to reject G0/G1c fixture leaks, writes SHA256SUMS and limited provenance, and uploads `g1-production-debug-apk` **privately for seven days**. No ADB, install, signing, release, service or firewall change, AIOS dispatch or merge.

**One Human action in GitHub UI:**

1. Open [existing manual Actions workflow](https://github.com/trung-via/torrent-tv-vietsub/actions/workflows/p1-g1d-ux-pr29-manual.yml).
2. Choose **Run workflow → Use workflow from → `feature/g1-production-sidecar-picker-20261027`**. Do **not** select `main`, whose content is the old PR29 build.
3. For the `confirmation` input enter exactly `BUILD_G1_PROD_DEBUG_ONCE`. If the UI instead asks for `BUILD_PR29_ONCE`, stop: wrong branch.
4. Click Run workflow **once**. Share only the run URL and PASS/FAIL/BLOCKED status. Do not rerun blindly on failure. The chat's GitHub connection does **not** expose a `workflow_dispatch` operation, so source preparation is not a claim that a job was actually triggered.

Alternatively, the Human may execute the equivalent one-run GitHub CLI command on an authenticated, authorized workstation:

```powershell
gh workflow run p1-g1d-ux-pr29-manual.yml --repo trung-via/torrent-tv-vietsub --ref feature/g1-production-sidecar-picker-20261027 -f confirmation=BUILD_G1_PROD_DEBUG_ONCE
```

**Required evidence:** log markers `G1PROD_RUNNER_AND_POWERSHELL_PARSE_GUARDS_PASS`, `G1PROD_PINNED_OMP_SUBMODULE_PASS`, `G1PROD_STATIC_SOURCE_GUARDS_PASS_NOT_COMPILATION_OR_TV_PASS`, `G1PROD_DEBUG_BUILD_AND_UNIT_TEST_PASS_NOT_REAL_TV_PASS`, and `G1PROD_DEBUG_APK_HASH_AND_ASSET_GUARDS_PASS` plus private APK SHA256 and GitHub run ID. Any run FAIL/BLOCKED is *not* compile PASS; do not claim new product G1 acceptance until an independently authorized keep-data TV run.

**Status as of source preparation:** `HUMAN_G1PROD_SINGLE_DEBUG_BUILD_APPROVED / MANUAL_WORKFLOW_PREPARED / BUILD_NOT_STARTED / TV_UNCHANGED`.

## Consolidated G1 Production fix and review checkpoint (2026-10-27)

- **F1 (episode-bound selection):** The original first-open production ON/OFF was inherited by subsequent queue entries through OMP's shared `PlayerSession.subPicks`. Now, explicit VLC with any saved G1 association evaluates each target episode before `EngineSwitcher.goTo` / `PlayerSession.goTo`, resets the per-episode subtitle picks (ON only with checked app-private file/URI, OFF, otherwise original request baseline), and clears inherited embedded-track pending selection only for this scoped override. No change to the default goTo path for sessions without a saved production association; resume, seek and audio picks remain in the original navigation path. Missing ON file warns only for the target episode.
- **F2 (targeted unit tests):** New JVM `P1ProductionSubtitlesTest.kt` covers valid Vietnamese Unicode SRT and VTT, invalid UTF-8/NUL/oversize/missing cues, profile/hash/index isolation, ON/OFF/OTHER policy and fake engine A→B→A subtitle selection with resume preserved. The guarded patch copies this into the upstream Android `src/test` directory. `verify.ps1` now checks the transitions and test source presence in addition to original G1 guards; static text checks do not replace compiled unit-test outcomes.
- **Immutable post-review source:** `401f5bbda871e5ad96b39b83d750a6b3fbc56c7d`; G1 production manual workflow now checks out this source commit, not a moving PR HEAD or the old `a1c71a6` source. OMP and submodule pins are unchanged. The expected build remains **one** `assembleDebug testDebugUnitTest` run on the isolated `torrent-tv-vietsub-win` runner. No command has been dispatched here and APK/real-TV/release evidence stays UNVERIFIED.

The two source findings have implementation candidates but remain **BUILD/TEST_UNVERIFIED** until this updated source passes the first authorized build. If that run fails, review its first failure before considering any retry; no automatic retry, merge, Release or TV install. Reconfirm that the earlier one-run authorization applies to this changed source pin before dispatching.

### Mandatory visibility gate before any Action

The live GitHub API reported `trung-via/torrent-tv-vietsub` as **public** during this review, despite the contract's **private repository** requirement. GitHub Actions artifacts of public repositories are available to readers; an APK artifact must NOT be called private by retention settings alone. The branch-only G1 production job now adds a fail-closed `github.event.repository.private == true` predicate **before** checkout/build/upload. The Human must reconcile repository visibility with the product contract before the already authorized one-run Debug build. This branch has not run a build, merged, or touched Redmi. Do not change repository visibility automatically from this code review.
