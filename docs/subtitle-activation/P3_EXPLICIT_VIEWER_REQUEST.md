# Issue #157 — Per-film explicit Vietsub AI request before P4 receiver activation

**Human decision 2026-11-14:** opening video only identifies it and establishes a private paired TV session; **the explicit "Bật Vietsub AI" tap** begins D1/D2 VI_FAST, local EN direct, or EN→existing LEAN120 if needed. P4 receiver starts only after exact matched source is available. This is the source-only PC half, stacked on [Draft #156](https://github.com/trung-via/torrent-tv-vietsub/pull/156). The Redmi UI half is a separate PR on #155. **No change to real TV or owner services.**

## Root cause

Old P4 `beginP4Activation` contacted `/p4/activate` before its G1 `setAutomaticOptIn(..., true)`. `PairedActivation.activate` returns `P4_ASSUMED_SOURCE_MISSING` until exact source already exists. P3 status formerly required `automaticChoice == ON`, so discovery could not happen for a video with no source. This is a source-level deadlock, not a reproduced Redmi bug.

## State contract

1. On native OMP PLAY/NEXT: TV assigns new per-selection random `tv_session_id`, signs `PLAY_REQUEST_ACCEPTED` / `NEXT_QUEUE_ITEM_ACCEPTED` and sends `/p3/state` (3s heartbeat, actual selected file, actual G1 mode). **PC returns SKIP: MEDIA_IDENTIFIED_AWAIT_VIEWER_REQUEST**. Never search/download/translate on Play, Seek, Pause, Resume, library-add or opening a catalog.
2. On a **direct user action** on the current Redmi item, the native P3 companion sets session-scoped `requested`, signs status `subtitle_choice=REQUESTED` only if G1 mode is OTHER and the *same* VLC queue hash/index/session is active, then signs the distinct selection-kind **`VIEWER_VIETSUB_REQUESTED`** with its original current session ID and exact hash/index. All signed packet fields, bounds, nonce replay, owner P4 pairing/HMAC, private pinned HTTPS and journal remain unchanged. There is NO forged PLAY event.
3. PC only dispatches this explicit signed viewer-request kind when its **separately authenticated current state** is `REQUESTED`, matches the same TV session, hash, fileIndex and already configured owner server/rights/local VI. Owner `SignedP3ToOwner`, `ActivationDeduplicator` and the existing V3 selected-file resolver accept this state **for discovery only**, then reuse the existing owner-private single queue, verified `matcher.Media`, D1/D2 OpenSubtitles/local EN and existing LEAN120 worker.
4. `REQUESTED` is NOT native P4 `ON` and not receiver acceptance. `P1ProductionSubtitles.automaticChoice` still returns ON only after existing P4 activation succeeds and G1 opted into that exact media. P4 signed revision imports continue to require ON + exact matching media/session/stream.
5. A user OFF/OTHER, changed file, next video B, closed player, missing/expired 8-second status or rights failure must refuse new provider work and delivery. Existing in-flight charged provider requests cannot always be preempted; apply no subtitle on TV after OFF and revalidate immediately before any later charge where supported.

## Distinct activation readiness

PC `PairedActivation` already has an `authenticated_source_factory(mediaKey)` for the exact owner-selected media. The owner must wire a **verified source-ready receipt** from the *existing* D2/P2 pipeline into this factory; it must never fabricate a source or trust a UI title. The TV P4 half will retry its **existing** authenticated `/p4/activate` only while the session-scoped user request remains active, within a bounded timeout, then bind the existing P4 receiver. No independent AI queue or new public endpoint.

### Verified source-ready P4 boundary (synthetic contract)

The existing `PairedActivation(authenticated_source_factory=...)` already allows the same paired P4 `/p4/activate` to **HOLD while the source is absent** and succeed when a matching, hashed owner-private source appears in the existing `verified_source_manifest` registry. `test_p3_p4_source_ready.py` proves an artificial D1/D2-ready EN receipt can activate the **same P4 controller**, publish synthetic signed 120→240 cumulative revisions (including cue 131), and reject a different torrent or tampered EN bytes; no second AI provider call is made.

**A remaining production integration gap is real:** no current P3 owner agent automatically writes a verified `mediaKey → EN source` manifest from #148 D1/D2/LOCAL_EN receipts, and the VI_FAST ready-only route must publish VI without treating it as English or re-translating it. This fixture tests the existing P4 source-ready boundary, not a real D2→P4 publisher. Do not call #157 end-to-end accepted until that independent source registration and real TV evidence are done.

### Gates

- This branch: strict HMAC viewer-tap event, TV status REQUESTED signed wire, explicit-only dispatch, legacy Play-only SKIP, resolver session/file match, OFF/OTHER and replay negative tests; exact HEAD offline CI.
- Sibling Redmi branch: exact P4-composed activity hooks, explicit UI toggle, status before request, bounded P4 activation retry, cancel on OFF/OTHER/switch/close, Kotlin/Gradle Android Debug build on dedicated Windows runner.
- **Still NOT_RUN:** real owner source-ready→P4 paired session activation, signed TV↔Windows LAN status and consent, installed exact Redmi APK, OpenSubtitles/Gemini live API and P4 no-picker cue-131 acceptance. No credentials, private torrents, movie content, API quota calls or Windows network/service modifications in PUBLIC repo.
- Draft/HOLD until independent Issue #42 Brain review, exact HEAD/base CI and actual consumer proof. User approval to implement is not permission to install or release.
