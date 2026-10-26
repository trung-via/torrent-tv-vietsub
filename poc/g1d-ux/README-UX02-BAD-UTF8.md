# G1d UX-02 — Invalid UTF-8 external SRT on the installed Redmi debug APK

**Gate:** `SOURCE_DRAFT / WINDOWS_PARSER_UNVERIFIED / UX02_PREFLIGHT_PENDING / TV_STAGING_NOT_APPROVED / UX02_REAL_TV_UNVERIFIED`.

This is a Human-run **new** test script `G1D-UX-Redmi-BadUtf8-SRT-Test.ps1`, layered on the UX-01 Draft PR #32 that already has **Human real-TV E2E PASS and restored baseline**. Do **not** use the historical SEL-01 `poc/g1d/G1D-Redmi-BadUtf8-SRT-Test.ps1` on the UX APK, as that script pins the **old** installed build. No CI, TV/Windows ADB command, build, release or app installation is authorized by creation of this PR.

## Exact source/provenance

- PR #29 source `dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92`, manually built in [Actions run #40302153992](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40302153992).
- **Local APK plus installed TV `base.apk`** must independently SHA256 to `8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85`.
- Exact real TV: `MiTV-ASTR0`, Android 11/API30, `armeabi-v7a`, debug package `com.spacesarmat.omp.test`, **one** ADB device.
- Original `files/p1-g1-external.vi.srt` SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95` is never intentionally changed; it is moved to a protected backup before a separate bad-UTF8 fixture is copied to the original path.
- Registry `shared_prefs/p1-g1c-subtitles.xml` must exist as a regular file and hash successfully. Because this TV's `test -r` falsely reported unreadable on an otherwise valid mode-660 XML, actual `sha256sum` checks are used and the content is neither dumped, edited nor disclosed.

## Isolated synthetic data

The deliberately invalid UTF-8 test body is deterministic: a valid ASCII SRT cue index and timestamp header, then illegal single byte `FF` in cue text, then `G1D_UX02_BAD_UTF8`. This fixture is created locally in a disposable Windows temp file, pushed to the *fixed reserved* `/data/local/tmp/p1-g1d-ux02-badutf8-20261026.bin` only if the path is unoccupied, then hashed before copying to the app-private original SRT pathname. The generated fixture is never treated as a real subtitle.

The script guards these app-private names:

- Protected original: `files/p1-g1-external.vi.srt.g1d-utf8-backup`
- Temporary synthetic discard used by Restore: `files/p1-g1-external.vi.srt.g1d-utf8-discard`
- Other prior UX-01 or legacy scenario backup/discard paths must be **absent**; pending G1b/G1c registration markers must be **absent**.

All app data changes are limited to Human-approved `StageBadUtf8` and `Restore`. Stage uses a single protected rename **before** copying the fixture; digest checks must match the exact SRT baseline and synthetic fixture. Windows-only temporary files are deleted. Stage attempts to remove the remote fixture only when its digest exactly matches the known synthetic bytes. If any stage failure occurs **after the original rename**, the protected backup remains and the Human should move directly to diagnosis/Restore, not restage.

`Restore` is deliberately **independent of APK archive, registry access, and remote fixture access for the core SRT recovery**: it validates protected original bytes, refuses to overwrite a nonfixture or occupied discard, moves exactly the known synthetic file to discard when present, moves the protected original back, verifies original SHA256 and absence of backup, and only then removes the known fixture/discard after digest checks. On unexpected bytes or an interrupted operation, **STOP and preserve backup**; do not manually overwrite, `pm clear`, uninstall, chmod or re-register.

## Next Human run — syntax and read-only Preflight ONLY

Download `poc/g1d-ux/G1D-UX-Redmi-BadUtf8-SRT-Test.ps1` using **Raw** at the pinned PR commit, saving a **new filename** in Windows Downloads. Do not run a cached/older SEL-01 script.

```powershell
$ux02 = "$env:USERPROFILE\Downloads\G1D-UX-Redmi-BadUtf8-SRT-Test.ps1"
if (-not (Test-Path -LiteralPath $ux02 -PathType Leaf)) {
    throw "STOP: UX02 script file missing"
}
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $ux02,[ref]$tokens,[ref]$parseErrors
) | Out-Null
if ($parseErrors.Count -ne 0) {
    $parseErrors | Select-Object Message,Extent
    throw "STOP: UX02 PowerShell syntax error"
}
"G1D_UX02_PS_PARSE_PASS_NO_ADB_RUN"
```

Only after parser PASS, run **read-only Preflight** with the *previously verified* `$uxApk` local variable:

```powershell
& $ux02 -Phase Preflight -ApkPath $uxApk
```

Require all four markers:
```text
G1D_UX02_REDMI_ARM32_DEVICE_PASS
G1D_UX02_EXACT_INSTALLED_APK_SHA_PASS
G1D_UX02_SRT_AND_REGISTRY_BASELINE_PASS
G1D_UX02_PREFLIGHT_READ_ONLY_PASS
```

**STOP AND POST THE LOG. StageBadUtf8 is NOT AUTHORIZED by this read-only Preflight instruction.** No code merge/build/release or AIOS action.

## After separate Human approval of the real-TV Stage (NOT YET)

1. Verify **already registered** film A has **saved external G1c SRT ON**, uses **VLC**, and no prior negative test remains staged. Close VLC player.
2. Run `& $ux02 -Phase StageBadUtf8 -ApkPath $uxApk`; type exactly `STAGE G1D UX BAD UTF8`. Expect `G1D_UX02_STAGED_FIXTURE_AND_BACKUP_SHA_PASS_NOT_TV_UX_PASS` and `G1D_UX02_STAGE_BAD_UTF8_PASS_NOT_TV_UX_PASS`. If STOPs at any point, **do not rerun StageBadUtf8**: preserve backup and inspect.
3. Freshly reopen A with VLC. Human observes **one nonblocking Vietnamese warning**: **“Phụ đề rời đã lưu không khả dụng. Kiểm tra file SRT.”** The G1c subtitle track must be absent, while video, audio, D-pad/remote and seek must remain stable. The warning must not expose file paths/media identifiers/credentials.
4. Optional `& $ux02 -Phase InspectBadUtf8 -ApkPath $uxApk` confirms SHA state but **not** visual UX.
5. **Always restore promptly—even on UI FAIL:** close VLC and run `& $ux02 -Phase Restore`, type exactly `RESTORE G1D UX UTF8`. Require `G1D_UX02_ORIGINAL_SRT_RESTORED_HASH_PASS` and `G1D_UX02_RESTORE_AND_SYNTHETIC_CLEANUP_PASS`. If cleanup STOPs **after** original hash PASS, do not restage; inspect residual fixture/discard separately.
6. `& $ux02 -Phase VerifyRestored -ApkPath $uxApk` (read-only). Require `G1D_UX02_RESTORE_BASELINE_READ_ONLY_PASS_NOT_TV_UX_PASS`. Then on TV reopen A: saved G1c track/ON and Vietnamese cues return, no false warning and AV functions.
7. Record separate `STAGE / REAL_TV_WARNING / NO_G1C / AV_REMOTE / RESTORE_HASH / POST_RESTORE_TV` PASS/FAIL. Do not leak TV serials, magnet links, raw infohashes, private media IDs or credentials in shared logs.

**STOP conditions:** wrong TV, duplicate/offline ADB, unexpected APK SHA, missing/mismatched original SRT, unreadable registry, unknown existing fixture/backup/discard, registry changes, crashing or blocking UI, sound/video loss, partial fixture, failed recovery. **Restore is priority; do not run UX-03/04/05 while UX-02 is staged.**

## Out of scope

The old SEL-01 G1d tests, release/G4, UX-03 malformed cues, UX-04 changed-valid content and UX-05 unreadable file remain independent. PR #29/#31/#32 are Draft and unmerged, and this Draft PR should stay stacked/unmerged pending all relevant Human gates.
