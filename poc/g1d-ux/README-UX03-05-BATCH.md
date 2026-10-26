# G1d UX03–UX05 — one Human-approved, guarded TV batch

**Status:** `SOURCE_ONLY / STATIC_CHECKS_ONLY / WINDOWS_PS5_PARSER_UNVERIFIED / BATCH_NOT_APPROVED / TV_UNTOUCHED`.

New script: [`G1D-UX-Redmi-03-05-Batch.ps1`](G1D-UX-Redmi-03-05-Batch.ps1). Based on reviewed UX02 Draft PR #33, with Human `UX02_TV_HUMAN_PASS` and `UX02_RESTORE_BASELINE_VERIFIED`. Historical SEL-01 `poc/g1d/` scripts use the **old installed APK SHA** and must never be used on current PR29 build.

## Three cases, one approval and one RunBatch command

1. **UX03 BadSyntax** — correct UTF-8 encoding but invalid SRT cue timestamps (dots for milliseconds, not commas).
2. **UX04 ChangedValid** — syntactically valid UTF-8 SRT but intentionally different content SHA256 from the previously registered original.
3. **UX05 Unreadable** — move original SRT inode to protected backup, copy it to a disposable SRT probe, change **only probe** to `chmod 000` and verify app UID actually sees a `Permission denied` on SHA256 read. Restore revives probe solely to verify its bytes, then replaces it with the **untouched original inode**.

Script pins exact `MiTV-ASTR0`/API30/`armeabi-v7a` debug package `com.spacesarmat.omp.test`; one authorized ADB device; both local APK and ACTUAL installed TV `base.apk` SHA256 `8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85`; original `files/p1-g1-external.vi.srt` SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`; valid directly SHA256-readable G1c registry; no registration marker, protected test backup/discard, or reserved synthetic fixture. APK provenance: PR29 source `dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92`, manual [Actions run #40302153992](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40302153992).

**For each case:** pin and baseline → protect original → create fault → Human opens registered film **A**, G1c saved **ON**, in a **fresh VLC session** → Human marks the warning/AV/remote checklist PASS or FAIL → PowerShell `finally` attempts **guarded Restore** even on FAIL or a script error → baseline hash and backups verified clean → Human reopens A and confirms G1c ON + Vietnamese cues, sound/video, **no warning**. Only then does batch proceed. **Any FAIL or unexpected state stops the rest of the batch.**

Expected invalid-SRT TV UX in every negative case: one generic Vietnamese warning **“Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT.”**, no saved G1c track, video/audio/seek/D-pad preserved, no path/URL/media ID/credential leakage. Human feedback is manual, not automated TV telemetry.

**Recovery limit:** Protected per-case backup preserves original bytes. Restores refuse overwrite if current SRT has unexpected SHA or discard is occupied; no action is taken to clear app data, uninstall, re-register, modify registry, change firewall/router, or merge. If Windows/PowerShell is forcibly terminated, `finally` may not execute. In that case **do not restart batch**; use scenario-specific `-Phase Recover -Case BadSyntax|ChangedValid|Unreadable` only after verifying staged backup and reviewing errors. `Recover` does not depend on local APK or registry access, and requires its own typed `RECOVER UX03 SRT`, `RECOVER UX04 SRT`, or `RECOVER UX05 SRT`. If recovery STOPs, preserve backups and obtain diagnosis.

## Initial Human check — parser + read-only Preflight

Download the pinned script from this Draft PR via **Raw**, save it as `Downloads\G1D-UX-Redmi-03-05-Batch.ps1`. Run in Windows PowerShell 5.1:

```powershell
$uxBatch = "$env:USERPROFILE\Downloads\G1D-UX-Redmi-03-05-Batch.ps1"
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uxBatch,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -ne 0) {
    $parseErrors | Select-Object Message,Extent
    throw 'STOP: batch script parser error'
}
"G1D_UX_BATCH_PS_PARSE_PASS_NO_ADB_RUN"
& $uxBatch -Phase Preflight -ApkPath $uxApk
```

Preflight expected markers: `G1D_UX_BATCH_ARM32_DEVICE_PASS`, `G1D_UX_BATCH_INSTALLED_APK_SHA_PASS`, `G1D_UX_BATCH_SRT_REGISTRY_CLEAN_PASS`, `G1D_UX_BATCH_PREFLIGHT_READ_ONLY_PASS`.

**Do not run `RunBatch` until a separate, explicit Human authorization for UX03–UX05 on the TV.** Preflight is TV read-only and temporarily copies installed APK to Windows temp for digest before deleting the temp copy.

## Only after separate Human batch-stage authorization (not yet)

Use a **single** PowerShell command, then follow interactive prompts on screen rather than returning to ChatGPT between cases:

```powershell
& $uxBatch -Phase RunBatch -ApkPath $uxApk
```

Type `RUN G1D UX03 UX04 UX05 BATCH` once. The script prompts before each stage to **close VLC**, then after TV observation to type **PASS** only if all four error-screen/AV checks pass, else **FAIL**. Regardless, guarded Restore is attempted. After reopening A to verify restored G1c track, subtitles and no false notice, type PASS/FAIL again. Each case is gated by complete SHA256 restoration before the next.

On successful completion expect `G1D_UX03_TV_WARNING_AND_RESTORE_HUMAN_PASS`, `G1D_UX04_TV_WARNING_AND_RESTORE_HUMAN_PASS`, `G1D_UX05_TV_WARNING_AND_RESTORE_HUMAN_PASS`, `G1D_UX03_UX04_UX05_BATCH_TV_HUMAN_PASS`. Confirm clean final state with:

```powershell
& $uxBatch -Phase VerifyRestored -ApkPath $uxApk
```

Expect `G1D_UX_BATCH_VERIFY_RESTORED_READ_ONLY_PASS`. Send one sanitized summary/log after the batch, not after every case. **No permission to run CI, AIOS, install, merge, modify registry, or claim G4 release isolation is included here.** PR #29/#31/#32/#33 and this PR remain Draft/unmerged.
