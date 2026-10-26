# P1 G0 — Local Vietsub debug probe (opt-in, no SMB)

**Status:** `IMPLEMENTATION_PATCH_PREPARED / BUILD_UNVERIFIED / REAL_TV_UNVERIFIED`. This is **code for a bounded feasibility probe**, not an Android production importer or an AIOS TASK.

## What this changes

- Applies one exact-line Kotlin call-site change to OMP `PlayerActivity.load()` before `PlayerSession.load()`.
- Copies `P1G0SubtitleProbe` into **Android `src/debug` and `src/release` source sets**, plus the self-authored SRT fixture into **debug assets only**. The release variant's `prepare()` is a no-op; the debug variant is default OFF.
- On a user-selected **VLC** play request, only when the marker `filesDir/p1-g0.enable` exists, copies the SRT asset into `filesDir` and appends a `SubFile(lang=vi)` to **only the current item**. No hot-add, arbitrary SRT file picker, persistence or per-series mapping is implemented.
- No Android permission, Windows share, network listener, service, router, database, model, AIOS file or upstream Git commit changes.

## Pinned inputs and location

- OMP `spacesarmat/omp` at `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`.
- `android/vendor/2160player` at `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`.
- Run only in a **clean, disposable, isolated OMP worktree** on the app's dedicated runner/workspace (not AIOS), after source/license/security and execution authorization. The existing historical upstream build only proves that baseline toolchain once passed.

## Operator steps (manual, authorized session only)

1. Clone the pinned OMP source and submodule into a disposable location under the dedicated runner workspace; verify SHA, license, and worktree clean. Do not import wholesale into `main`.
2. With the app repo checkout providing these files, run: `powershell -NoProfile -File .\poc\g0\apply.ps1 -OmpRoot <ISOLATED_OMP_DIR> -AppRepoRoot <APP_REPO_CHECKOUT>`.
3. Run: `powershell -NoProfile -File .\poc\g0\verify.ps1 -OmpRoot <ISOLATED_OMP_DIR>`. This is **static only**, not compiler PASS.
4. On the dedicated authorized runner, build with the locked package manager / pinned toolchain: `npm ci --no-audit --no-fund`, `npm run android:sync`, then `cd android; .\gradlew.bat assembleDebug testDebugUnitTest --no-daemon --console plain`. Preserve the exact source/patch Git state and APK SHA256. Existing machine-scoped Java/SDK settings must remain untouched.
5. Inspect the debug APK for the G0 asset and release source-set/packaging expectations separately (release artifact cannot be claimed PASS unless actually built/inspected). Keep the APK private; do not publish/sideload automatically.
6. **Only with permission to access Redmi TV/ADB:** install the debug APK, select VLC explicitly in OMP settings, open a rights-cleared video with duration ≥ 18 seconds. Debug application ID per upstream Gradle is `com.spacesarmat.omp.test` (verify installed ID before use).
7. G0 marker is OFF by default. To opt in on the running/debuggable app: `adb shell run-as com.spacesarmat.omp.test touch files/p1-g0.enable`. Reopen the selected video to trigger `PlayerActivity.load()`. To disable: `adb shell run-as com.spacesarmat.omp.test rm files/p1-g0.enable`.
8. Test VLC audio/video and 2–17 s UTF-8 cues, remote subtitle track ON/OFF, pause/seek. Read marker alone does not mean the asset was rendered. Record firmware/API/ABI, APK SHA, log without URLs/secrets and real device evidence.

## Verification boundaries from V1 audit

| Gate | Proof boundary | Status |
| --- | --- | --- |
| F-01 / G0 | Debug-local predeclared SRT renders with audio/remote on real TV | `UNVERIFIED` |
| F-01 / G1 | Arbitrary file **outside APK** can be imported, track persisted without reinjection | **Not implemented** |
| F-02 / G3 | Controlled video/cue timing, not merely Unicode display | **Not implemented** |
| F-03 / G4 | Release build excludes debug behavior/fixture | Release no-op source-set prepared; artifact **UNVERIFIED** |
| F-04 | Exact pinned source, license, dedicated runner, real-TV proof and AIOS route (if used) | **Partially verified historically**, fresh gates pending |

**STOP:** SHA, license, dirty worktree, disallowed executor, unavailable VLC, unsafe credentials/logs, unexpectedly required Windows/TV configuration, or any pressure to claim `EXTERNAL_SRT_E2E_PASS` from this G0 patch.

Rollback the disposable worktree (prefer discard), or restore the one modified `PlayerActivity.kt` and remove only the two G0 Kotlin source-set files plus debug SRT asset. Nothing in `main` is changed by this branch.

## G0 runner build handoff — prepared, NOT executed

- `poc/g0/build-on-runner.ps1` is the **manual, fail-closed runner build script**. It checks exact GitHub Actions app repo/runner identity, workspace isolation, clean app checkout, pinned OMP+2160 source, SDK/JDK/toolchain, and invokes `apply.ps1` + `verify.ps1` before npm/Gradle. It writes `SHA256SUMS.txt` and a sanitized `P1-G0-BUILD-EVIDENCE.txt`, and verifies the debug APK contains the SRT fixture. It never installs on TV or changes Windows machine-scoped settings.
- `poc/g0/manual-workflow.template.yml` is a **non-active workflow template** deliberately outside `.github/workflows/`. It references immutable app patch source commit `8bcd3cbc2890a2d0d9ce449f24171b4e0813422b` so later documentation edits cannot silently alter the executable code. It requires a separately authorized, manual-only `workflow_dispatch` workflow on the default branch to run.
- When an authorized operator adds the template under `.github/workflows/p1-g0-manual.yml` on `main`, they can go to **GitHub → Actions → Torrent TV - P1 G0 Manual Debug Build → Run workflow**. It should publish only a private 7-day APK/checksum/evidence artifact. **This repository tool connection cannot dispatch Actions directly; no run is triggered by adding this template.**
- No trigger for `push`, `pull_request`, `schedule` or `workflow_run` is included. The existing `omp-fast-build.yml` still builds the unmodified OMP upstream and must **not** be mistaken for a G0 build.
- For manual execution inside a confirmed dedicated GitHub Actions job after checkout of the pinned PR #11 code: `powershell -NoProfile -File .\poc\g0\build-on-runner.ps1 -AppRepoRoot $env:GITHUB_WORKSPACE`. Running from an ordinary shell must stop. Never bypass its preflight to claim PASS.
- After the job finishes, verify exact commit + SHA256 evidence and inspect any failure traces (redact credential-bearing URLs). Real-TV G0 remains `UNVERIFIED` until an authorized Redmi test. G1 arbitrary-file import remains not implemented.

**Stop conditions:** runner offline, branch/head drift, missing/changed license or pins, Gradle/toolchain mismatch, failed artifact asset inspection, exposed secrets, unauthorized CI/Windows changes. Do not auto-merge PR #11, enable continuous CI, bypass AIOS governance or infer TV PASS from compile success.
