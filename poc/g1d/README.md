# G1d — negative external SRT on real Redmi (first bounded gate: missing file)

**Status:** `PROPOSED_TEST_SCRIPT / NOT_EXECUTED / G1D_REAL_TV_UNVERIFIED`. No new Kotlin/app code, release build, ADB test, CI dispatch or AIOS task. This plan applies only to legally accessible TorrServer v1 media on trusted LAN and the already Human-installed SEL-01 debug APK.

## Why test missing SRT first

The installed SEL-01 debug helper `P1G1CSubtitleRegistry` validates the independent app-private SRT file's presence/readability, <=256 KiB, strict UTF-8, cue shape and SHA256 each time it reopens registered media. If validation fails it returns the normal PlayRequest without injecting G1c, and it must not override ON or OFF. **This is a code claim, NOT a real-TV PASS**. AC-06 also asks for an appropriate error indication; current debug PoC deliberately silently fails closed, so even a successful no-crash test does **not** by itself fulfill error-UX acceptance.

## Immutable evidence/pins

- Source SEL-01 Draft PR #21 head: `4ead266bc303e44efd83bd5e4270d3919951cf6a`.
- [SEL-01 manual GitHub Actions run #40264117786](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40264117786) succeeded; ARM32 debug APK hash (Human-checked): `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`.
- Redmi `MiTV-ASTR0`, API 30, `armeabi-v7a`, package `com.spacesarmat.omp.test`.
- Exact SRT baseline: app-private `files/p1-g1-external.vi.srt`, SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`; G1c registry `shared_prefs/p1-g1c-subtitles.xml`.
- **No G1b/G1c marker**, no re-registration, no copying source SRT into APK. No app-private registry modification.

## One reversible test, Human at TV + Windows

Use `poc/g1d/G1D-Redmi-Missing-SRT-Test.ps1`, only on the Human's Windows PC with previously authorized ADB. The script never calls ADB connect/tcpip or opens firewall/router/SMB, never installs, uninstalls, resets data or executes torrents. Only **StageMissing** and **Restore** rename the single SRT within app-private storage after explicit typed approval. Backup name is `files/p1-g1-external.vi.srt.g1d-backup`, and the exact SRT SHA256 must match before **each** move. There is no automatic deletion or overwrite of an existing backup.

1. Make sure the existing SEL-01 APK and user session remain intact. Close VLC player on TV. Do not switch to a different episode; test only previously registered lawful video **A**.
2. Windows PowerShell after obtaining script (download it from THIS draft PR's pinned code view): `$g1d = "$env:USERPROFILE\Downloads\G1D-Redmi-Missing-SRT-Test.ps1"`, `$sel01Apk = $apks[0].FullName` if still in the previously audited shell. If shell was restarted, use the **audited** `app-armeabi-v7a-debug.apk` absolute path as `$sel01Apk`.
3. Run `& $g1d -Phase Preflight` (read-only; expect `G1D_PREFLIGHT_PASS_READ_ONLY`). **STOP** if not PASS.
4. Run `& $g1d -Phase StageMissing -ApkPath $sel01Apk`; type **`STAGE G1D MISSING`**. Expect `G1D_MISSING_FILE_STAGED`. Original SRT bytes are kept under protected app-private backup; no marker is armed.
5. Open video A in VLC from a new player session. Expected: **`P1 G1c - Saved SRT` absent**, app **does not crash**, audio/video remains playable; do **not** mistake another embedded subtitle for G1c. If G1c track appears, `FAIL` — stop testing and restore immediately. The absence alone does not prove good UX error feedback.
6. Run `& $g1d -Phase ObserveMissing` (read-only verification of missing original + intact backup; not proof of TV behavior).
7. Close VLC player on TV. Run `& $g1d -Phase Restore`, type **`RESTORE G1D SRT`**. **Do this even if TV result FAIL or you choose to stop testing.** Expect `G1D_ORIGINAL_SRT_RESTORED_HASH_PASS`. Reopen A (no marker): check the G1c track and two distinctive UTF-8 Vietnamese lines are restored, including ON selection as previously accepted.
8. Run `& $g1d -Phase VerifyRestored` (read-only). Expect `G1D_RESTORE_PREFLIGHT_PASS_NOT_TV_RENDER_PASS`.

**STOP conditions:** any hash mismatch, duplicate device, wrong model/API/ABI, unauthorized ADB, missing old registry, existing G1d backup, marker present, missing original when not staged, crash, missing audio, inability to restore, or accidental registration. Keep the protected backup intact if any recovery step fails; do **not** run `pm clear`, uninstall, `rm`, new `Register` or patch scripts to bypass checks.

## Evidence matrix

| Gate | Human TV observation | State until Human confirms |
| --- | --- | --- |
| G1d-MISS-01 | Missing SRT => G1c track not injected; playback still works, no crash | UNVERIFIED |
| G1d-RESTORE-01 | Restore exact SHA256; reopen A => G1c label + 2 Vietnamese cues + prior ON | UNVERIFIED |
| G1d-BADUTF8-02 | Invalid UTF-8 content => no injection, no crash | **NOT TESTED** |
| G1d-BADSYNTAX-03 | Malformed/noncue SRT => no injection, no crash | **NOT TESTED** |
| G1d-MODIFIED-04 | Changed valid SRT (different SHA) => no silent association | **NOT TESTED** |
| G1d-PERM-05 | Permission-denied/read-error case => no crash, appropriate feedback | **NOT TESTED** |
| AC-06 UX | Clear user-facing feedback without secrets; silent fallback might be insufficient | **UNVERIFIED / PROPOSED product UX** |
| G4 | Production/release APK has no debug hook/asset/registry behavior | **UNVERIFIED / separate** |

No general `G1D_PASS`, `AC06_PASS` or `EXTERNAL_SRT_E2E_PASS` until the entire corresponding matrix is supported. The initial gate is intentionally only missing file and recovery. All test evidence is `HUMAN_REPORTED`; TV screenshots/logs optional but must not expose URLs, magnets, keys or serials.

## Rollback and boundary

`Restore` must work **without** a local APK path even if the original archive/PowerShell session has been lost. It validates the backup hash before renaming back. The app-private preferences XML must never be deleted or edited. Script is from a Draft PR; its source has not been run on Human's Windows PC or instrumented Android device. Review before running. No AIOS TASK/dispatch, no code merge or release authorization implied.
