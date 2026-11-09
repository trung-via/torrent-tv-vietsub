# G4-B1 preparation — accepted Font v3 Release source preflight

**Date:** 2026-11-10 · **Gate:** [Issue #95](https://github.com/trung-via/torrent-tv-vietsub/issues/95) · **Status:** `SCRIPT_PREPARED / WINDOWS_G4V3_COMPOSITION_PENDING / SIGNED_RELEASE_NOT_RUN`.

## Source authority and why the prior G4 proof is insufficient

- Current accepted Torrent TV `main`: [`150f9b7d1c7e534f2e0f861ea9e8856f20bf4a1f`](https://github.com/trung-via/torrent-tv-vietsub/commit/150f9b7d1c7e534f2e0f861ea9e8856f20bf4a1f), [Font v3 PR #99](https://github.com/trung-via/torrent-tv-vietsub/pull/99) MERGED.
- G4 readiness [PR #94](https://github.com/trung-via/torrent-tv-vietsub/pull/94) and [Windows HostOps run #42642118985](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42642118985) had **only G1 Production + P2**. Their source-composition PASS does **not** prove Font v3 included in any Release.
- The final v3 renderer source/test blobs are identical to those previously built and installed on real Redmi (see [Issue #96](https://github.com/trung-via/torrent-tv-vietsub/issues/96)), but those were **Debug** APK facts, not Release.
- Upstream OMP is pinned to `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, submodule 2160 `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`, LibVLC 3.7.7, Gradle `android/app/build.gradle` blob `d0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429`.

## New bounded preflight

`hostops/jobs/g4v3-preflight.ps1` is derived from the previously tested `hostops/jobs/g4readiness.ps1`, with a **minimal additive Font v3 composition check**, not an alternate builder. Runs only on owner-approved, SHA-pinned `hostops/g4v3-preflight` using existing Issue #82 HostOps command and dedicated Windows `torrent-tv-vietsub-win`.

1. Verify exact trusted repo checkout, clean branch, dedicated runner identity/worktree, input script presence and **merged PR #99's exact Font v3 Git blob SHA**.
2. Run Node Font v3 unit tests; create a uniquely named disposable, pinned OMP/2160 checkout in runner temp.
3. Apply **G1 Production → P2 UI → Font v3**, then run each source verifier. Check native subtitle helper stays in `src/main`, no G0/G1c source fixtures, and Gradle Release signing guard is intact.
4. Report whether all four existing upstream Release signing environment fields are present **without printing names, values, paths, keystore content, or secrets**. The marker is informational; it does not verify any key or certify readiness.
5. Cleanup temporary OMP checkout. No `assembleRelease`, binary output, signing, key creation, workflow override, APK upload, ADB, TV changes, Windows service, firewall or TorrServer operation.

**Hard stop:** any SHA drift, wrong host/event, failed source test, composition error, signing-guard removal, unexpected fixture. No fallback to AIOS/Commerce, Debug signing or historic unsigned G1c PR #36.

## G4 gates after the preflight (separately authorized)

| Gate | To prove | Current status |
|---|---|---|
| **G4-S5** | Actual Windows G1+P2+Font v3 composed source and signing-guard preflight, exact runner/run/source | `PENDING_HOSTOPS_RUN` |
| **G4-B1/B2** | Approved private Release keystore and **manual-only** signed `assembleRelease` for the exact accepted source; then check manifest `debuggable=false`, applicationId, ABI, compiled G1 helper, absent G0/G1c fixtures, `apksigner verify`, SHA and build provenance | `NOT_RUN / SIGNING_AUTHORITY_PENDING` |
| **G4-T1** | Separately authorized Redmi installation, preservation of existing Debug package and user data, actual SRT/VTT import, ON/OFF/OTHER, A→B→A, post-seek sync and restart/resume, rollback | `NOT_RUN / TV_INSTALL_AUTHORITY_PENDING` |

**Release package boundary:** upstream Gradle uses Release `applicationId=com.spacesarmat.omp` and Debug `applicationIdSuffix=.test`. Consequently, Release may install side-by-side with `com.spacesarmat.omp.test`; **do not assume the saved SRT/track state migrates across packages**. Also note upstream code may include a separate embedded TorrServer helper; this preflight does not authorize any server runtime changes or binaries.

The repository is currently **PUBLIC**. Keystore, passwords, signed APK and user content remain private; do not publish Release artifacts under this source-only PR.

**Decision boundary:** a successful `G4V3_SOURCE_COMPOSITION=PASS_NOT_BINARY_OR_RELEASE_PASS` unblocks **design/review of the signed candidate builder**, not Release acceptance. Human must approve signing, artifact handling and TV deployment in their own scoped steps.
