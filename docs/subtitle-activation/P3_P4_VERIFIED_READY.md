# P3→P4 owner source-ready handoff (Issue #157 continuation)

**Source-only candidate, 2026-11-14.** The explicit Redmi "Bật Vietsub AI" and Windows signed REQUESTED/owner queue are Draft [#159](https://github.com/trung-via/torrent-tv-vietsub/pull/159)/[#158](https://github.com/trung-via/torrent-tv-vietsub/pull/158). This child PR is based on #158. It does **not** alter Redmi/OMP source or provide a second provider worker.

## Missing edge that this child connects

Prior #158 can ask the single owner V3 agent to find VI or translate EN, but the original `AutomaticVietsubFlow.selected_media()` stops at an owner-private `VI_READY/VIETSUB_READY` result. Existing P4 `PairedActivation` resolves pre-supplied EN only; it has no verified owner V3 source-ready pathway for **VI already available** or **EN already translated by existing LEAN120**. Retrying the TV's `/p4/activate` therefore cannot automatically see the existing result.

This branch adds **one local source consumer**, not a new translation engine:
1. `VerifiedV3Processor` (same private owner inbox/worker) calls an optional `on_vietsub_ready` callback **only after** the original D1/D2/local EN/LEAN120 returned `VI_READY` or `VIETSUB_READY`. No REVIEW_REQUIRED or failed source advances.
2. `P3OwnerReadyRegistry.register()` cross-checks live signed Redmi TV session/REQUESTED or ON, owner rights/auto, exact TorrServer server/torrent/file index and name. It reads the original `.auto-source-<fingerprint>.json` from owner-private cache with strict SHA-256/timed-cue checks. For cached VI, this is ready for P4 **without Gemini**. For EN, it locates the **existing completed** P2 `vi-final.srt` using `AutomaticLean120Worker._job_fingerprint`, checks EN/VI matching cue IDs/timecodes and requires completed `translated_cues == cue_count`. This never calls `worker.run` again and never sends a second OpenSubtitles POST.
3. The registry keeps bounded *in-memory* pointers to the original owner-private files. `resolve(mediaKey)` is invoked **only after P4 device HMAC**, and independently re-reads fresh Redmi session/consent and verifies the original file hashes before returning `VerifiedVietsubReady`. Crash/restart requires a new explicit signed viewer request; no persisted ACTIVE.
4. Existing P4 `PairedActivation` has an opt-in `authenticated_vietsub_factory` for this **already-ready VI payload**. It retains the unchanged legacy EN source+translation callback, and refuses to combine conflicting factories. It creates the original signed `SessionRevisionFeed` with source SHA and **one complete cumulative signed revision version 1**, with the exact existing native `media.<sha256>` derived from server profile/torrent/index.
5. The preexisting `compose_owner_redmi_status` adds explicit `enable_verified_vietsub_ready=True` and `p4_gateway=None` mode; it builds the same paired P4 handler, the same verified current reader and V3 callback. Existing default gateway mode is backwards compatible and inert. **No listener is bound or Windows Task Scheduler installed.**

## VI vs EN semantics

- **VI_FAST**: source and payload are the same validated VI SRT; `source_sha256 == payload_sha256`. No Gemini invocation.
- **EN→LEAN120 complete**: source is the matched EN SRT with EN digest; payload is *already generated* `vi-final.srt`, with independent VI SHA. P4 retains EN source identity, returns the final ready VI bytes as one signed P4 offer. This is **final-on-ready**, not a claim of streaming revisions while the original Gemini job was running. Progressive 120→240 on-TV acceptance remains a separate gate.
- No source guessing from a film title and no registration by raw TV JSON. No VI mislabelled as EN, no unsafe cached model replay. Wrong hash/index/session, OFF/OTHER, stale heartbeat, missing P2 final, corrupt bytes, wrong cue count or altered timecodes fail CLOSED.

## Acceptance and limits

Offline synthetic tests (a lawful artificial SRT), exact-head CI and legacy P4/owner/D1/D2 regressions are expected. Actual owner-runtime callbacks (rights inventory, local media roots), Windows ACL/TLS/pairing, installed Redmi APK, provider/API consent and real no-picker cue 131 proof have **NOT** run. The already-requested viewer consent may allow a provider call that began before user OFF; cancellation can refuse any later ready publication but cannot retroactively refund provider quotas. The existing P4 TV receiver independently checks G1 mode ON and media key.

Repository PUBLIC: no movie content, raw source, real IP/cert/secret, provider keys or private file paths committed. Keep Draft/HOLD pending real consumer evidence + independent Brain PASS, under Issue #42.
