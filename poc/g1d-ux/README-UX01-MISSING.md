# G1d UX-01 — Missing SRT, guarded Redmi test

**Status:** `SOURCE_ONLY_DRAFT / HUMAN_PARSE_PENDING / TV_STAGE_NOT_EXECUTED / UX_WARNING_UNVERIFIED`.

Use only the new [G1D-UX-Redmi-Missing-SRT-Test.ps1](G1D-UX-Redmi-Missing-SRT-Test.ps1) in this directory. The five older SEL-01 scripts in `poc/g1d/` are **historical** and pinned to the OLD APK; do not use them against the new UX build.

## Immutable gates

- Actual installed APK **and** local `-ApkPath` must independently equal SHA256 `8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85` from PR #29 run #40302153992.
- Real TV: `MiTV-ASTR0`, API30, ARM32; one authorized ADB device.
- Original `files/p1-g1-external.vi.srt` must equal SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`.
- Saved G1c registry must be a regular file and directly readable/hashable. The prior `test -r` false negative is deliberately not used.
- No G1b/G1c markers, no protected backup/discard from other negative tests, and no existing missing-SRT backup.

`Preflight`, `ObserveMissing`, and `VerifyRestored` read from the TV; for SHA provenance, the script pulls an installed APK into a disposable Windows-only temp file and removes it. It handles benign ADB stderr progress while preserving exit-code and hash guards. `StageMissing` uses a **single protected SRT rename** after separate typed Human consent. `Restore` is recovery-safe without local `-ApkPath` or registry accessibility: it never overwrites an occupied original SRT and always rechecks protected backup SHA256. It does not uninstall, change permissions, reset app data, manipulate the network or modify registry bytes.

## First execution — parser and read-only Preflight ONLY

Download the script from the **pinned Draft PR commit**, save it to Downloads under the name `G1D-UX-Redmi-Missing-SRT-Test.ps1`. In Windows PowerShell:

```powershell
$ux01 = "$env:USERPROFILE\Downloads\G1D-UX-Redmi-Missing-SRT-Test.ps1"
$parseTokens = $null; $parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($ux01,[ref]$parseTokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -ne 0) {
    $parseErrors | Select-Object Message,Extent
    throw "STOP: UX01 parser failed"
}
"G1D_UX01_PS_PARSE_PASS_NO_ADB_RUN"
```

After parser PASS, run:

```powershell
& $ux01 -Phase Preflight -ApkPath $uxApk
```

The local `$uxApk` is the verified PR29 ARM32 `app-armeabi-v7a-debug.apk` from the earlier install. Require all four output markers:

```text
G1D_UX01_REDMI_ARM32_DEVICE_PASS
G1D_UX01_EXACT_INSTALLED_APK_SHA_PASS
G1D_UX01_SRT_AND_REGISTRY_BASELINE_PASS
G1D_UX01_PREFLIGHT_READ_ONLY_PASS
```

**STOP after Preflight and send its log for review. Do NOT run `StageMissing` until a separate Human authorization.**

## Later, if Human separately authorizes the Stage test

1. Check registered media **A** already has saved G1c selection **ON** and will open using **VLC**; close the player before staging. Do not re-register or change media.
2. Run `& $ux01 -Phase StageMissing -ApkPath $uxApk` and type `STAGE G1D UX MISSING`. The source/pinned installed APK, app-private baseline and registry digest are rechecked, then the original SRT is moved to `files/p1-g1-external.vi.srt.g1d-backup`. Do not launch other tests while staged.
3. In a **fresh VLC player load** of A, expect **one** nonblocking warning: **"Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT."** The G1c subtitle track must be omitted while AV/seek/remote keep working. This must be confirmed by Human; code markers cannot prove TV UX.
4. Optional read-only staging verification: `& $ux01 -Phase ObserveMissing -ApkPath $uxApk`. This is not TV UX proof.
5. **Always Restore promptly, including if warning or playback FAIL:** close VLC, run `& $ux01 -Phase Restore`, type `RESTORE G1D UX SRT`. Require `G1D_UX01_ORIGINAL_SRT_RESTORED_HASH_PASS`.
6. Run `& $ux01 -Phase VerifyRestored -ApkPath $uxApk`; expect `G1D_UX01_RESTORE_BASELINE_READ_ONLY_PASS_NOT_TV_UX_PASS`. Reopen A in VLC without registering again: saved G1c track, UTF-8 Vietnamese cues and prior ON choice return, with no false warning.

**STOP** on any unexpected device/build, hash mismatch, marker/backup, SRT or registry change, blocked playback, app crash, lost audio or restoration problem. Keep backup untouched for diagnosis. Never use `pm clear`, uninstall, overwrite a backup, chmod/chown registry, alter Windows services/firewall/router, dispatch AIOS, or merge/release as part of this test.

The other G1d cases (bad UTF-8, invalid cue, changed-valid SRT, denied-read) remain **separate future source reviews**, not part of this PR.
