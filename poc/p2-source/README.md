# P2-SOURCE — Candidate metadata verifier (offline first slice)

**Scope:** authorized input metadata → deterministic eligibility/UNKNOWN/REJECT. No search, indexer login, crawl, magnet fetch, peer connection, torrent add, TorrServer call, host service, cloud API or TV action.

This code is a **bounded core module**, not yet wired into OMP website adapters or a local Gateway. It preserves the existing OMP-first decision; another feature must implement an authorized adapter and user-confirmation UX. Never assume a title or seed number proves a legal or playable video.

## Use

Run tests from the repository root:

```powershell
python -m unittest discover -s poc/p2-source -p 'test_*.py' -v
```

Programmatic consumers import `candidate_verifier` from the module directory and construct a `Candidate` from an **authorized trusted adapter** (not raw page text), plus `Criteria`. `assess()` is pure and returns an opaque-ID-only `Assessment`, with `ELIGIBLE_METADATA`, `REJECT` or `UNKNOWN`.

- The user's “2K” is ambiguous: require explicit `Resolution.P1440` (at least 2560×1440) or `Resolution.DCI2K` (at least 2048×1080). No implicit resolution downgrade.
- Sizes use **decimal GB** (1 GB = 1,000,000,000 bytes). A request for 8–12 GB becomes `min_bytes=8_000_000_000` and `max_bytes=12_000_000_000`.
- Reported, scraped and connected seed counts are different `SeedKind` measurements; require one exact matching observation with named source and timestamp. Missing/duplicate samples yield UNKNOWN. `observed_at` is metadata only: staleness detection must be added with an actual time/adapter policy before claiming live peers.
- Resolution/audio metadata may be wrong; no ffprobe, video playback or track truth is proven by normalized candidate fields. Empty/unknown fields return UNKNOWN when required.
- `source_authorized` is a trusted adapter-policy input, **not** a rights proof from a title or untrusted web page. Inaccessible or disallowed source is rejected; Human rights/ToS review remains external.
- Eligible metadata still requires explicit Human confirmation before torrent addition or TV playback.

## Acceptance for this slice

Unit tests pass for 2K policy distinction, hard size bounds, provenance-labeled seed counts and no substitution between families, unknown metadata, Vietnamese audio claim, unauthorized-source fail-closed and malformed input. No E2E source discovery is claimed.

**Next integration:** select one authorized OMP source adapter; pin its input/output contract and legal fixture; map actual metadata/provenance into Candidate; measure first real candidate + negative source failures; then separately add user-confirmation and TorrServer transfer in later scoped work. No automatic downloader or unauthorized live crawling.
