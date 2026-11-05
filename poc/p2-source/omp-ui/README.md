# P2-SOURCE.3 — Actual OMP search screen overlay (opt-in, source-only)

This is **not** another standalone Python-only PoC. `apply.mjs` patches the real OMP TV search consumer `src/screens/Add.tsx` (the search-result UI), copying `tvCandidateCheck.ts` and `tvCandidateCheck.test.ts` into OMP's `src/sources/`. The patch is bounded to upstream OMP commit `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` and requires original `Add.tsx` Git blob `be8ab4529e0fdb9fe6dde3cc68c7fe58284aa323`.

## User-visible behavior in an overlay-built OMP app

A **new optional search control**, default OFF: `P2: ưu tiên metadata (tắt)`. When enabled it uses the North Star sample constraint **8–12 decimal GB and >=300 *reported* seeds** (non-customizable in this bounded slice), marks each result `khớp / ngoài giới hạn / chưa đủ dữ liệu`, and prioritizes matches once streaming completes. It never hides unknown rows, alters existing source search, automatically resolves a link/adds a torrent, fetches peers, reads media tracks or overrides D-pad selection. Search focus order remains stable as rows stream.

- Only a primary `ts-torznab` result with a tracker display field qualifies for the *reported* verdict. Merged `sources` cannot promote another source. This UI **does not authorize a tracker**, authenticate a source or prove licensing; these remain a separate upstream/source-adapter gate. A display `Tracker` field is untrusted.
- `sizeBytes` and `Seed` are from the source's reported metadata. An invalid/missing value is `UNKNOWN`; a known mismatch is reported as mismatch. A result title saying 1440p, 4K or Vietnamese audio does **not** prove actual dimensions, codec or audio.
- The UI badge deliberately says `báo cáo`; a prominent notice states no confirmation of 2K, Vietnamese audio or content rights. Addition remains a separate existing explicit user action.
- No external Python process runs on the TV. This is a TypeScript evaluator in OMP itself, independent of the previously merged offline Python verifier.

## Test in a disposable pinned upstream checkout

```bash
git clone --no-checkout https://github.com/spacesarmat/omp.git /tmp/omp
git -C /tmp/omp checkout --detach 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f
node poc/p2-source/omp-ui/apply.mjs /tmp/omp
cd /tmp/omp
npm ci --no-audit --no-fund
npx vitest run src/sources/tvCandidateCheck.test.ts
npm run build:mobile
```

The CI job runs only on GitHub-hosted Ubuntu, not the personal Windows runner. It is **source/TypeScript compilation proof**, not an APK/Redmi test. Actual G1+P2 overlay composition in a fresh Windows build requires a distinct guarded, authorized workflow after this source PR is accepted; do not silently modify the already accepted G1 APK or claim the current installed TV app includes the feature.

## Rollback

Delete the overlay from future build selection; the pinned OMP clone remains disposable. Existing G1 source patches, subtitle preferences, runner, TV, TorrServer, firmware and user data are untouched by this PR.
