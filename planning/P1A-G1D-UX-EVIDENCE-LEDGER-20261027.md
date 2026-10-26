# P1a G1d UX — Evidence ledger (2026-10-27)

**Scope:** Evidence reconciliation only for the new G1d warning debug APK on real Redmi; not a release or an AIOS TASK. Authority: Project Contract C6–C8 and P1A Acceptance Criteria AC-01..08. Human chose nonblocking Vietnamese warning option B. This record does not change Contract, PRD or ADR.

**Status:** G1D_UX01_TO_UX05_HUMAN_PASS / NEGATIVE_SUPPRESSION_PARTIAL / G4_RELEASE_ARTIFACT_UNVERIFIED.

## Immutable target

| Item | Pinned provenance |
| --- | --- |
| OMP upstream | 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f |
| 2160player | 6ba6edd39f5d986ddfae29b5425b8ac0b319844e |
| [Source PR #29](https://github.com/trung-via/torrent-tv-vietsub/pull/29) | dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92 — Draft/unmerged |
| [Manual build #40302153992](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40302153992) | Dedicated Windows runner; assembleDebug + testDebugUnitTest PASS; not release |
| Current debug APK on TV | SHA256 8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85. Human install + read-only VerifyInstalled [PR #31](https://github.com/trung-via/torrent-tv-vietsub/pull/31#issuecomment-6419730715) |
| Real device | MiTV-ASTR0, Android 11/API30, armeabi-v7a; com.spacesarmat.omp.test |
| External original SRT | files/p1-g1-external.vi.srt; SHA256 c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95. Imported separately from APK under G1c debug PoC |
| G1c settings | shared_prefs/p1-g1c-subtitles.xml exists and can be SHA256-read; scripts do not independently prove unchanged registry bytes throughout all cases |

## Five real-TV negative SRT cases for film A, saved choice ON, VLC

| Case | Fault | TV observation | Recovery evidence |
| --- | --- | --- | --- |
| UX-01 | Missing SRT | **Human PASS**: once-only nonblocking Vietnamese warning; G1c absent; AV, seek and remote stable; no sensitive content | **PASS**: standalone VerifyRestored original SRT hash / no backup and 3/3 Human reopened-TV checks; [PR #32 closure](https://github.com/trung-via/torrent-tv-vietsub/pull/32#issuecomment-6421130715) |
| UX-02 | Bad UTF-8 byte 0xFF | **Human TV PASS** (summary; no full separate UI trace pasted) | **PASS**: standalone VerifyRestored original SHA + registry baseline + no fixture; [PR #33 closure](https://github.com/trung-via/torrent-tv-vietsub/pull/33#issuecomment-6421857871) |
| UX-03 | Invalid cue timestamps | **Human PASS**: nonblocking warning, no G1c, stable AV and no leak | **PASS**: Stage, protected Restore SHA, cleanup, on-TV re-open with G1c ON and no warning; [PR #34 batch](https://github.com/trung-via/torrent-tv-vietsub/pull/34#issuecomment-6422564122) |
| UX-04 | Valid changed SRT, wrong saved SHA | **Human PASS** | **PASS**: case-specific Stage/Restore/clean-baseline/TV recovery markers, same PR #34 |
| UX-05 | Unreadable chmod-000 disposable SRT probe | **Human PASS** | **PASS**: app UID denied read, original protected inode restored, SHA/cleanup/TV recovery markers, same PR #34 |

PR #34 supplied the final **G1D_UX03_UX04_UX05_BATCH_TV_HUMAN_PASS** marker and final installed APK + clean original SRT/registry markers, with Restore after each test. No separate final VerifyRestored command was pasted, but the batch itself checks the final baseline.

Evidence nuance: UX-01 independent VerifyRestored succeeds although standalone Restore console log was not pasted. UX-02 standalone StageBadUtf8 and Restore command outputs were not pasted, although final VerifyRestored and Human TV PASS were provided. Avoid fabricating those command markers. Do not rerun these five successful cases solely for additional log cosmetics. TV checklist PASS is Human observation, not automated video/UI instrumentation.

## In-scope result versus remaining coverage

| Acceptance condition | Evidence tier | Status |
| --- | --- | --- |
| Exact debug APK installed; SRT outside APK; registered A with G1c saved ON and correct original subtitle after Restore | SHA checks + Human on-device | **PASS, for bounded PoC** |
| A→unregistered B→A when SRT is healthy | Human [PR #31](https://github.com/trung-via/torrent-tv-vietsub/pull/31#issuecomment-6419833502) | **PASS, healthy baseline only** |
| A ON with missing/invalid-UTF8/malformed/wrong-checksum/unreadable SRT | Human + per-case checksum integrity | **5/5 HUMAN PASS** |
| A saved OFF/OTHER while SRT invalid; no false warning and never forced ON | Source: warning requires explicit selection ON | **SOURCE_GATED / REAL_TV_UNVERIFIED** |
| B unregistered while A has damaged SRT; no warning or G1c leak | Source: exact server/hash/index media key | **SOURCE_GATED / REAL_TV_UNVERIFIED** |
| Built-in/2160 player with damaged saved-ON SRT; no false warning | Source: VLC-only early return | **SOURCE_GATED / REAL_TV_UNVERIFIED** |
| Missing identity, pending registration, unrelated episode under active failure | Source guards; no complete new-APK negative TV matrix | **PARTIAL / REAL_TV_UNVERIFIED** |
| G1 overall P1a AC-01..06, embedded switching, VTT, G2 live add and G3 cue sync | Not established by the five error-UX cases | **DO NOT INFER PASS** |
| Release variant contains no active debug registry/hook/asset or warning | Release source stub is no-op; no release APK evidence | **G4_RELEASE_ARTIFACT_UNVERIFIED** |
| Real Windows/NAS TorrServer, entire product readiness | Beyond this G1d UX evidence | **NOT ASSESSED HERE** |

**Naming warning:** the older planning/P1A-G1D-ERROR-UX-DECISION-DRAFT.md uses UX-01..UX-06 for a different decision checklist. UX-01..UX-05 here specifically name *five new-APK fault fixtures in Draft PRs #32–#34*.

## Recommended sequencing (do not repeat the five PASS cases)

1. Preserve bounded closure of all 5 error-UX fixtures with these limits. Do not call comprehensive AC06/G1/release PASS.
2. If Human wishes to certify the three no-false-warning paths, create a **single separately reviewed, approved negative-suppression matrix** for A OFF/OTHER, unregistered B and Built-in, with exact save/restore of ON selection and app SRT data. No additional on-TV fault stage is authorized by this ledger.
3. Prepare **G4 release artifact evidence** separately; see [G4 plan](P1A-G4-RELEASE-ISOLATION-PLAN-20261027.md). A debug APK does not prove release variant isolation.
4. Reconcile the stacked Draft PRs before any potential merge. At this audit: PR #29 → #31 → #32 → #33 → #34, all Draft/unmerged; PR #30 was a separate manual workflow merge.

**Stop rules:** no automatic AIOS/GitHub Actions dispatch, test rerun, TV app reset, runner system mutation, merge, publish, signing or release. Never log raw infohash, credential, magnet, LAN address or unredacted private TV footage.
