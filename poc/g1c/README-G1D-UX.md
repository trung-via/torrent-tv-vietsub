# G1d subtitle error UX — approved B, implementation candidate

**Human approval:** 2026-10-26, nonblocking error notice in a separate Draft patch only; **no auto merge/build/installation**. Inherits decision draft in PR #28. Not an AIOS TASK, contract revision, or release authorization.

**Actual status:** `PATCH_PREPARED / STATIC_SOURCE_REVIEW_ONLY / KOTLIN_BUILD_UNVERIFIED / UX_REAL_TV_UNVERIFIED / G4_RELEASE_ARTIFACT_UNVERIFIED`. Prior five G1d cases on real Redmi are **HUMAN PASS only on the old SEL-01 debug APK**; their results are not evidence of this modified APK.

## Scoped implementation

- `P1G1CSubtitleRegistry.debug.kt`: `prepare()` returns `Prepared(request, warning)`. Check current item by exact saved-server-profile ID + v1 infohash + fileIndex. Only warn if the current item had **previously registered SRT**, saved choice **ON**, explicit **VLC**, no pending marker, and SRT unreadable/missing/invalid/changed checksum. The warning is a fixed, safe Vietnamese sentence: **“Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT.”** No URL/media ID/absolute path/credential is included. No prefs mutation during error.
- `P1G1CSubtitleRegistry.release.kt`: same result API, returns `Prepared(r)`, no warning or SRT file/prefs access. Source split does **not** establish G4 release binary PASS.
- `apply.ps1`: on clean disposable pinned OMP upstream, patch `PlayerActivity.load()` to use `g1cPrepared.request`; call existing native `showMessage(it, true)` after upstream `hideMessage()`. No new toast/UI framework or modal, no engine change, SEL-01 ON/OFF persistence preserved.
- `verify.ps1`: static source assertions for ON/exact-media gate, ordering, release no-op and absence of embedded SRT assets. This is **not** a Kotlin compile, behavior test or Redmi TV proof.
- **Localization limit:** the approved PoC displays fixed Vietnamese copy only. A full locale-aware EN/RU/VI implementation is not included; assess separately before multilingual production release.

## Behavior and acceptance criteria

| Scenario: newly opened current item | Expected toast | Expected subtitle/player |
| --- | --- | --- |
| A registered, G1c ON, SRT missing, corrupt UTF-8, malformed cue, content SHA mismatch, or app cannot read | One generic Vietnamese warning | G1c omitted; AV/remote remain functional |
| A registered, ON, correct SRT | None | G1c + Vietnamese cues selected |
| A registered, OFF or OTHER | None, even if SRT invalid | Never force G1c ON |
| B never registered | None | No G1c leak from A |
| C previously registered | Only if C itself ON and fails checksum | C isolated from A/B |
| Built-in player, missing server/hash/index identity, initial marker registration | None | Preserve prior behavior |
| File restored and A reopened | None | G1c cues and persisted choice restored |

**One warning per newly opened `PlayerActivity.load()`**; changes mid-playback or internal `PlayerSession.goTo()` queue-item switches are outside this PoC, and should not be claimed. No dialog, D-pad blockage, automatic registration, preference mutation, backend/database or transport change.

## Verification gates — not yet executed

1. Review Draft PR code/diff, pinned OMP SHA `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, 2160player SHA `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`, and dedicated runner/worktree restrictions. Confirm no unapproved source or AIOS changes.
2. **Separate Human build authorization required:** disposable clean checkout on project-only Windows runner; apply this exact patch; run `verify.ps1`, TypeScript compile, Gradle tests/debug APK build; collect sanitized build log and newly built APK SHA256. Static guard PASS != `BUILD_PASS`.
3. **Separate Human TV install authorization required:** verify exact **new** APK provenance and Redmi model/API/ABI, only then reinstall with data retention; NEVER `pm clear`/uninstall/modify saved prefs. Existing G1d negative scripts are pinned to the **old SEL-01 local APK checksum** `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`: that pin does not establish that a new UX APK is installed. Review a new installed-binary check before claiming new UX PASS.
4. Human tests actual VLC behavior for UX-01..UX-05: missing, bad-UTF8, bad syntax, changed-valid SHA, permission 000; each should warn only for saved ON A, still have stable AV/remote, and restore the original exact SRT/permissions. Check no warning for A OFF, B unregistered, built-in player, and no false notice on restore. Each negative experiment uses guarded per-case Stage/Restore/VerifyRestored; **do not skip cleanup even after FAIL**.
5. Record `HUMAN_PASS` only after real-TV observation of the **new APK**; check no secrets in toast/log. **G4 release artifact** requires its own build, inspection and Human approval; the no-op release source is not enough.

**STOP:** wrong media/episode, popup blocking playback, warning for saved OFF/B, changed subtitle choice, crash/lost AV, secret disclosure, protected backup/hash problem, mismatched runner/worktree or source SHA, inability to restore, or unauthorized network/system change. Rollback via branch/disposable checkout; keep TV data intact.

**Do not auto:** build, CI dispatch, install, merge, release, alter the contract or AIOS-renew.
