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

**Status:** `SOURCE_CANDIDATE_ONLY`. `ANDROID_BUILD_NOT_RUN`, `REDMI_NOT_RUN`, `G2_HOT_ADD_NOT_PROVEN`, `G4_NOT_RUN`. Do not deploy this candidate or claim release readiness without the listed evidence. Licensed/source-only code, no movie dialogue.