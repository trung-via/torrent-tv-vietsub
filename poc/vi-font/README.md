# P1 — Accepted Vietnamese subtitle Font v3 (LibVLC 3.7.7 / Redmi A Pro 55)

**Tracking:** [Issue #96](https://github.com/trung-via/torrent-tv-vietsub/issues/96) · **Scope:** source-only overlay for the separately built OMP Debug client · **Status:** `V3_DEBUG_REAL_TV_VISUAL_ACCEPTED / G1_G3_HUMAN_REGRESSION_SMOKE_PASS / G4_RELEASE_NOT_RUN`.

This is the **clean Font v3 source snapshot** proposed against `main`. It supersedes the intermediate Font v2 proposal in [Draft PR #97](https://github.com/trung-via/torrent-tv-vietsub/pull/97) and carries the **identical tested code/test blobs** from [Draft PR #98](https://github.com/trung-via/torrent-tv-vietsub/pull/98), without stacked PR history. It does **not** itself install an APK, modify the installed player, change release signing, or turn the PoC into an automatically deployed production feature.

## Pinned source and sole retained configuration

- OMP upstream: `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, exact original `VlcRuntime.kt` blob `15bf0cb1d53ddf6c8936f362499a7575f2586f08`.
- LibVLC: `org.videolan.android:libvlc-all:3.7.7`. Run G1 Production and P2 overlays first, then apply `poc/vi-font/apply.mjs` only in a pinned disposable `p1-g1-prod-*` OMP checkout. The script stops on root/source drift, duplicate anchor, or existing font customization.
- Retained renderer options: `--freetype-font=Noto Sans`, `--freetype-rel-fontsize=13`, **`--freetype-bold` ON**, `--freetype-outline-thickness=1`, `--freetype-outline-color=0`. Preserve `--verbose=-1`.
- No changes to Thor v0.3.5 SRT bytes, cue timestamps, selected-track persistence, G3 seek/resume logic, font files, ROM settings, TorrServer, AIOS, or signed Release.

Historical A/B context only: v1 used Bold ON / outline 2 (too heavy in video); v2 used Bold OFF / outline 1 (lower contrast); **v3 uses Bold ON / outline 1**. V3 is the single retained candidate; neither v1 nor v2 is included as a source patch in this branch.

## Independent evidence, by boundary

| Gate | Evidence and scoped outcome |
| --- | --- |
| Source and build | [Windows HostOps #42665236868](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42665236868): Node tests, G1+P2 composition guards, pinned LibVLC 3.7.7 checks, Gradle Debug and unit tests PASS for the v3 candidate |
| APK/signature | [Read-only HostOps #42666314021](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42666314021): v3 SHA, test package and signer compatibility PASS |
| Actual Redmi install | [HostOps #42667738610](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42667738610): installed Debug v3, APK SHA-256 `845e25444e1ed9fc3092a1274c6f93e2dce19854b588eae9b9085139c85b74ac`; v2 rollback APK retained privately |
| Visual typography | Human accepted v3; Brain reviewed uploaded `16093.mp4` as a limited visual smoke PASS (legible UTF-8 Vietnamese, no evident missing marks/clipping in the sample). [Brain record](https://github.com/trung-via/torrent-tv-vietsub/issues/96#issuecomment-6747726402) |
| G1/G3 post-install | Human tested reopening app: selected subtitle automatically reappears and aligns; seeking: subtitle remains aligned. [Recorded Human acceptance](https://github.com/trung-via/torrent-tv-vietsub/issues/96#issuecomment-6747801292). `HUMAN_REPORTED_PASS` for those actions; not an automated full-matrix result |
| G4 signed Release | **NOT_RUN / NOT_ACCEPTED**. [Release issue #95](https://github.com/trung-via/torrent-tv-vietsub/issues/95) owns release binary, signing, isolation and TV verification |

The user-uploaded videos are **not published** in this public repository. Independent GitHub/HostOps job evidence and Human real-TV observations are kept separate; the video itself does not cryptographically attest the APK SHA.

## Reproduction and remaining gates

`node --test poc/vi-font/apply.test.mjs` checks patch behavior. `node poc/vi-font/apply.mjs <pinned-disposable-omp-root>` applies the source-only overlay **after G1+P2**; `node poc/vi-font/verify.mjs <pinned-disposable-omp-root>` checks the composed source. Use the project's approved dedicated Windows runner and pinned source; this document does not authorize a new host/ADB operation.

**Not claimed by this acceptance:** full OFF/ON/OTHER preference matrix, A→B→A media isolation, malformed/missing SRT, separate VTT, measured cue drift, arbitrary content/codecs, true FreeType font family selection on the ROM, or a signed Release. Preserve the tested private v2 rollback until a separately approved G4 path.

**Merge boundary:** this branch supplies only `poc/vi-font/{apply.mjs,apply.test.mjs,verify.mjs,README.md}`, with v3 source/test blobs unchanged from PR #98. Review the exact diff, then obtain the separate Human merge decision; no auto-merge or production promotion follows from the Debug visual PASS.
