# P2-SOURCE.2 — OMP TorrServer/Torznab result bridge

## Pinned source inspection
OMP upstream SHA: `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`.

- `src/api/types.ts`: `SearchResult` has `Size`, `Seed`, `Tracker`, `Hash`, `Link`, `Magnet`.
- `src/sources/registry.ts`: `fromSearchResult` normalizes to `SourceResult`, setting `source` and parsed `sizeBytes`. Sources include `ts-torznab` from `TorrServerClient.search('torznab')`.
- `src/sources/types.ts`: `SourceResult` supports `groupKey` and combined `sources` after merging. These are not authorization signals.
- `src/sources/search.ts`: `SearchAllOptions.onResult(sourceId, results)` is the intended future integration seam.

## Implemented now
`omp_torznab_bridge.py` translates a **caller-provided** snapshot of one `ts-torznab` source's `SourceResult` rows into existing `candidate_verifier.py` assessments. Pass an `ApprovedOrigin('ts-torznab', tracker_id, approved)` created from the trusted user/operator policy **outside the result**. The row's `source` and `Tracker` must both match that grant; a merged row's `sources` cannot expand a grant.

- `sizeBytes` is site-reported/parsed size, not ffprobe-verified.
- `Seed` is explicitly labeled `REPORTED` with caller-supplied timestamp, **not** `CONNECTED`. `CreateDate` is a release date, never the observation time.
- No frame dimensions, video codec or Vietnamese track are inferred from the result title; required resolution/audio criteria remain UNKNOWN until media verification.
- Output identifies results with SHA-256 opaque IDs; no magnet, tracker key, HTTP URL, torrent title or PII is echoed. No request to trackers, TorrServer, LAN or TV.
- Max 100 rows per snapshot; missing/malformed required metadata produces UNKNOWN or REJECT. No automatic torrent add.

## Contract test
```powershell
python -m unittest discover -s poc/p2-source -p 'test_*.py' -v
```

## Important boundary
This is a **working offline data adapter** against the real pinned OMP TypeScript `SourceResult` contract, **not a change compiled into OMP UI/APK**. The app does not yet transmit snapshots to Python, nor apply the results on TV. Integration requires a separate read-only OMP UI module or properly scoped local Gateway protocol with user opt-in, and actual authorized Torznab settings/ToS verification. Untrusted result field `Tracker` is not an authenticated tracker identity. It only matches an approved configuration provided by the caller; real transport provenance remains an independent gate.

No live search, external media or credentials used in this PR.
