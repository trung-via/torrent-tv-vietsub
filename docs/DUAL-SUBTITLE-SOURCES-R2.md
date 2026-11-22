# Dual subtitle sources: AI default, downloaded Vietnamese optional

**Decision:** Human, 2026-11-22. **Status:** source implementation on Draft
PR #179. P2 dual discovery/cache, independent P4 V2 activation and the OMP
source-choice menu exist in source and have offline tests. **No Android build,
Owner deployment, TV installation or real-device acceptance is claimed.**

## User-visible behavior

One explicit **Bật Vietsub AI** starts the existing Owner job for the exact
selected TorrServer file. It may produce two distinct choices:

1. **Vietsub AI (mặc định)** — a confidently matched English sidecar/provider
   SRT, translated by the existing checkpointed LEAN120 worker and delivered
   by the existing signed P4/G2 channel. This is the preferred track whenever
   an eligible English source exists; progress may be incomplete at first.
2. **Vietsub có sẵn (có thể lệch)** — an *independent* downloaded Vietnamese
   SRT offered only when the release identity is plausible. It is never
   passed through LEAN120. A title/year/BDRip/1080p match without verified
   moviehash or identical scene group is a **candidate**, not a proven sync
   match. The user can select it explicitly; it must not replace AI by itself.

If no usable English source exists or the translator fails, surface its
status and allow the Vietnamese option where present; never report it as an
AI translation. If neither source exists, show unavailable without creating
fabricated subtitle tracks. Existing ON/OFF/OTHER and exact movie/session
checks apply to both.

## Ownership and persistence

- P2 searches VI (at most one bounded metadata GET) and EN independently;
  finding VI never short-circuits the EN search. A search is not a download.
- Download each distinct selected file once under independent, recoverable
  per-media/per-source claims. If the POST outcome is uncertain, do not retry
  blindly. This can use **two** OpenSubtitles download quota units.
- Keep two immutable source receipts and namespaced output files per media:
  `ai/en-source` and `downloaded-vi`. Never overwrite the currently installed
  legacy `.auto-source-<fingerprint>.json`; migration must verify old content
  before recording the new lanes. Existing AI LEAN120 checkpoints remain
  keyed to the actual EN bytes/profile and are never invalidated by a VI option.
- P4 must carry a trustworthy source variant identifier alongside the current
  media/session and source digest; two independently versioned signed feeds or
  a verified option manifest must preserve replay protection. The TV may
  receive both but must auto-apply **only AI** when it becomes available.
  Manual switch to VI freezes auto-AI replacement until the user chooses AI
  again. Never let a late response from film A change film B or A→B→A.
- The OMP player action menu currently exposes distinct **Vietsub AI
  (mặc định)** and **Vietsub có sẵn (có thể lệch)** commands, each using
  authenticated P4 activation. The VLC native subtitle-track picker is not
  yet populated with both remote options; this is a subsequent UI polish
  gate, not something to claim as implemented. **No second translator or
  independent TV listener**.

## Implemented source boundaries

- `DualSubtitleCatalog` owns a distinct hash-checked immutable index for
  `ai_en` and `downloaded_vi` under the exact server/torrent/file-index
  fingerprint, with verified non-destructive migration from the legacy index.
- Dual-mode Owner uses one bounded VI GET and one/two EN GETs, at most one
  optional VI POST and one EN POST, then routes EN to existing LEAN120.
  A failing optional VI download does not block AI; a transient EN metadata
  network failure still leaves an eligible manual VI option.
- Normal V1 P4 activation remains AI-first, resolving existing EN
  checkpoints before the legacy ready source; in new dual mode a VI-only
  ready receipt **cannot** impersonate V1 AI. The explicit downloaded-VI
  command alone uses `TTV-P4-ACTIVATE-V2`, with a variant-bound device HMAC,
  exact current-film check and separate signed source SHA/session. The OMP
  swaps sessions only *after* a new authenticated activation response.
- A cached AI source is reused without rerunning a completed translation.
  A reopened legacy EN-only film may still search for a VI option once
  more; subsequent reopen with both caches does not call the provider.
- Offline tests verify protocol tampering/replay, separate receipts,
  migration, two-provider POST behavior, AI default, optional failure and
  A-to-B identity rejection. These tests do **not** replace device evidence.

## Exact acceptance boundary

Offline: matching false positives, two GET searches with VI present, EN
default, explicit VI choice, two independent cache receipts, no duplicated
provider POST/model calls, OFF/OTHER, A→B→A, disconnect/recovery and G2
first-frame ack per source. Then pinned Android build and Redmi visual test:
the same film displays both choices, defaults to AI, manual VI selection
persists without being overwritten by subsequent AI revisions, and reopening
the film reuses both cached SRTs. Until that proof, mark **SOURCE_ONLY**.
