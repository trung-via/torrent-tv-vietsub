# P3/P4 cross-lane source integration — Draft (2026-11-14)

An exact-source candidate, **not** deployed/released or proof of real subtitles on TV. Repository PUBLIC; no private media, credentials or actual LAN addresses included.

## Immutable source parents

- Native Redmi signed P3/P4 and explicit-on-TV request: PR #159, `a5db6079d74d3d5060e31817379c69be70e956b8`.
- Windows owner and signed P4 verified-ready, existing OpenSubtitles D1/D2/VI_FIRST and LEAN120: PR #160, `66a2baba370b129ec90cdb56d26bb8462eaefe88`.
- Merged baseline main at composition: `ad853ebd5acdbb1e16656bde8da3c68950d0de2c`.
- Two-parent integration commit preserves provenance. Compared with main, owner code has 133 unique changed paths and native TV has 55 unique changed paths; exact SHA-source path collision count is zero. No second translator/receiver.

## Source-chain contract

1. OMP Play/Next identifies the selected legal media/session only. Only direct film-specific **Bật Vietsub AI** sends signed VIEWER_VIETSUB_REQUESTED and current REQUESTED status.
2. P3 TV sender uses the existing private P4 certificate-pinned HTTPS connection: `/p3/selection` and `/p3/state`, with separate HMAC domains, nonce, boot+sequence, TTL. OFF/OTHER, cancel, Next and wrong item must refuse/cancel.
3. Owner independently checks current signed TV state against trusted localhost TorrServer selected file. Source preference: local viable VI/EN, then D1/D2 VI-first OpenSubtitles, confident EN through existing LEAN120 API worker (Human-directed candidate Gemini 4 Hydrogen High full-film profile, optional first-window pilot).
4. Validated VI/result is registered into the original paired P4 feed and the existing OMP G1/G2 native player. No other TV receiver or provider is introduced.

## Evidence and hold boundaries

- Hosted Ubuntu-only source/mock CI in `.github/workflows/tv-p3-p4-cross-lane-offline-ci.yml` runs the TV source guard, signed P3 state/consent synthetic test and existing OpenSubtitles/P2/P3/P4 mock suites on a single HEAD.
- Pre-existing workflows may skip because they gate on historical PR number/branch; skipping is never PASS. Hosted CI is not equivalent to composed Android Gradle APK, authenticated real LAN, real OpenSubtitles/Gemini, Redmi no-picker 120→240 cue 131, or G4 Release.
- Keep **Draft/HOLD** until independent Brain review on exact HEAD/base, CI, provenance/security checks, Android composed proof and required device acceptance according to Issue #42.
- No ADB, Windows service/firewall, pairing, API upload/charge, media download, signed APK or release is permitted solely by this source-only PR.
