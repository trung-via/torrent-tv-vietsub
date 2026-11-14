# G2 Refresh Vietsub — source candidate v0.1 (VLC / G1)

**Purpose:** after the user explicitly picks an updated cumulative SRT/VTT while watching an authorized movie, apply the new G1-managed sidecar **without closing the PlayerActivity**, resume the same queue item at its observed position and restore paused state. This is **in-place media reload**: brief buffering/position drift can occur. It is **NOT** proven zero-interruption `libVLC.addSlave()` hot-add or TV acceptance.

## Exact dependency and scope

- Target: `spacesarmat/omp` with merged Torrent TV **G1 Production** patch already applied to a **disposable** `p1-g1-prod-*` checkout. G1 source lives under `poc/g1-prod/` in `trung-via/torrent-tv-vietsub`. This G2 overlay does not apply directly to pristine OMP.
- Engine: explicitly selected **VLC**; requires the G1 media key (profile ID, torrent hash, file index). No `AUTO`/Media3 promise.
- Source: `PlayerActivity.kt` G1 document-picker callback and two new G2 Kotlin classes. No changes to TorrServer, streams, LAN, TV storage permissions, Android manifest, release signing or Python Brain LEAN120 plugin.
- Content: the user selects the updated `.srt`/`.vtt`. G1 still performs UTF-8/content/size checks, app-private SHA storage and identity binding. No automatic access to a PC file or background model service is implied.

## What happens

1. After G1 `importSelected()` successfully stores a new version, the callback **rechecks the same `PlayerSession.request` object**, same media key, queue index, VLC engine and a live activity before reload. A changed session only gets a saved-for-next-open notice.
2. `G2RefreshInPlace.prepare()` removes at most one **previously G1-owned**, identity-scoped old `file://` sidecar from the **copied** queue item; rejects an impostor/path escape/multiple G1 labels; calls the existing G1 `prepare()` to insert the newly verified file.
3. The activity commits any pending seek, captures current position and paused state, captures the selected audio label/language, and snapshots per-item resume points. `session.load()` then reopens the same item **in place** with the new subtitle; paused sessions are paused again immediately.
4. On failure, the G1 import is still saved, and the user sees the original fallback instruction to reopen. No guessed subtitles or cross-item file sharing.

## Source-only tests run locally

- `python -m unittest -v test_apply.py` — 7/7 PASS; catches unexpected G1 source shape, reapply, wrong checkout, dry-run mutation and limited file patch.
- `kotlinc G2RefreshDecision.kt G2RefreshDecisionSmoke.kt -d policy-classes && kotlin -cp policy-classes com.spacesarmat.omp.player.G2RefreshDecisionSmokeKt` — 14/14 PASS on pure JVM guard, synthetic paths only.
- `kotlinc G2RefreshDecision.kt G2RefreshInPlace.kt stubs/*.kt -d integration-classes && kotlin -cp integration-classes com.spacesarmat.omp.player.G2IntegrationSmokeKt` — 7/7 PASS on **mocked** Context, PlayRequest, and G1 registry. **Not** actual Android Gradle build or real VLC runtime.

## Dry-run first; installation is not performed by this source candidate

```powershell
python .\poc\g2-refresh\apply.py --omp-root 'C:\path\p1-g1-prod-CLEAN'
# after reviewing dry-run and on an explicitly authorized disposable G1-applied checkout:
python .\poc\g2-refresh\apply.py --omp-root 'C:\path\p1-g1-prod-CLEAN' --apply
```

The script refuses any checkout not named `p1-g1-prod-*`, missing G1 anchors or already containing G2 source. It does **not** call Gradle, ADB, Windows services, GitHub workflows, or copy files to a TV.

## Acceptance gates remaining (do not merge based on smoke tests)

1. **Real Android Gradle compile/unit tests** on pinned G1-applied OMP source with exact APK SHA and runner evidence.
2. **Real Redmi A Pro 55 (China) / explicit VLC**: open lawful media A with cumulative 120-cue SRT; while playing import its 240-cue cumulative replacement; same PlayerActivity; near-identical position (record measured delta), video/audio resume and Vietnamese captions continue at cue 121+. Validate paused update, OFF/OTHER choice, seek, and A→B→A isolation. Repeat VTT case separately.
3. **Failure tests:** malformed/oversize UTF-8 file, picker canceled, stale callback after item change, spoofed `file://` URI, multiple G1 labels, inaccessible file, duplicate import; generic non-sensitive UX and no playback breakage.
4. **Real hot-add remains separate:** this patch reopens the media inside the player. To promise zero-buffering seamless G2, a different `VlcEngine.addSlave` path and real device proof are needed.

**Status:** G2-B1 Android Debug CI **PASS** on pinned commit `8721b87e7de9434472bb32e57aad2e387815d1d1` (Actions run `42942320322`); G2-B2 recovery source **CANDIDATE / AWAITING ITS OWN CI**, Redmi E2E **NOT_RUN**, true seamless hot-add **NOT_PROVEN**, G4 **NOT_RUN**. Do not deploy this B2 candidate or claim release readiness without independent verification. Licensed/source-only code, no movie dialogue.

## G2-B1 build-route checkpoint (2026-11-11; source prepared, not executed)

- New `poc/g2-refresh/build-on-runner.ps1`: validates owner/workflow/branch/SHA, permits **public or private** Torrent TV repository visibility while requiring the dedicated Windows runner/workspace; clones pinned OMP `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` and 2160player `6ba6edd39f5d986ddfae29b5425b8ac0b319844e`, runs existing G1 `apply.ps1` + `verify.ps1`, G2 patch unit tests/dry-run/apply, then `npm ci`, `npm run android:sync`, Gradle `assembleDebug testDebugUnitTest`; writes APK hashes + proof **only if successful**.
- New `.github/workflows/p1-g2-refresh-manual.yml` is `workflow_dispatch` only with `BUILD_G2_REFRESH_DEBUG_ONCE`, fixed branch and owner; checkout at the dispatch event SHA, actions pinned, no ADB/TV install, merge, signing or release; artifact retention is 7 days **when the repository is private**; for a public repository the upload step is skipped.
- **Registration completed:** dedicated tooling-only PR #116 registered this workflow on `main` (squash commit `f06a07ba0c3910bae6aa857509866f5da4e4692c`), byte-identical to the workflow on this Draft branch. The G2 implementation remains Draft/unmerged. Select the G2 feature branch explicitly when authorizing a separate manual dispatch; registration itself does not build an APK.
- As observed on 2026-11-11, the linked GitHub repository is **public**, although the historical merged contract describes PRIVATE as the intended configuration. By latest Human instruction, G2 Debug build no longer depends on repository visibility. An APK produced on the public repo's dedicated runner remains local to that runner; it is **not uploaded as an Actions artifact**. The premerge entrypoint is now registered through PR #116; the actual build/run has not been executed.
- **No Windows/PowerShell parser or Android build run was performed from this checkpoint.** No new APK SHA, Gradle test results or Redmi G2 E2E result exists for this change. G2-B2 restore-on-reload-failure remains separately open.

### Latest Human override — public-repository G2 Debug build (2026-11-11)

Human requested that the private-only execution condition be changed. This is a **scoped G2-B1 CI exception**, not a request to make GitHub visibility private or to publish a Debug APK. The main Contract's earlier PRIVATE intent remains historical until separately reconciled through governance.

- **Build authorization:** `workflow_dispatch` + exact confirmation + `github.actor == 'trung-via'` + G2 branch + immutable dispatch SHA + dedicated Windows runner; accepts both public and private repositories.
- **Public repository:** `assembleDebug testDebugUnitTest` may run under those guards. SHA256 and sanitized provenance can be read from build logs; unsigned/debug APK stays on the dedicated runner under its isolated temp checkout (subject to runner cleanup). GitHub artifact upload is skipped.
- **Private repository:** same build guards; guarded APK/hash/provenance upload may occur with 7-day retention after a successful build.
- **Workflow registration resolved:** PR #116 added the same workflow to default branch `main`. Do not merge G2 feature to build it. CI/Gradle/Redmi gates are still NOT_RUN until an authorized dispatch and actual logs/artifacts are observed.

## G2-B2 reload-failure recovery — candidate checkpoint (2026-11-11)

Problem identified from exact G1 source: `P1ProductionSubtitles.importSelected()` deletes the previous media-keyed SRT/VTT after committing the new file. Therefore, a simple `catch` around `session.load()` cannot return to the former subtitle track if the new VLC reload fails.

Candidate fix in this Draft branch:

- `G2RefreshRecovery.kt`: capture **up to 256 KiB** of only the previous app-private G1-owned SRT/VTT after media-key/path validation and **SHA256 contents-vs-filename check**. It does not back up ordinary external subtitles, torrent URLs or adjacent queue entries. If snapshot fails, the G2 picker path fails closed rather than deleting an old playing sidecar without rollback bytes.
- `apply.py`: inject scoped capture *before* G1 import, then arm a one-shot recovery for a specific refreshed `PlayRequest` object, media key and queue index. On synchronous `session.load()` failure, VLC error before first frame, or a 25-second **playing-only** first-frame timeout, try to put the previous validated bytes back at the original scoped file path and reopen previous playback at the captured position, audio pick and paused state. For a file-restore failure, fall back to video without that specific invalid G1 sidecar; never point to another media's captions.
- On successful new first frame, drop the in-memory snapshot. A stale callback, switched media, closed player or different request identity must not restore old media. Paused media does not use the 25-second frame timeout; its failure handling requires separate TV evidence.
- The newly imported file and G1 registry remain saved for the **next explicit open** even if the in-place reload is rolled back; this is not a transaction that rolls back the user's import selection. No guarantee of continuous playback during VLC reopen or recovery; the path is intended as fail-safe best effort and needs real-device checks.
- Synthetic Kotlin/JVM rollback cases are in `stubs/G2RecoverySmoke.kt` (not claimed executed by Android CI unless separately run); Python patch tests check fail-closed anchors. **B2 runtime recovery is not yet verified on real VLC/Redmi.**

### G2 Debug APK private-handoff preparation

`poc/g2-refresh/retain-private-arm32.ps1` is an **opt-in G2 CI-local retention candidate** adapted from the project's G1+P2 ACL-protected vault logic and now wired into the G2 feature-branch workflow *after* the successful Gradle build; its own execution/retained APK result remains unverified until a successful new run. It requires exact source/workflow/runner and run-artifact matching, a checked ARM32 APK SHA256, expected debug package ID and OMP debug signing certificate fingerprint, then copies to a dedicated `private-artifacts/G2B2/run-<id>-<attempt>` folder with inherited NTFS access disabled. Any signer failure leaves a quarantined private local copy, never a downloadable public artifact. It does **not** run automatically with the current workflow; it never installs APK/ADB/TV or exposes TorrServer.

Historical G2-B1 success: [run 42942320322](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42942320322), with three APK SHA256 values in its CI logs. Runner temp cleanup prevented independent post-run JUnit/XML and APK file re-read, and the public GitHub repo has APK upload disabled.

**Open gates:** G2-B2 Android compile/unit on its exact new commit, synthetic error-injection/rollback execution, then authorized Redmi G2 matrix and separate private APK retention/handoff acceptance. No PR merge, release, signing or physical TV change is implied.

### G2-B2 compilation checkpoint and strengthened test gate (2026-11-11)

- [G2 Android CI run 42948309167](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42948309167) **SUCCESS** for B2 recovery source at immutable commit `cc0e2b6b0ff137c3b7943a33838ee4e0c79ad0fe`: 9 Python patch tests, G1+G2 source apply, targeted previously failing LG JUnit test, full Android `assembleDebug testDebugUnitTest`; SHA256 of three Debug APKs logged. This is **compile/CI proof only**, not proof the VLC error path executes successfully on a Redmi.
- After that proof, G2's feature workflow added a **separate Ubuntu/Kotlin synthetic rollback smoke gate** (sources `G2RefreshRecovery.kt`, `G2RefreshDecision.kt`, `stubs/FakeAndroid.kt`, `stubs/FakeOmp.kt`, `stubs/G2RecoverySmoke.kt`) whose PASS is now a prerequisite of the dedicated Windows build. Its first actual execution result must be observed before claiming synthetic recovery PASS.
- The same workflow now calls the guarded `retain-private-arm32.ps1` only following a successful full Android build. APK handoff **remains local to** the dedicated Windows runner; never GitHub public artifact, ADB, TV installation or release.
- The 25-second no-first-frame fallback applies to **playing** sessions. Paused recovery and actual stalled VLC/codec/network faults need additional real-device or controlled fault-injection proof. The earlier G2-B1 Android CI evidence remains pinned to its own commit.
