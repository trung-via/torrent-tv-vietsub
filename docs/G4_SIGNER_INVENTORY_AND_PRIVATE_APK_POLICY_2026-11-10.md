# G4 — Read-only signer/inventory and private Release artifact boundary

**Date:** 2026-11-10 (Asia/Ho_Chi_Minh)  
**Status:** `WINDOWS_SIGNER_TOOL_INVENTORY_PASS / SIGNING_CONFIG_NOT_PRESENT_IN_HOSTOPS_JOB / G4_SIGNED_APK_NOT_RUN`  
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
- `G4_SIGNER_INVENTORY=READONLY_WINDOWS_PASS` — [HostOps #42680824158](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42680824158), owner-command job `129374554038`, exact tested commit `b3f6aa218ce9eb7c57d26423a881af7a9595a47a`; no secrets or signing run.
- `G4_RELEASE_KEYSTORE_APPROVED=NOT_ESTABLISHED`
- `G4_B2_SIGNED_BINARY=NOT_RUN`
- `G4_B3_PRIVATE_APK_HANDOFF=NOT_RUN`
- `G4_T1_REDMITV_RELEASE=NOT_RUN`

No AIOS/AI Commerce runners, secrets, services or workflows are involved.

## Actual dedicated Windows result — 2026-11-10 ICT

Owner-only [HostOps issue #82 command](https://github.com/trung-via/torrent-tv-vietsub/issues/82#issuecomment-6748941345) executed on dedicated Windows runner at [run #42680824158](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42680824158), job `129374554038`, exact source branch commit `b3f6aa218ce9eb7c57d26423a881af7a9595a47a`. GitHub returned job conclusion **success**. Verified real log markers:

- `G4_SIGNER_PROBE_DEDICATED_RUNNER_AND_SOURCE_PASS`
- `G4_KEYTOOL_JDK21=AVAILABLE`
- `G4_ANDROID_RELEASE_AUDIT_TOOLS=AVAILABLE`
- `G4_SIGNER_ENV_IN_HOSTOPS=NONE_PRESENT_NOT_PROOF_OF_ABSENCE`
- `G4_SIGNER_FILE_IN_HOSTOPS=NO_CONFIG_IN_THIS_JOB`
- `G4_PRIVATE_APK_DIR_IN_HOSTOPS=NO_CONFIG_IN_THIS_JOB`
- `G4_GITHUB_ACTIONS_RELEASE_SECRETS=NOT_INSPECTED_BY_ISSUE_COMMENT`
- `G4_SIGNER_CERT_FINGERPRINT=NOT_VERIFIED_BY_THIS_READONLY_PROBE`
- `G4_PRIVATE_APK_VAULT_ACL=NOT_VERIFIED_BY_THIS_READONLY_PROBE`
- `G4_SIGNER_READONLY_INVENTORY_COMPLETED_NOT_RELEASE_PASS` and `HOSTOPS_PINNED_JOB_PASS`

**Interpretation:** the dedicated runner has the necessary tool executables for future signer and APK checks. However, this Issue #82 HostOps environment was given **no** G4 signing variables and **no** configured private output path. The result **cannot prove** absent keystore on the laptop or absent GitHub Release Secrets: those were intentionally not inspected. The code in this PR read no secret file and made no host changes. This is `INVENTORY_PASS_WITH_SIGNING_HOLD`, **not** G4 Release acceptance.
