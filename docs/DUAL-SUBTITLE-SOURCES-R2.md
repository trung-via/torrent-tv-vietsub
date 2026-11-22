# Dual subtitle sources: AI default, downloaded Vietnamese optional

**Decision:** Human, 2026-11-22. **Status:** product contract; P2 discovery
and stricter VI matching implemented as source-only candidate. The complete
Owner/P4/OMP two-track delivery is **not yet implemented or installed**.

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
- The native OMP subtitle selector should show each track's origin distinctly
  (AI translated versus downloaded VI), selection state, and availability;
  **no second translator or independent TV listener**.

## Exact acceptance boundary

Offline: matching false positives, two GET searches with VI present, EN
default, explicit VI choice, two independent cache receipts, no duplicated
provider POST/model calls, OFF/OTHER, A→B→A, disconnect/recovery and G2
first-frame ack per source. Then pinned Android build and Redmi visual test:
the same film displays both choices, defaults to AI, manual VI selection
persists without being overwritten by subsequent AI revisions, and reopening
the film reuses both cached SRTs. Until that proof, mark **SOURCE_ONLY**.
