# P2-SOURCE.3 — Actual OMP search screen overlay (opt-in, source-only)

This is **not** another standalone Python-only PoC. `apply.mjs` patches the real OMP TV search consumer `src/screens/Add.tsx` (the search-result UI), copying `tvCandidateCheck.ts` into OMP's `src/sources/` and the test into `tests/sources/`. The patch is bounded to upstream OMP commit `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` and requires original `Add.tsx` Git blob `be8ab4529e0fdb9fe6dde3cc68c7fe58284aa323`.

## Historical P2-SOURCE.3/4 behavior (superseded by P2-SOURCE.5 below)

A **new optional search control**, default OFF: `P2: ưu tiên metadata (tắt)`. When enabled it uses the North Star sample constraint **8–12 decimal GB and >=300 *reported* seeds** (non-customizable in this bounded slice), marks each result `khớp / ngoài giới hạn / chưa đủ dữ liệu`, and prioritizes matches once streaming completes. It never hides unknown rows, alters existing source search, automatically resolves a link/adds a torrent, fetches peers, reads media tracks or overrides D-pad selection. Search focus order remains stable as rows stream.

- P2-SOURCE.3 initially evaluated only primary `ts-torznab` rows with a tracker display field; **P2-SOURCE.4 below additionally evaluates primary pinned TorrServer `ts-rutor`** for reported numeric metadata. Merged `sources` cannot promote another source. This UI **does not authorize a tracker**, authenticate a source or prove licensing; these remain a separate upstream/source-adapter gate. A display `Tracker` field is untrusted.
- `sizeBytes` and `Seed` are from the source's reported metadata. An invalid/missing value is `UNKNOWN`; a known mismatch is reported as mismatch. A result title saying 1440p, 4K or Vietnamese audio does **not** prove actual dimensions, codec or audio.
- The UI badge deliberately says `báo cáo`; a prominent notice states no confirmation of 2K, Vietnamese audio or content rights. Addition remains a separate existing explicit user action.
- No external Python process runs on the TV. This is a TypeScript evaluator in OMP itself, independent of the previously merged offline Python verifier.

## P2-SOURCE.4 — reasoned UNKNOWN and pinned TorrServer Rutor metadata (2026-11-07)

Human-observed on Redmi after the G1+P2 debug APK install: P2 toggle and badge rendering worked, but TorrServer Rutor results showing reported size and seeds were all UNKNOWN and did not change priority. This is expected under the earlier Torznab-only allowlist, not evidence of a broken APK.

This bounded revision follows the exact pinned OMP `registry.ts` contract: `fromSearchResult(..., 'ts-rutor')` and `fromSearchResult(..., 'ts-torznab')` produce first-party TorrServer source ids. Only those two primary ids may be evaluated for **reported** size/seed metadata. Torznab still requires a nonblank tracker display field; Rutor does not. Other built-ins, phone results and merged secondary `sources` remain UNKNOWN even with plausible visible numbers. This is not a generic trust grant for source names.

Every UNKNOWN result now has a safe, static diagnostic in the visible UI: unsupported primary source, missing Torznab tracker, missing/invalid size, missing/invalid reported seeds, or invalid criteria. No raw tracker name/URL, magnet, credentials, rights or source secrets are logged/shown. A known numeric mismatch outranks missing unrelated metadata, but only within the two pinned adapters. Reported counts are neither live connected peers nor lawful-media authorization, and title text never proves resolution/audio.

Sort remains `reported-match` → `unknown` → `reported-mismatch` **after** source streaming ends; all rows remain visible and stable while streaming. The original default-OFF control, user confirmation for additions, search back/remote UX, G1 subtitles and runtime permissions are unchanged.

**Gate:** this PR proves only overlay source/tests and GitHub-hosted TypeScript/asset build if CI succeeds. The existing Redmi APK SHA `c2f71cb8c8accc11821396d20a96490b0a129344cb329e1c5e6d9c3bf2f7b75f` **does not contain this revision**. A new APK and read-only/installation/device validation require a later separately approved deployment; no current real-TV PASS is claimed for P2-SOURCE.4.

## P2-SOURCE.5 — Human-requested 6–15 GB + 4K title hint + highest reported seeds (2026-11-07)

The Human's latest on-Redmi decision supersedes the previous 8–12 GB / >=300-seed sample. This remains **P2 opt-in UI ranking, NOT a hard-hide filter**. The new badge is `P2: 6–15 GB · tên 4K · seed cao nhất (bật)`; default remains OFF. The search/source/network/remote/Back and add-confirmation paths are unchanged. No automated torrent addition/download is permitted.

- **Size:** 6,000,000,000 to 15,000,000,000 reported bytes inclusive (decimal GB); outside range is `reported-mismatch`.
- **4K:** recognize only bounded `2160p`, `2160`, `4K`, `UHD` **tokens in the result title**. This is an untrusted release *claim*, not an inspected 3840x2160 stream or codec proof. Explicitly lower-resolution-only titles are `reported-mismatch`; unlabeled/ambiguous titles remain `unknown`. Titles with both 4K and lower resolution are ambiguous, not auto-matched. No 4K claim is silently inferred from `qualityRank`, poster or filename-like substrings (e.g. `4KID`).
- **Seed priority:** drop the former >=300 seed eligibility floor entirely. After search streaming ends, group matched (size+claimed 4K+valid seed) → unknown → mismatch, and sort **descending reported seeder count within each group**, preserving original order on ties. Zero seeds are a valid reported count and rank last among matched nonnegative counts. Missing/invalid seeds remain unknown. No live peer count, health or throughput is verified.
- **Scope/provenance:** assess only pinned first-party TorrServer `ts-rutor` and `ts-torznab` (the latter requiring nonempty tracker display metadata); other/merged sources remain unknown regardless of title/size/seed. These results do not establish that the source or media is authorized.
- **UI:** each row keeps its P2 verdict with safe diagnostics for unknown, and the notice emphasizes that 4K is a title claim; all rows remain visible. No data migration or modification of G1 subtitles, saved preferences, Windows/NAS TorrServer or Redmi hardware.

**Acceptance boundaries:** targeted Vitest must cover inclusive 6/15 GB, 4K token/false-positive behavior, no seed floor, descending seeds, tie stability, provenance/UNKNOWN handling, and no hidden/mutated rows. Hosted OMP TypeScript build and build-composition CI are source-only; do not claim that the **already-installed** G1+P2-SOURCE.4 APK SHA `cd55d195741697509b294d8cc4176473c01ccfdba654b1a40408a001e85c7320` includes P2-SOURCE.5. A fresh ARM32 APK and separate Human-approved ADB in-place install plus Redmi UI acceptance will be required to deploy this change.

## Test in a disposable pinned upstream checkout

```bash
git clone --no-checkout https://github.com/spacesarmat/omp.git /tmp/omp
git -C /tmp/omp checkout --detach 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f
node poc/p2-source/omp-ui/apply.mjs /tmp/omp
cd /tmp/omp
npm ci --no-audit --no-fund
npx vitest run tests/sources/tvCandidateCheck.test.ts
npm run build:mobile
```

The CI job runs only on GitHub-hosted Ubuntu, not the personal Windows runner. It is **source/TypeScript compilation proof**, not an APK/Redmi test. Actual G1+P2 overlay composition in a fresh Windows build requires a distinct guarded, authorized workflow after this source PR is accepted; do not silently modify the already accepted G1 APK or claim the current installed TV app includes the feature.

## Rollback

Delete the overlay from future build selection; the pinned OMP clone remains disposable. Existing G1 source patches, subtitle preferences, runner, TV, TorrServer, firmware and user data are untouched by this PR.
