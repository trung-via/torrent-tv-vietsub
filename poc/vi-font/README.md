# P1 — Vietnamese subtitle typography trial (VLC 3.7.7 / Redmi A Pro 55)

**Issue:** [#96](https://github.com/trung-via/torrent-tv-vietsub/issues/96). **Status:** `V3_A_B_SOURCE_CANDIDATE / WINDOWS_BUILD_PENDING / REAL_TV_GLYPH_NOT_VERIFIED`. This branch is stacked on the existing v2 Draft PR #97; v2 remains installed on Redmi.

## Problem from real TV

On the already working Thor v0.3.5 G1+P2 Debug playback, Human reports captions slightly too small and abnormal Vietnamese tone glyph shapes, especially `ả`, `ậ` in `chảy` and `cậu`, along with `ở cả bận hỏng được mất mời dọa phải tất lưu bộ`. The SRT is UTF-8/NFC with exact remote SHA; G1 render, G3 multi-seek sync and auto-reopen resume remain HUMAN_PASS.

Actual Redmi read-only font inventory: [HostOps #42646613900](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42646613900), 262 system font files (Roboto: 20; NotoSans: 179). `fonts.xml` lacks an explicit `vi` mapping under the particular matching rule probed; this does **not** prove which font VLC actually selected.

## Smallest reversible Debug candidate

Pinned upstream OMP `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, LibVLC `org.videolan.android:libvlc-all:3.7.7`, native `VlcRuntime.kt` (original Git blob `15bf0cb1d53ddf6c8936f362499a7575f2586f08`). On a disposable OMP clone **after** G1 Production + P2 source overlays, `poc/vi-font/apply.mjs` makes a single pinned, fail-closed change to `VlcLibrary.OPTIONS`:

- `--freetype-font=Noto Sans` — trial font family; exact Android font resolution and glyph shape must be confirmed on-device, not assumed.
- `--freetype-rel-fontsize=13` — **unchanged from v1** per Brain's video review; VLC 3 default 16, smaller denominator yields a larger caption (device-dependent).
- **`--freetype-bold` enabled:** v3 changes exactly one style parameter from v2 (normal weight → bold), holding font family, size and outline constant. This tests whether readability/contrast can be recovered without the heavy v1 outline; it does **not** prove better glyph positioning.
- `--freetype-outline-thickness=1`, `--freetype-outline-color=0` — **unchanged from v2**, slimmer than v1 (`2`), preserving the controlled single-variable bold A/B.

**Brain A/B video reviews:** in v1's 31-second video the strokes/outline looked heavy; v2's 46.6-second video showed thinner letters and lower contrast, while the shapes of dấu hỏi in `bảo`/`cả` remained imperfect. This controlled v3 candidate restores bold alone while retaining v2 outline `1`. Camera evidence cannot prove actual font fallback, diacritic root cause or sync. **No SRT, timing, player selection, or resume source changes.**

VideoLAN Android `VLCOptions.kt` explicitly uses `--freetype-rel-fontsize`, `--freetype-bold` and `--freetype-outline-thickness` for VLC 3; VLC 4 uses a different scaling flag. Font-family selection is a **test candidate** requiring actual visual acceptance; no bundled font or ROM modification. Source: https://github.com/videolan/vlc-android/blob/master/application/resources/src/main/java/org/videolan/resources/VLCOptions.kt

## Guards and tests

- `poc/vi-font/apply.test.mjs` — anchor uniqueness, idempotency failure, exact **five** freetype flags; confirms bold enabled, size 13 and outline 1 unchanged, with NFC Vietnamese specimen.
- `poc/vi-font/verify.mjs` — assembled source flag counts, pinned OMP/LibVLC and G1 helper presence.
- Run on dedicated Windows `torrent-tv-vietsub-win`, isolated OMP clone; don't change global TV settings/ROM fonts, Thor SRT, Gradle release signing guard, TorrServer or AIOS.
- User-approved source test/build Debug trial; do **not** install/replace the already working Debug on Redmi, publish APK, sign Release, or modify app data without a separately authorized action.

## Human A/B acceptance

After a reviewed/compiled candidate and separately authorized installation: compare same on-TV sentence with previous Debug, check `ở chảy cậu cả bận hỏng được mất mời dọa phải tất lưu bộ` plus `ả ậ ỏ ọ ộ ỡ`; readable from normal seating, both one/two lines, complete ascenders/marks, no new aliasing; then verify SRT selection, OFF/ON, G3 seek and G1 resume unchanged. If family selection is unsupported, investigate libass/fontconfig fallback rather than replacing SRT characters. Only then integrate reviewed font solution into G4 Release issue #95.

**Acceptance boundaries:** `NODE_UNIT_PASS` ≠ `WINDOWS_DEBUG_APK_BUILD_PASS` ≠ `REAL_TV_FONT_VISUAL_PASS` ≠ `G4_RELEASE_PASS`.

## Three-way experimental matrix and acceptance boundary

| Candidate | Font | Relative size | Bold | Outline | Actual Redmi evidence |
| --- | --- | --- | --- | --- | --- |
| v1 | Noto Sans | 13 | ON | 2 | Installed/tested; glyph weight heavy per videos |
| v2 | Noto Sans | 13 | OFF | 1 | Installed; video thin/less contrast; sign-off HOLD |
| v3 (this branch) | Noto Sans | 13 | ON | 1 | **NOT INSTALLED; visual NOT_RUN** |

V2→v3 changes only bold; v1→v3 changes only outline. Until a separately authorized device install, v2 stays on the TV. If v3 still has awkward `ả`/`ậ`/`ở`, investigate which font VLC/FreeType actually resolves on this Android ROM and whether fallback or glyph shaping is responsible, rather than claiming a stroke tweak fixed the underlying issue. No Release G4 approval flows from this trial.
