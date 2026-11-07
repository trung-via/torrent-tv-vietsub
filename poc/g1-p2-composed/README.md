# G1 + P2 composed Debug build — Torrent TV Vietsub

**Decision:** preserve Human-tested G1 Production external SRT/VTT implementation while adding P2-SOURCE.3 opt-in reported-metadata UI to the **same** pinned OMP Android build. User approved continuing this composition on 2026-11-07. This is independent of AIOS/AI Commerce.

## Inputs and exact sequence

1. Owner triggers `.github/workflows/p1-g1-p2-composed-manual.yml` on `main` with `BUILD_G1_P2_DEBUG_ONCE`. **No background or automatic build.** Workflow checks Owner, repo/ref, exact `github.sha`, dedicated Windows Torrent TV runner and isolated workspace.
2. Checkout reviewed `main` commit and independently pin OMP `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` plus its 2160 submodule `6ba6edd39f5d986ddfae29b5425b8ac0b319844e` in a disposable `p1-g1-prod-* ` checkout.
3. Run existing `poc/g1-prod/apply.ps1` and `poc/g1-prod/verify.ps1` unchanged. These verify media-bound external SRT/VTT, OFF/ON/OTHER and source/test hashes.
4. Only after G1 static PASS, invoke reviewed `poc/p2-source/omp-ui/apply.mjs`, which checks pinned OMP `src/screens/Add.tsx` original blob and requires changes limited to G1 file paths. It adds default-OFF P2 reported size/seed priority, never an automatic add/download.
5. `npm ci` → focused `npx --no-install vitest run tests/sources/tvCandidateCheck.test.ts` → OMP `npm run android:sync` → Gradle `assembleDebug testDebugUnitTest`.
6. Check generated debug APK set for prohibited debug-only subtitle fixtures, compute per-file SHA256, write `SHA256SUMS-G1P2.txt` and `G1P2-BUILD-EVIDENCE.txt`; no ADB, install, package-name alteration, release signing, TorrServer change or TV data mutation.

## Public repository disclosure gate

GitHub currently reports `trung-via/torrent-tv-vietsub` as **PUBLIC**, despite older docs saying PRIVATE. The manual workflow deliberately **does not silently skip builds** because the repo is public. It uploads only manifest/checksum/evidence, without raw credentials or media URLs, on PUBLIC. It uploads APK binaries **only if GitHub reports PRIVATE** at dispatch. If the owner wants to retrieve an APK while PUBLIC, publishing the Debug artifact or transferring it from the trusted Windows runner is a separate explicit decision; never make an APK publicly distributable by accident.

## CI proof vs real hardware

`.github/workflows/tv-g1-p2-composition-ci.yml` runs on a GitHub-hosted Ubuntu runner with read-only token, parses PowerShell, checks ordering/source SHA/allowed effects, simulates a G1-modified OMP tree, then applies the real P2 overlay, runs Vitest and builds mobile UI assets. This test **does not** execute the Windows-only G1 Kotlin patch, build an APK or touch a real TV.

The previous installed Debug APK `c5a5bbd265e1353012165111d114b692b66ad783775eebdbc1408e1a668e82b6` has *Human-reported G1 5/5 functional PASS*. That acceptance does not automatically transfer to a new composed APK. For composed Debug APK: `SOURCE_CI`, `WINDOWS_APK_BUILD`, `APK_HASH_READBACK`, `G1_REGRESSION_ON_REDMITV` and `P2_TV_UI` are independent gates. Install without data wipe requires a separate explicit Human authorization and a signing-cert/package match. Production G4 release remains unverified.

## Rollback

Stop selecting the G1+P2 workflow, keep using the last SHA-verified G1 APK for the previously accepted feature. No host service, TV setting or TorrServer state changed by the source PR. The original `poc/g1-prod/build-on-runner.ps1` and manual G1 workflow remain unchanged.
