# G4-B1/B2 — Signed Release builder candidate (SOURCE ONLY)

**Status:** DRAFT / WINDOWS_STATIC_GUARDS_PASS / MANUAL_SIGNING_NOT_AUTHORIZED / SIGNED_RELEASE_NOT_RUN
**Owner issue:** [#95](https://github.com/trung-via/torrent-tv-vietsub/issues/95)
**Baseline:** Torrent TV main a03b4b113a23f601ab9caabe84bcfa212f055072, merged G1+P2+Font v3, [preflight PR #100](https://github.com/trung-via/torrent-tv-vietsub/pull/100) and [actual HostOps #42675088058](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42675088058) source-only PASS.

## Proposed files

- poc/g4/release-v3-builder.ps1 — manual-only Release builder on the dedicated Torrent TV Windows runner. It pins current main SHA, OMP 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f, 2160player 6ba6edd39f5d986ddfae29b5425b8ac0b319844e, Gradle build.gradle blob d0c7a13bf8ad5108e4b82d5bbac8ffd7d522b429, accepted Font v3 Git blobs. Compose G1 Production → P2 → Font v3, run Node/P2/Android unit tests and **only with approved private signing material** run assembleRelease in disposable OMP checkout. Does not bypass upstream signing guard.
- poc/g4/audit-v3-apk.ps1 — verify Release applicationId com.spacesarmat.omp, absence of application-debuggable marker, ARM32 lib, P1ProductionSubtitles DEX presence, absence of historical G0/G1c fixtures, apksigner verification and exact **approved Release certificate fingerprint**, with SHA256 per APK.
- .github/workflows/g4-v3-signed-release-manual.yml — inert until merged; owner-only workflow_dispatch on main with exact phrase SIGN_G4_V3_RELEASE_ONCE, pinned checkout, dedicated runner. There is **no upload-artifact, push, schedule, PR or deployment trigger**.
- hostops/jobs/g4b1-static.ps1 — separate no-key/no-Gradle owner-only static review on dedicated Windows via Issue #82 HostOps, exact branch/commit pin, PowerShell syntax and guards.
- This document describes evidence boundaries and future approvals.

## Signing identity — separate future Human decision

**Missing at previous G4 preflight:** G4V3_SIGNING_ENV=INCOMPLETE_OR_NOT_IN_THIS_JOB. This only means signing values were not supplied to that HostOps job. It does **not** establish whether a private key exists elsewhere.

If Human **separately** authorizes an actual signed build, these GitHub **secrets** must first be explicitly and privately provisioned (do not put values into issues, PRs, repository files or screenshots):

| Secret | Role |
| --- | --- |
| TORRENTTV_RELEASE_KEYSTORE_FILE | Absolute Windows path to an existing private Release keystore outside runner workspace; not a Debug key |
| TORRENTTV_RELEASE_KEYSTORE_PASSWORD | Keystore password |
| TORRENTTV_RELEASE_KEY_ALIAS | Existing approved Release signing alias |
| TORRENTTV_RELEASE_KEY_PASSWORD | Alias/key password |
| TORRENTTV_RELEASE_CERT_SHA256 | Fingerprint of the approved **Release** signing certificate; must differ from OMP public Debug signer |

This PR does **not** create a private key, choose an alias, grant access to any secret, publish an APK or trigger the workflow. No Debug key substitution, Gradle guard removal, unsigned PR #36 reuse, key logging, plaintext secret or remote signing service. The builder removes secrets from child npm environment before running dependency scripts and scopes Android signing variables to the Gradle release invocation.

## Exact acceptance sequence after approval

1. Human reviews/merges builder PR separately from authorizing signing. Merge **alone** triggers nothing.
2. Human approves **one bounded signed build**; provision private signing identity and expected cert fingerprint. Invoke manual workflow on trusted main with exact confirmation. If config absent/wrong, the builder must fail closed.
3. Verify actual signed binary with aapt2, apksigner, ZIP/DEX evidence and checksums, with exact immutable source and run ID. Keep signed APK **ephemeral/private**; builder deletes disposable clone and APK even when audit succeeds. The public Actions step summary contains only source SHA, success type and SHA256 digests, no APK bytes or signing secrets.
4. A separate private-artifact retention/handoff mechanism is needed before any install. **No ADB, no TV install, no publication in this PR.** Release applicationId com.spacesarmat.omp differs from installed Debug com.spacesarmat.omp.test; saved SRT and track preferences do not automatically migrate.
5. After separate Human authorization for installation and rollback, test real Redmi ARM32 Release binary: picker SRT/VTT, ON/OFF/OTHER, A→B→A, restart, post-seek sync and lack of Debug-only fixture.

## Gate separation

- G4-S5 G1+P2+Font v3 source composition — **PASS** via actual prior Windows job.
- G4-B1 code/guard **static review** — PASS on real dedicated Windows HostOps [run #42678315158](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42678315158), owner-command job 129365640330, exact tested source commit 6481ac76845858dc627c68f6f46c1c815eed19dc. Static job logs: G4B1_STATIC_POWERSHELL_SYNTAX_PASS, G4B1_STATIC_OWNER_ONLY_MANUAL_SIGNING_GATES_PASS, G4B1_STATIC_BINARY_AUDIT_PRESENT_PASS, G4B1_STATIC_NO_APK_BUILD_SIGN_UPLOAD_OR_TV_ACTION_PASS and HOSTOPS_PINNED_JOB_PASS. Only syntax/required guards validated; actual signed build/binary remains NOT_RUN.
- G4-B2 signed APK build, manifest, ABI, signature/DEX and private SHA — **NOT_RUN**, requires separate Human signing approval and approved Release keystore.
- G4-B3 private artifact retention and G4-T1 TV acceptance — **NOT_RUN**.

**Security/privacy boundary:** Repository is currently PUBLIC. Do not include signing keys, signed APK, personal file paths, tracker passkeys, private media names or device credentials in GitHub public issue logs. This is independent Torrent TV engineering, not AIOS or AI Commerce.
