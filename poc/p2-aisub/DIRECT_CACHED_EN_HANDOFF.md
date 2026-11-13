# P2 Direct EN Cache → Existing LEAN120 (No D3 Translation Detour)

Tracking: [Issue #132](https://github.com/trung-via/torrent-tv-vietsub/issues/132). Small source-only
candidate stacked on **P2 API Draft #118**. Independent discovery branch
**D2.5 Draft #130** has already performed one real EN acquisition and cache;
this P2 candidate does **not** redo that work.

## Architecture: one original EN, one existing worker

```text
Selected authorized film
      |
      v
Embedded/cached confident VI? --YES--> Verified VI file
      | NO                               |
      v                                  |
D2.5 VI_FAST (one metadata GET max)       |
      | no confident VI                  |
      v                                  |
EN search + release ranking                |
      | confident EN + owner approval    |
      v                                  |
D2 ONE permitted provider POST             |
      |                                    |
      v                                    |
Original EN .srt in owner-private cache    |
      | SHA/cue verification              |
      v                                    |
P2 direct cached_en_direct_handoff.py      |
      | no D3 manifest, no copy           |
      v                                    |
EXISTING AutomaticLean120Worker #118      |
      | 120 cue / 6500 chars / ±4         |
      | one approved cloud translation    |
      | durable per-batch checkpoints     |
      v                                    |
Private VI SRT <--------------------------+
      |
      | *only when real OMP+TorrServer binding and authenticated P4 are ready*
      v
D3 verified media/session binding → Existing P4 receiver #120 → OMP/G2
```

## Code ownership and data contract

**D2/D2.5 (source):** search/select/one approved download, validate timed SRT,
write the EN once to a private cache, return source receipt:
`{cache_file, source_sha256, cue_count, language:"en"}`. A source has already
been successfully downloaded: never issue another OpenSubtitles POST solely to
start translation.

**P2 (translation):** `cached_en_direct_handoff.py` reopens that exact
private file, checks it is inside the chosen private cache root (not symlink),
verifies size/SHA and original cue count, and constructs
`AssumedEnglishSubtitle.from_supplied` for **LOCAL_TRANSLATION_ONLY**. Its
deterministic internal `media.<hash>` is a **P2 job namespace**, *not* a
real, authenticated P4 media key. The bridge calls the existing
`AutomaticLean120Worker.run(handoff, on_revision=None)` only after one
explicit cloud-upload authorization. No GitHub payload, manifest, intermediary
JSON, queue service, another model client, polling, file copy, repeat POST or
TV pairing is involved. The existing worker writes LEAN120 checkpoints and
`vi-final.srt` under its configured owner-private state root. Any real model
call requires a separately configured local Gemini credential/profile; offline
tests use a fake transport.

**D3/P4 (delivery, SEPARATE):** a local-only translation receipt MUST NOT
populate D3's owner-confirmed-match booleans, claim video sync or be sent to
TV. Before delivery, bind the validated VI artifact to a real selected
TorrServer file/index and authenticated OMP/P4 session; reuse the existing
P4 receiver and G1/G2 reload. No fake `media.<hash>` may be converted to a
trusted TV identity merely because its syntax matches.

## User interaction design

One user intent ("Find Vietsub") → one result. The system may perform a
bounded VI lookup and EN fallback, but should not ask the user to select a file
or approve every LEAN120 batch. Configuration of rights/cloud-subtitle upload
and allowed provider is an **upfront explicit owner setting/session grant**,
not implicit from downloading EN. For the already downloaded owner pilot, no
download again is needed; a separate actual Gemini upload grant is not yet
recorded.

If exact release/codec/source evidence is only suggestive, mark
`SYNC_NOT_VERIFIED` and keep delivery gated; translation-only QA can proceed
without pretending the OMP film binding is known. On any invalid cache,
stale bytes, wrong language or quota-related error, fail closed. Worker
`.inflight` prevents ambiguous Gemini retries; owner reconciliation is
required if provider outcome was uncertain.

## Current implementation/evidence boundary

- **Implemented in this Draft:** direct, pure owner cache → P2 source
  import + call into the **existing** worker; no new LEAN120 implementation.
- **Mock verified:** source SHA/cue/path/format/consent/CI guards, and real
  worker invocation against a fake Gemini transport, checkpoint replay.
- **Not implemented here:** automatic callback wired into the existing D2
  owner download CLI (D2 and P2 remain different Draft branches); owner
  one-button UI; real Gemini call; trusted TorrServer+OMP binding; Redmi P4
  no-picker end-to-end; any merge or release.

The next independent implementation task after this bridge is **one
composed, source-pinned integration test**: the D2 in-memory successful
download receipt invokes this P2 bridge, using fake provider transport,
without a second file copy/search, and preserving D3 for delivery. No new
daemon or standalone translator is needed.
