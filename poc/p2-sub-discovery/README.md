# P2-SUB-DISCOVERY — D1 offline matcher

Tracking: [Issue #121](https://github.com/trung-via/torrent-tv-vietsub/issues/121).

**State:** Source-only candidate on a separate feature branch. This is not wired to TorrServer, OpenSubtitles or the TV. Neither live downloads nor native player updates are implemented here.

## Architecture boundary

- `Media` is supplied by a **future trusted TorrServer adapter**; media identity is `server_profile_id + torrent_hash + file_index`. Filename and release strings are untrusted *metadata hints*, never instructions.
- `SearchResults` must be bound to that exact media key or `choose` raises an error. External responses require source-side API/ToS/credential validation in D2, not in this pure matcher.
- `parse_release` extracts title/year/source/resolution/codec/release group as hints from a filename. Year/title conflicts are rejected. `1080p` is only a small ranking signal; the release group helps but is **not proof** of timecode compatibility.
- `movie_hash` is accepted only as a validated 16-character hex value. Hash calculation, remote Range reads and proof that the supplied hash is the OpenSubtitles hash of the selected file belong to a separately verified D2 adapter.
- Priority: sufficiently confident VI candidate → confidently matched EN candidate for a **separately authorized** translation handoff → human review on ambiguous candidates → no match. A candidate decision is **not** a downloaded subtitle and is **not** subtitle synchronization proof.
- Fail-closed on wrong media binding, contradictory title/year, invalid moviehash, duplicate subtitle IDs, unsupported formats, and ambiguous equivalent candidates. No model, network, Torznab or BitTorrent work here.

## Run offline unit tests

From repository root:

```bash
python -m unittest discover -s poc/p2-sub-discovery -p 'test_*.py' -v
```

12 synthetic tests were executed locally on the authored source candidate, all PASS (2026-11-12). GitHub CI/Windows runner on this branch: **NOT_RUN**; no real credentials, user media or API responses used.

## Next gates

- **D2:** OpenSubtitles API compliance, quota/rate limit, legal/authorized media, safe download/UTF-8 SRT/VTT parsing, local cache and VI→EN fallback. Never put keys or real film captions in public GitHub.
- **D3:** bridge output through existing P4 receiver, not a second TV transport. Needs pairing, session/revision HMAC, OFF/OTHER preference, G1/G2/G3/G4 and Redmi physical evidence.
- **No automatic side effects:** do not start a service, change host/network, install APK, call cloud models or merge/release from this D1 source-only PR.
