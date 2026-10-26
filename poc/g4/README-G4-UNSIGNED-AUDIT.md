# G4 — one-shot unsigned release-variant binary audit (human opt-in)

**Scope explicitly authorized 2026-10-27:** the Human approved a single G4 artifact build/inspection on the dedicated Torrent TV runner, with a **narrow, temporary, disposable-only exception** to upstream OMP's signing-key-required release task guard. No signing key, TV install, production release, publication, AIOS action, repo merge or persistent Windows/network modification. Approval is specific to this inspected G4 artifact and does not amend Product Contract, PRD or upstream policy.

## Provenance / deliberate exception

- Human real-TV G1d warning debug UX-01..UX-05 **5/5 PASS** on local + installed PR29 debug APK SHA256 `8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85`; this does **not** imply release-artifact safety. See [evidence ledger](../../planning/P1A-G1D-UX-EVIDENCE-LEDGER-20261027.md).
- PR29 source `dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92`. The audit script checks the *four exact PR29 G1c helper blob hashes* before applying them.
- Pinned OMP upstream `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, 2160player `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`.
- Pinned upstream `android/app/build.gradle` Git blob `d0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429`, containing a deliberate `gradle.taskGraph.whenReady` exception when `ANDROID_KEYSTORE_FILE` is unset. The G4 script first verifies that exact original Gradle blob, then removes ONLY that one else-side `whenReady` throw in the **disposable OMP clone**, without modifying `signingConfigs.release`, setting any keystore, changing source sets, or using debug keys. It asserts the one-line addition and emits `G4_ONE_DISPOSABLE_SIGNING_GUARD_EXCEPTION_PASS`.
- Release APK is therefore an **unsigned G4 audit variant with a documented build-config exception**, not an exact production-signed release; do not install/distribute or claim production-complete G4 from it.

## Workflow access without a merge to main

On `main`, GitHub already has the **same path** `.github/workflows/p1-g1d-ux-pr29-manual.yml`, containing the original **PR29 debug workflow**. This Draft branch adds a different **G4-only manual workflow at that path**, locked to **the one Draft branch** `poc/p1a-g4-unsigned-release-audit-20261027`. GitHub workflow dispatch supports choosing a branch for a workflow that exists in `main`; do not choose `main` or you will run the older debug workflow instead.

At the time of creating this script, the immutable checkout of `poc/g4/G4-Unsigned-Release-Audit-On-Runner.ps1` is commit `8f9126cc4e8a4cb033be903709213c5ff9e2b5d1`; workflow uses pinned checkout of exactly that source. PR #36 workflow branch HEAD should be checked immediately before dispatch for unexpected drift.

**Human GitHub UI — one authorized run only:**

1. Go to [Torrent TV Vietsub Actions](https://github.com/trung-via/torrent-tv-vietsub/actions), select the workflow named **Torrent TV - G1d UX PR29 Manual Debug Build** (GitHub may display the main branch's title; the path is `p1-g1d-ux-pr29-manual.yml`).
2. Click **Run workflow**, select **Use workflow from** → `poc/p1a-g4-unsigned-release-audit-20261027` (**not** `main`). Confirm the G4 branch is unchanged from the pinned reviewed PR #36 head.
3. Under the single `confirmation` input, type exactly `G4_UNSIGNED_AUDIT_ONCE`. Do not use the older `BUILD_PR29_ONCE` token.
4. Click **Run workflow** exactly **once**. If the UI still displays the old debug approval input or the branch is missing, STOP rather than selecting `main` or guessing.
5. When the job has completed, share **one link** to the workflow run and overall success/failure. The assistant can then read the exact runner/log/artifact metadata and document G4 outcome; no need for screenshots, private URLs or raw logs.

Alternative using GitHub CLI after authenticating to this repo (no automatic assistant dispatch):

```powershell
gh workflow run p1-g1d-ux-pr29-manual.yml --repo trung-via/torrent-tv-vietsub --ref poc/p1a-g4-unsigned-release-audit-20261027 -f confirmation=G4_UNSIGNED_AUDIT_ONCE
```

**One-shot source/runner guards:** `workflow_dispatch` only (no push/PR/schedule trigger), exact repo, branch, workflow path, `torrent-tv-vietsub-win`, isolated `C:\TOOL\TorrentTV-Runner\_work`, clean immutable audit-source checkout, pinned four PR29 blob hashes, pinned upstream OMP/submodule/Gradle, no signing-related environment variables. The job aborts if any mismatch is seen.

## Binary inspection

An authorized run builds `assembleRelease` in the disposable checkout and attempts to check **every generated release APK** (ARM64, ARM32, universal, if emitted): raw ZIP asset list and classes DEX G1c markers; `apkanalyzer` manifest debuggable flag and production applicationId; `apkanalyzer dex code --class ...P1G1CSubtitleRegistry` to assess the compiled release helper; `apksigner verify` must reject the artifact as **unsigned**. A failed tool, ambiguous binary, unexpected debug strings or unexpected signing is **BLOCKED/FAIL**, never silently ignored. The script does not use ADB, modify TV, sign, upload to public storage, or replace a release.

**PASS markers only if the full binary checks pass:**

```text
G4_PR29_SOURCE_BLOBS_PASS
G4_ONE_DISPOSABLE_SIGNING_GUARD_EXCEPTION_PASS
G4_ASSEMBLE_RELEASE_UNSIGNED_PASS_NOT_G4_BINARY_PASS
G4_UNSIGNED_AUDIT_BINARY_INSPECTION_PASS
G4_UNSIGNED_ARTIFACT_ONLY_NOT_PRODUCTION_OR_TV_PASS
```

After success, the private GitHub artifact `g4-unsigned-audit-pr29` contains the **unsigned test APKs**, `SHA256SUMS-G4.txt` and `G4-UNSIGNED-AUDIT-EVIDENCE.txt`; retention **7 days**. It is not installable/release-ready and must never be redistributed as a production APK.

**STOP conditions:** runner/path/branch drift, incompatible toolchain or PowerShell parse error, signing env/secret present, Gradle diff mismatch, release compilation failure, manifest debuggable, release helper not provably no-op, debug SRT/marker present in APK, APK unexpectedly signed, artifact missing. If stopped, preserve existing TV app/SRT and report the run link; do **not** rerun automatically or fall back to debug. Real release production-equivalence and G4 shipping approval remain separate.

## Failed runner attempts and targeted fix (2026-10-27)

The Human ran the manual G4 action twice on the original pinned branch/head:

- [Run #40375155558](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40375155558): FAILURE.
- [Run #40375407588](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40375407588): FAILURE.

Both logs passed `G4_PR29_SOURCE_BLOBS_PASS` and then stopped with `BLOCKED: Node, JDK or APK inspection tool missing` at line 63 of the initial audit script. This happened **before the OMP clone, Gradle modification or release assembly**; no release APK was built or TV changed.

Static investigation of the original script found an unconditional preflight bug: it assigned JDK21/JDK17 **folder paths** and subsequently tested those with `Test-Path -PathType Leaf` (**file-only**) instead of `Container` (folder). Thus the old code would fail even with properly installed JDKs. It also hard-coded `build-tools/36.0.0/apksigner.bat` instead of resolving `apksigner.bat` from installed build-tools. Historical dedicated runner preflight [run #40154251565](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40154251565) documented Android build-tools **37.0.0** plus Node and JDK.

This Draft fixes **both** issues: JDK dirs checked as `Container`, file executables as `Leaf`, installed build-tools searched for `apksigner.bat`, individual `G4_PREREQ_<NAME>_PASS` output and explicit missing component STOP. It also switches UTF-8 output construction to PowerShell 5.1-compatible `[Text.UTF8Encoding]::new($false)`. The workflow now checks out the repair at `8f9126cc4e8a4cb033be903709213c5ff9e2b5d1`.

**No new runner execution has happened after this repair.** Do not retry failed runs because they use the old immutable checkout. If the Human approves a new invocation, dispatch a NEW run from this same G4 branch only once and read its result; if a different missing tool is named, diagnose it before any further runs. Never self-install SDK/JDK, change Windows services, dispatch AIOS, use `main`, or treat a prerequisite BLOCKED as an APK G4 failure.
