# G1 + P2 combined OMP Debug build — 2026-11-07

## Product scope and provenance

This is a **new build path** for one G1+P2 Debug APK, using OMP commit `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` and 2160player submodule `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`. The source branch is separate from the existing, real-Redmi-accepted G1 production test and does not alter the accepted original `poc/g1-prod/build-on-runner.ps1` or `.github/workflows/p1-g1-production-manual.yml`.

**Exact overlay order:**
1. Dedicated Torrent TV Windows self-host runner validates its identity, repo, workspace and exact immutable source commit.
2. Clone pinned disposable OMP and its recursive player submodule; run reviewed `poc/g1-prod/apply.ps1`, then `verify.ps1`.
3. Apply reviewed P2 `poc/p2-source/omp-ui/apply.mjs` *after* G1. It checks the original `Add.tsx` blob and allowlists only the G1 worktree changes.
4. Run focused 8-case P2 Vitest tests, `npm run android:sync`, then Android `assembleDebug testDebugUnitTest` in the exact same OMP checkout.
5. Verify no earlier G0/G1c debug-only subtitle fixture in the APK, hash each output APK, and publish distinct `SHA256SUMS-G1P2.txt` and `G1P2-BUILD-EVIDENCE.txt`.

**Important:** This is a *Debug variant*, not a G4 signed/release artifact, and not evidence that the new APK has been installed or verified on Redmi. G1 separately had Human-reported real-TV SRT/VTT 5/5 PASS on its previous installed APK; that does not automatically validate a new combined APK. P2 metadata search view defaults OFF, uses reported 8–12 decimal GB and ≥300 reported seeders, cannot verify resolution, media audio tracks, actual peers or rights, and never automatically fetches/adds a torrent.

## Public repository artifact safety

The repository is currently **PUBLIC**. Do **not** assume any uploaded GitHub Actions artifact is private. The new workflow `.github/workflows/p2-g1-combined-manual.yml` is disabled for push/PR/schedule and operates **only** when an authenticated repo Owner manually dispatches it on `main`, entering the exact `BUILD_G1P2_DEBUG_PUBLIC_ARTIFACT_ONCE` confirmation. This confirms deliberate public access to the *Debug APK* and 3-day artifact retention. The source checkout is pinned to immutable commit `dbc0c1b04dc352bed0662fae899475f4e55425f0` (containing the unchanged G1 helper and newly reviewed combined runner). It never uses PR code for a self-hosted job. It never invokes ADB, changes TV data, launches TorrServer, changes services/network, signs or publishes a Release.

Do not dispatch the manual build merely because a PR merged or a CI preflight passed. A user-authorized build may follow independently, and a **separate explicit TV install approval** is required to change the real Redmi. Before any real install, record APK SHA256, package/versionCode/signing compatibility, preserve existing app data, and check rollback.

## Source preflight vs real build

`.github/workflows/tv-g1p2-composition-preflight.yml` uses a **GitHub-hosted Windows** job for isolated source guard tests, PowerShell parser verification and Node overlay syntax. It neither runs Gradle nor produces an APK. The successful P2-only OMP TypeScript/Vitest/UI build from PR #47 is historical proof of that specific overlay, not a combined G1+P2 APK.

**Acceptance states:**
- `G1_REAL_REDMITV_PASS_PREVIOUS_APK`: historical and scoped.
- `P2_OMP_UI_SOURCE_BUILD_PASS`: historical run #42066468764.
- `G1P2_COMPOSITION_PREFLIGHT_PASS`: only after current PR CI success.
- `G1P2_COMBINED_DEBUG_APK_PASS`: only with actual new Windows manual build, tests and immutable hash receipt.
- `G1P2_REAL_REDMITV_PASS`: only with actual user device observation after separately approved install.
- `G4_RELEASE`: independent, not granted by this work.

Rollback is to omit the separate combined-build workflow/overlay on subsequent builds; the previous G1 APK and Android data are untouched by this PR.
