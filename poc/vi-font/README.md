# P1 — Vietnamese subtitle typography trial (VLC 3.7.7 / Redmi A Pro 55)

**Issue:** [#96](https://github.com/trung-via/torrent-tv-vietsub/issues/96). **Status:** `SOURCE_CANDIDATE / REAL_TV_GLYPH_NOT_VERIFIED`.

## Problem from real TV

On the already working Thor v0.3.5 G1+P2 Debug playback, Human reports captions slightly too small and abnormal Vietnamese tone glyph shapes, especially `ả`, `ậ` in `chảy` and `cậu`, along with `ở cả bận hỏng được mất mời dọa phải tất lưu bộ`. The SRT is UTF-8/NFC with exact remote SHA; G1 render, G3 multi-seek sync and auto-reopen resume remain HUMAN_PASS.

Actual Redmi read-only font inventory: [HostOps #42646613900](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/42646613900), 262 system font files (Roboto: 20; NotoSans: 179). `fonts.xml` lacks an explicit `vi` mapping under the particular matching rule probed; this does **not** prove which font VLC actually selected.

## Smallest reversible Debug candidate

Pinned upstream OMP `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, LibVLC `org.videolan.android:libvlc-all:3.7.7`, native `VlcRuntime.kt` (original Git blob `15bf0cb1d53ddf6c8936f362499a7575f2586f08`). On a disposable OMP clone **after** G1 Production + P2 source overlays, `poc/vi-font/apply.mjs` makes a single pinned, fail-closed change to `VlcLibrary.OPTIONS`:

- `--freetype-font=Noto Sans` — trial font family; exact Android font resolution and glyph shape must be confirmed on-device, not assumed.
- `--freetype-rel-fontsize=13` — VLC 3 default 16, smaller denominator yields a larger caption (nominal ~23% scale vs 16; device-dependent).
- `--freetype-bold` — legibility; evaluate stroke thickness and Vietnamese marks visually.
- `--freetype-outline-thickness=2`, `--freetype-outline-color=0` — thin black contrast edge.

VideoLAN Android `VLCOptions.kt` explicitly uses `--freetype-rel-fontsize`, `--freetype-bold` and `--freetype-outline-thickness` for VLC 3; VLC 4 uses a different scaling flag. Font-family selection is a **test candidate** requiring actual visual acceptance; no bundled font or ROM modification. Source: https://github.com/videolan/vlc-android/blob/master/application/resources/src/main/java/org/videolan/resources/VLCOptions.kt

## Guards and tests

- `poc/vi-font/apply.test.mjs` — anchor uniqueness, idempotency failure, exact flags, original Vietnamese precomposed Unicode specimen.
- `poc/vi-font/verify.mjs` — assembled source flag counts, pinned OMP/LibVLC and G1 helper presence.
- Run on dedicated Windows `torrent-tv-vietsub-win`, isolated OMP clone; don't change global TV settings/ROM fonts, Thor SRT, Gradle release signing guard, TorrServer or AIOS.
- User-approved source test/build Debug trial; do **not** install/replace the already working Debug on Redmi, publish APK, sign Release, or modify app data without a separately authorized action.

## Human A/B acceptance

After a reviewed/compiled candidate and separately authorized installation: compare same on-TV sentence with previous Debug, check `ở chảy cậu cả bận hỏng được mất mời dọa phải tất lưu bộ` plus `ả ậ ỏ ọ ộ ỡ`; readable from normal seating, both one/two lines, complete ascenders/marks, no new aliasing; then verify SRT selection, OFF/ON, G3 seek and G1 resume unchanged. If family selection is unsupported, investigate libass/fontconfig fallback rather than replacing SRT characters. Only then integrate reviewed font solution into G4 Release issue #95.

**Acceptance boundaries:** `NODE_UNIT_PASS` ≠ `WINDOWS_DEBUG_APK_BUILD_PASS` ≠ `REAL_TV_FONT_VISUAL_PASS` ≠ `G4_RELEASE_PASS`.
