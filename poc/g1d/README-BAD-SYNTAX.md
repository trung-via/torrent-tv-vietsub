# G1d — Malformed SRT cue while bytes remain valid UTF-8 (AC-06)

**Status:** `PREPARED / HUMAN-RUN ONLY / WINDOWS_AND_REAL_TV_UNVERIFIED`. Stack on [Draft PR #24](https://github.com/trung-via/torrent-tv-vietsub/pull/24), whose invalid-UTF8 negative + restore + VerifyRestored already have Human PASS. This is a **different test script**; do not reuse or edit the tested invalid-UTF8 script.

## Test hypothesis and fixture

The new script `G1D-Redmi-BadSyntax-SRT-Test.ps1` uses only printable ASCII (thus strictly valid UTF-8), with a numbered cue and timestamp `00:00:00.000 --> 00:00:02.000`. Milliseconds use **periods** instead of the SRT comma required by the PoC `cuePattern`, so the app's code should **reject the external subtitle** while VLC still plays the authorized video. This tests bad **syntax**, not invalid encoding. The script checks its own decoded fixture text against the Kotlin cue regex before staging. Real Redmi PASS requires Human observation.

## Gate 0: safe read-only preflight

- One authorized `MiTV-ASTR0`, Android API 30, ABI `armeabi-v7a`; ADB executable `C:\TOOL\Android-SDK\platform-tools\adb.exe`.
- Existing SEL-01 APK on Windows (used only by `StageBadSyntax`), exact SHA256 `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`.
- Existing original independent SRT `files/p1-g1-external.vi.srt`, SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`.
- Registry `shared_prefs/p1-g1c-subtitles.xml` exists, no G1c/G1b marker; no active backup or synthetic fixture at script's guarded paths. Prior invalid UTF-8 test `VerifyRestored` Human PASS.
- **Do not display** private media keys, torrent hash, magnet, credentials, passkeys or ADB serial in evidence.

Download the script from **the pinned new Draft PR** into `Downloads\G1D-Redmi-BadSyntax-SRT-Test.ps1` and review it. Then:

```powershell
$g1dSyntax = "$env:USERPROFILE\Downloads\G1D-Redmi-BadSyntax-SRT-Test.ps1"
& $g1dSyntax -Phase Preflight
```

Expected `G1D_SYNTAX_REDMI_MATCH`, `G1D_SYNTAX_BASELINE_PASS`, `G1D_SYNTAX_PREFLIGHT_READ_ONLY_PASS`; do not stage unless all three appear.

## Gate 1: only after accepted Preflight

Close the VLC player on TV, keep app installed, use the **previously SHA-verified SEL-01 APK** path already in `$sel01Apk`. If PowerShell session was reset, independently recheck the APK path/hash. Then:

```powershell
& $g1dSyntax -Phase StageBadSyntax -ApkPath $sel01Apk
```

Type `STAGE G1D BAD SYNTAX` after reviewing prompt. The script:
1. Rechecks device, registry, markers, original SRT SHA and both test backup/discard paths.
2. Generates SHA-verifiable synthetic malformed cue, uploads it temporarily, and checks its SHA256 before use.
3. Moves **only** original app-private SRT to `files/p1-g1-external.vi.srt.g1d-syntax-backup`, verifies protected backup SHA; copies synthetic fixture to original pathname, verifies that hash.
4. Emits `G1D_SYNTAX_FIXTURE_STAGED` only if staging checks pass.

If any error occurs after manual staging approval (particularly Android `run-as cp` denied), mark **BLOCKED** and prioritize `Restore`. Never overwrite, delete, or clear the protected backup. STOP conditions include hash changes, backup collision, wrong device, additional ADB devices, existing marker or missing registry. No new registration or engine switching away from VLC.

With successful staging, open the previously registered legal video **A in a NEW VLC session**. Expect the literal `P1 G1c - Saved SRT` **absent** from subtitle menu, with normal picture/audio/remote and no crash. This is not proof of user-facing UX error feedback.

Optional state-only check while staged:

```powershell
& $g1dSyntax -Phase InspectBadSyntax
```

## Gate 2: immediate recovery (even after a negative test FAIL)

Close VLC player and run:

```powershell
& $g1dSyntax -Phase Restore
```

Type `RESTORE G1D SYNTAX`. The script requires protected original backup at exact SHA256, and any present synthetic fixture at its specific exact SHA256. It moves the synthetic original-path file aside, **restores the original before deleting the synthetic discard**, and independently verifies SRT SHA. Restore requires no local APK path.

```powershell
& $g1dSyntax -Phase VerifyRestored
```

Expected `G1D_SYNTAX_ORIGINAL_SRT_RESTORED_HASH_PASS` and `G1D_SYNTAX_RESTORED_BASELINE_READ_ONLY_PASS_NOT_TV_PASS`. Reopen video **A using VLC** without re-registration, require exact G1c menu label and two Vietnamese Unicode cues to return.

**If Restore STOPs:** do not delete, overwrite, rename or clear app data manually; preserve the protected backup and report the sanitized error for diagnosis.

## Scope and acceptance

`G1D_BAD_SYNTAX_REAL_TV_HUMAN_PASS` requires Human-attested safe rejection and restored behavior, plus exact SHA and final read-only cleanup. Pending: changed-valid-SRT digest case, permission/read errors, and appropriate user-facing error indication. The earlier missing-file and invalid UTF-8 gates remain separate PASS; overall `AC06_PARTIAL`, and `G4_RELEASE_ARTIFACT_UNVERIFIED`.

This protocol adds **no Android Kotlin/TypeScript source changes**, Windows service/firewall/SMB/WAN settings, new APK installs, CI dispatches, AIOS TASKs, PR merges or releases. All device operations are performed by Human via explicitly gated PowerShell.
