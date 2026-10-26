# P1a G4 — Release isolation evidence plan (2026-10-27)

**Status:** G4_STATIC_SOURCE_REVIEW_PARTIAL / RELEASE_BUILD_NOT_AUTHORIZED / RELEASE_ARTIFACT_UNVERIFIED / NO_RELEASE_REQUESTED.

**Authority:** Project Contract C5/C6/C7/C8, P1a acceptance **AC-08**, and P1a G0..G4 separation. This is a **proposal for the next Human-approved gate**, not authority to create or run a GitHub Actions workflow, build/sign/install/publish a release, change AIOS, or merge any Draft PR.

## Why G4 is still open

The tested physical Redmi contains **debug** PR29 APK SHA256 8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85. The five G1d corrupted-SRT cases are Human PASS on that debug APK, *not on a release variant*.

The audited candidate source has two build-variant helpers:
- [Debug helper in PR #29](https://github.com/trung-via/torrent-tv-vietsub/blob/dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92/poc/g1c/P1G1CSubtitleRegistry.debug.kt) reads the app-private SRT, checks media key/selection, registers the debug-side file if explicitly armed, and can emit a fixed Vietnamese warning.
- [Release helper in PR #29](https://github.com/trung-via/torrent-tv-vietsub/blob/dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92/poc/g1c/P1G1CSubtitleRegistry.release.kt) exposes the same method signatures but returns unchanged PlayRequest, no warning, and no file/prefs accesses. **This is a source-level fact, not proof that the actual release APK excludes all debug implementation/fixture pathways.**
- [Guarded apply](https://github.com/trung-via/torrent-tv-vietsub/blob/dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92/poc/g1c/apply.ps1) places Kotlin sources in Android src/debug and src/release respectively on a **disposable, pinned upstream OMP checkout**. [verify.ps1](https://github.com/trung-via/torrent-tv-vietsub/blob/dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92/poc/g1c/verify.ps1) audits source structural guards including absence of SRT assets, but is not an Android compiler or an APK-inspection substitute.
- Current checked repository workflows include manual **debug** build jobs. No authorized release build or actual release APK forensic result is in the G1d evidence ledger.

## Proposed single release-artifact gate — run only with distinct Human approval

**G4-S1: read-only scoped source/variant mapping**, without ADB or modifying the TV:
1. Pin the approved source PR29 SHA, OMP SHA 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f, submodule SHA 6ba6edd39f5d986ddfae29b5425b8ac0b319844e, and the exact Kotlin source blob SHAs. Detect any PR drift or clean-tree mismatch.
2. Verify src/debug helper contains debug-only registration, SRT and warning paths; src/release helper has matching signature and **returns the request unchanged**, never reads registry/files or adds a subtitle. Confirm main source does not independently replicate the debug injection.
3. Verify Android variant wiring **actually picks the release source set for release** and no debug-only asset/fixture is incorporated, without assuming naming alone is enough.
4. Record every check as SOURCE_ONLY_PASS or BLOCKED; never claim G4 PASS from this stage.

**G4-B1: one manually authorized build and binary inspection on dedicated app runner**, not AIOS runner:
1. Separate Human grants permission for a **disposable, unsigned/unpublished release-variant artifact build + scan**. Review required repository source branch, isolated workspace path, runner identity, workflow dispatch policy, and dependency/license provenance before any execution. Existing workflows are debug-only; drafting or dispatching a release workflow is **not** authorized by this document.
2. From a fresh pinned OMP checkout and verified submodule, apply exact approved PR29 patch in the dedicated, disposable project workspace, run applicable source checks and compile a true **release** variant (candidate Gradle task: assembleRelease; verify build configuration and signing requirements first). Never modify a persistent Android/Windows system location, TV, credentials, app installation or Git main as an implied side effect.
3. Capture a private, immutable release APK artifact with SHA256, build/run ID, runner/workspace provenance, variant flag, exact source commit, Android Gradle output and static tests. If release assembly requires unavailable signing, do not bypass security or pretend a debug APK is release: mark BLOCKED and request a separate decision.
4. Inspect **actual release APK** package/manifest and merged assets/resources and classes*.dex using appropriate Android analysis utilities. Prove no G1c debug SRT bytes/asset, no active registration marker behavior, no debug-only prefs/file-load/injection, and no fixed warning string or track label from the debug helper. Do not rely solely on filename or a blind strings grep; analyze variant-selected compiled code and account for R8/obfuscation. Check the release variant does not expose other debug test entrypoints via manifest or WebView.
5. Report both negative findings **and any uncertain analysis**. If all source-set, runtime-entry-point and binary inspections support isolation, mark **G4_RELEASE_ARTIFACT_ISOLATION_PASS for this pinned, inspected artifact only**. If an APK could not be examined or code path cannot be excluded, mark BLOCKED/UNVERIFIED and retain exact evidence.
6. **Never install or distribute** an unsigned test artifact. Any subsequent on-TV release smoke, signing-key handling, installation, publication, license/copyleft review and user-facing shipping approval require distinct Human decisions. GPL corresponding-source obligations remain separate from the G4 debug-isolation criterion.

## Exit criteria / acceptance matrix

| Check | Required artifact/evidence | Current |
| --- | --- | --- |
| G4-01 — release Kotlin helper is no-op | Pinned PR29 release helper and source-set routing | **SOURCE_ONLY observed; variant compilation not checked** |
| G4-02 — debug paths cannot activate in release | Release-variant compiled methods and call graph, no debug registration/selection/notice route | **UNVERIFIED** |
| G4-03 — no debug fixtures in release package | Actual APK assets/resources, manifest, classes and recognizable test strings | **UNVERIFIED** |
| G4-04 — exact reproducible provenance | Release APK SHA, source, build logs, dedicated runner and variant | **UNVERIFIED** |
| G4-05 — credential/license/security review | Redacted evidence and separate release/compliance approval | **NOT AUTHORIZED / UNVERIFIED** |
| G4-06 — actual release playback on TV (if required for shipment) | Separate authorized sign/install/smoke and rollback | **NOT REQUESTED** |

## Recovery and stop conditions

- G4 should **not require touching the Redmi** or the existing G1c stored SRT/prefs when merely inspecting an APK. Do not repeat UX01-05 or change saved OFF/ON to generate G4 evidence.
- If a build is later authorized, run **once** and collect combined source/binary/test results. Do not create extra ChatGPT gates between harmless in-job read-only inspection steps. STOP immediately on runner identity/workspace drift, wrong commit, impure clone, unexpected signing/publishing attempt, source-set leakage, asset debug content or inability to prove binary variant.
- Do not auto-dispatch, schedule, merge, sign, publish, switch TV player, access LAN private media, alter firewall/router or change AIOS-renew.
- Keep stacked PRs #29/#31/#32/#33/#34 Draft/unmerged until separate Human review. Product-level release requires other Contract gates besides G4, including source license attribution, authentication/privacy, server, player and TV acceptance.
