# Owner background per-film Vietsub (source-only R1)

## Decision (Human 2026-11-21)

An authenticated, explicitly requested Vietsub AI translation belongs to the
**film**, not to its current TV playback session. Closing A or starting B must
not stop or lose A. At most three distinct authorized film jobs can run in
parallel in the single interactive Owner process. P4 delivery, unlike P2
translation, remains strictly tied to the **currently verified TV session**.

## Audited previous behavior

- `owner_session_bridge` blocked its only queue consumer until one full film
  finished; B could wait minutes for A.
- `AutomaticLean120Worker.run` held *all other films* behind an `inflight`
  marker from A, although its checkpoints/locks were already per-job.
- P2 did persist `vi-final.srt`, but reopening a cached English source still
  performed model preflight even when the final SRT was valid.
- V3 events needed A to be on the TV **at execution time**, and the late P4
  callback could mark a successfully translated A as blocked after B began.
- A new TV session for the same media key could collide with stale P4
  in-memory rolling receipts instead of rehydrating durable checkpoints.

## New source flow

1. A verified signed viewer request is admitted by P3, then the Owner-private
   V4 queue item freezes the authorized `server_id`, `torrent_hash`,
   `file_index`, media filename and original TV session. The independent
   TorrServer/owner-pinned-file resolver still verifies the source on execution.
   Legacy V1–V3 items keep their original TV-bound semantics.
2. The Owner loop leases up to three items to background threads, preserving
   the **same** worker/provider implementation, model profile and source
   cache. A pending V4 request for the same film is deduplicated (the TV may
   reconnect and request the same A again). A legacy V3 cannot consume a V4
   background request merely because its fingerprint matches.
3. Each P2 job has an independent fingerprint-based folder, `active.lock`,
   numbered `batch-XXXX.json` checkpoints, `batch-XXXX.inflight` markers and
   completed `vi-final.srt`. Another film's unknown-effect marker does not
   block this film. **The same job** is not automatically replayed after an
   uncertain provider effect, even if the Owner process crashes.
4. Reopening completed A verifies the cached original subtitles plus A's
   final translated SRT, cue identity/timing and checkpoint digest. This
   skips OpenSubtitles, AGY model preflight and paid translation. Reopening
   unfinished A rehydrates the latest durable LEAN120 checkpoint for live P4
   consumption without starting a duplicate AGY request.
5. The original film's P4 callback is allowed to fail closed if A is no
   longer current on TV; the translated SRT stays saved privately on Owner.
   A new authenticated A session can reattach to the saved translation.

## A → B → A expected behavior

| Action | Owner P2 | TV P4 |
| --- | --- | --- |
| Start A, request AI | Translate A; persist each batch | Show A's approved revisions |
| Close A, start B, request AI | Continue A; begin B concurrently | Only B may receive B subtitles |
| A finishes in background | Save A `vi-final.srt` | Do not push A into B's session |
| Reopen A while translating | Keep the original A job; no duplicate | Rehydrate A's newest saved batch |
| Reopen A after completion | Verify and reuse A's saved final SRT | Revalidate and deliver A only |

## Storage and delivery boundary

- Source SRT and index: private Owner cache, `*.srt` and
  `.auto-source-<source-fingerprint>.json`, validated with SHA-256 and cue count.
- Translated work: private Owner P2
  `auto-lean120-state/<job-fingerprint>/batch-XXXX.json` and `vi-final.srt`.
  The job key includes source/model/glossary; a material profile change can
  correctly require a different translation.
- TV cache is a separate P4/G1/G2 concern. A TV-side saved `(file)` label
  alone **does not** establish that the current Owner translation completed.
- All current source/Windows installer scripts hash-pin old revisions.
  **Do not** use historical F3/F4/F6/quarantine installers to deploy this
  changed module set: their fixed SHA pin mismatch is intentional. Prepare a
  new audited exact-source Owner release with backup/rollback once live
  provider work is quiescent; never restart Owner during an active A job.

## Acceptance boundary

Offline unit tests cover independent P2 jobs, V4 durable selection,
parallel claims, A reattach, complete SRT reuse and fail-closed TV binding.
No live TV, Windows Owner, TorrServer, OpenSubtitles or AGY provider was
contacted by this source change. Do not declare installed/deployed/TV PASS
until a separate authenticated A→B→A test supplies actual Owner/P4 evidence.
