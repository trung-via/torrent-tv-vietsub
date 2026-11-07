# G1+P2 Redmi ARM32 — local-only private handoff

This script prepares **the existing Debug APK from [GitHub Actions run #42331308161](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42331308161)** for device acceptance. It does NOT rebuild, upload, install, uninstall, modify the TV, dispatch a workflow or contact TorrServer.

Historical source:
- App source commit: `1a71f136d712e534904c25c8baf0b8d7a461120e`
- Runner: `torrent-tv-vietsub-win`; generated APK: `app-armeabi-v7a-debug.apk`
- SHA256: `c2f71cb8c8accc11821396d20a96490b0a129344cb329e1c5e6d9c3bf2f7b75f`
- Evidence artifact: [run #42331308161 artifact #13557710870](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42331308161/artifacts/13557710870) (checksums and manifest **only**, not an APK)
- Runner build path originally reported: `C:\TOOL\TorrentTV-Runner\_work\_temp\p1-g1-prod-42331308161-1\android\app\build\outputs\apk\debug\`. It may have been cleaned; existence **must be checked**, not assumed.

## Fix for `SOURCE_APK_NOT_RETAINED_ON_RUNNER` (7 Nov 2026)

The verified run `42331308161` created its APK under `C:\TOOL\TorrentTV-Runner\_work\_temp\...`. This is GitHub Actions **RUNNER_TEMP** and may be purged after a job. The evidence-only GitHub artifact contains no APK bytes; a SHA256 hash cannot reconstruct the APK. A missing historical file is an expected HOLD, not permission to skip hash/signature checks or to use a different APK silently.

A reviewed auto-build now retains the freshly rebuilt ARM32 APK, manifest and evidence **before job cleanup**, outside `_work`, at:

```text
C:\TOOL\TorrentTV-Runner\private-artifacts\G1P2\run-<RUN_ID>-<RUN_ATTEMPT>\
  app-armeabi-v7a-debug.apk
  SHA256SUMS-G1P2.txt
  G1P2-BUILD-EVIDENCE.txt
```

The runner script uses NTFS ACL restricted to its own Windows identity, SYSTEM and local Administrators, and never publishes the APK to GitHub. This directory can differ from the interactive user's `%LOCALAPPDATA%`; access may require the authorized runner account or local administrator. Existing builds are never overwritten, and there is no automatic device installation.

For a **new confirmed successful run**, independently read its SHA256 from the GitHub Actions evidence manifest. On the Windows host, use the updated preflight (with exact run ID, attempt, and trusted hash):

```powershell
& .\tools\redmi-validation\verify-g1p2-arm32.ps1 -Mode Stage `
  -RunId '<new-run-id>' -RunAttempt '1' -ExpectedSha256 '<verified-64-hex-sha>'
```

The tool prefers the private retained path, then historical RUNNER_TEMP as a fallback; missing bytes still HOLD. To compare installed signatures without changing the TV, use `-Mode CompareInstalled` with the *same* pinned parameters and an already connected, authorized Redmi. **Do not use the old run's SHA to validate a different APK**.

## Local read-only checks

From Windows PowerShell, in a trusted checkout of this repository:

```powershell
& .\tools\redmi-validation\verify-g1p2-arm32.ps1 -Mode Inspect
```

Requires the original APK and SHA256 manifest to remain in the original runner's temp directory. Verifies the exact known checksum, the file name/ARM32 variant, Android package `com.spacesarmat.omp.test`, and that Android `apksigner` accepts the debug signature. It prints `G1P2_LOCAL_APK_SHA_AND_PACKAGE_PASS` only on success, **not G1 or P2 real TV PASS**. It holds if the APK was cleaned rather than silently running another build.

To stage a private **user-local** file (no network, no GitHub artifact):

```powershell
& .\tools\redmi-validation\verify-g1p2-arm32.ps1 -Mode Stage
```

The verified file is copied into the current Windows account's `%LOCALAPPDATA%\TorrentTVVietsub\PrivateDebug\g1p2-42331308161-armeabi-v7a-debug.apk`. A conflicting file is never overwritten. It is not placed into the public repository or published to GitHub Actions. This local persistence is **opt-in** and should be done by the person controlling the Windows runner.

To compare signing certificates before **considering** a keep-data update, use read-only ADB:

```powershell
& .\tools\redmi-validation\verify-g1p2-arm32.ps1 -Mode CompareInstalled
```

This is only appropriate when exactly one personally authorized Redmi is already ADB-connected. It queries `pm path`, pulls the installed `base.apk` into a local temporary file, compares its package name and all signer SHA256 digests with the new APK, then cleans the local temporary file. When several devices are connected, a separately known serial can be supplied with `-Serial`. **It never executes `adb install` or requests ADB pairing/network changes.**

### Gate outcomes

- **APK absent/cleaned:** `SOURCE_APK_NOT_RETAINED_ON_RUNNER`. No binary can be recovered from checksum-only evidence. A separately authorized build/transfer method is required.
- **APK/manifest/hash/package/signature failure:** HOLD and don't install.
- **Signature mismatch or ADB base APK unreadable:** HOLD, don't uninstall or clear data to work around it.
- **All checks PASS:** prepares an evidence-backed candidate for a **separately Human-approved** keep-data install and real Redmi tests (G1 SRT auto-render, OFF, A→B→A, VTT, OTHER; P2 opt-in UI, D-pad, no auto-add). The existing real TV G1 5/5 PASS belongs to a *previous APK*, not this composite build.
- **G4 Release:** remains unverified and unauthorized.

No WAN, account secrets, magnet/passkey, AIOS/AI Commerce execution or APK publishing is introduced by this change.
