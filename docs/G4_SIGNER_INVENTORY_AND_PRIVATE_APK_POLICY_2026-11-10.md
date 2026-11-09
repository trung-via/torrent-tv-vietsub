# G4 — Read-only signer/inventory and private Release artifact boundary

**Date:** 2026-11-10 (Asia/Ho_Chi_Minh)  
**Status:** `SIGNER_INVENTORY_SOURCE_PREPARED / G4_SIGNED_APK_NOT_RUN`  
**Owner:** [Issue #95](https://github.com/trung-via/torrent-tv-vietsub/issues/95)

## Live baseline

- Torrent TV `main` after Human-approved [PR #101](https://github.com/trung-via/torrent-tv-vietsub/pull/101): `547e31717cd2dc256b1c0e43033305dd0e5d2aca`.
- The G1 Production → P2 → accepted Font v3 **source composition** passed [Windows HostOps #42675088058](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42675088058).
- The signed Release builder's **PowerShell syntax and guard-presence** passed [Windows HostOps #42678315158](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42678315158). That was **not** a Gradle or signer test.
- Current G4 manual workflow `.github/workflows/g4-v3-signed-release-manual.yml` expects five GitHub **secrets**, and the builder expects an existing private keystore and approved certificate fingerprint. Secret *references* in YAML do **not** establish that the actual values or files exist.

## Inventory scope

`hostops/jobs/g4signer-inventory.ps1` checks only the dedicated Torrent TV Windows runner's local toolchain and the presence of explicitly configured paths **in that particular HostOps issue-comment job**. It never prints a file path, secret, certificate identity or keystore bytes; it never enumerates private folders or opens a keystore. It does **not** call `keytool -list`, sign, build or install.

- Reports whether JDK 21's `keytool.exe`, `apksigner.bat` and `aapt2.exe` exist at the expected runner toolchain locations.
- Checks whether the specific process was given five `G4_RELEASE_*` environment names, and whether a **configured** keystore path points to an existing file outside the dedicated runner workspace.
- Checks whether an **explicitly configured** `G4_RELEASE_PRIVATE_OUTPUT_DIR` exists outside the runner workspace; it does not audit ACL and never writes there.
- An unconfigured path is `NO_CONFIG_IN_THIS_JOB`, **not** evidence that a key or private vault doesn't exist elsewhere.
- Separately records `G4_GITHUB_ACTIONS_RELEASE_SECRETS=NOT_INSPECTED_BY_ISSUE_COMMENT` because the Release workflow's secret inputs are not injected into the independent Issue #82 HostOps job.

## Next distinct authorizations and storage policy

**G4 signer:** Owner first chooses an existing authorized Release identity, or **explicitly approves** generating a new one in private storage. Provision the keystore privately, its approved certificate SHA-256, alias and passwords. Do not write anything to GitHub source, comments, logs or artifacts. Never reuse the OMP public Android Debug keystore. Before dispatching `SIGN_G4_V3_RELEASE_ONCE`, verify actual secret availability through a separately reviewed mechanism **in the manual workflow context**, not by assuming HostOps's unrelated environment is representative.

**G4 private APK handling:** The PR #101 builder currently **deletes signed APKs together with its temporary OMP clone** after audit and only writes checksums to a public Actions summary. This is fine for a one-time binary audit but does **not** provide an APK that can later be installed on Redmi. A subsequent, separately reviewed G4-B3 change must implement owner-approved private archive/handoff (e.g. a local vault outside `_work` with restricted ACL and checksum/provenance) with no automatic public upload, overwrite or retention surprise. Do not create/modify an archive location merely for this inventory.

**G4 Redmi:** `com.spacesarmat.omp.test` Debug and `com.spacesarmat.omp` Release are separate applicationIds. Preserve the installed Debug/data and require a separate explicit approval for Release install and on-device SRT/VTT, ON/OFF/OTHER, A→B→A, seek and resume tests.

## Gate states

- `G4_S5_SOURCE_COMPOSITION=PASS` (prior real Windows run).
- `G4_B1_BUILDER_STATIC=PASS` (prior real Windows run).
- `G4_SIGNER_INVENTORY=NOT_YET_RUN` at initial source creation; attach exact new Windows job/result to change state.
- `G4_RELEASE_KEYSTORE_APPROVED=NOT_ESTABLISHED`
- `G4_B2_SIGNED_BINARY=NOT_RUN`
- `G4_B3_PRIVATE_APK_HANDOFF=NOT_RUN`
- `G4_T1_REDMITV_RELEASE=NOT_RUN`

No AIOS/AI Commerce runners, secrets, services or workflows are involved.
