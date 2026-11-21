# P3 Signed Redmi CURRENT playback state — source candidate

**Owner Human decision 2026-11-14 ~13:43 ICT:** add Redmi current playback status before automatic subtitle activation. This project is independent of AIOS, and this is a Draft child of #153, ultimately #148 V3 exact selected-media and #120/#137 P4.

## A signed Play event is NOT enough

Earlier P3 HMAC PlayRequest message proves only the P4-paired sender generated a selection event. Windows cannot infer from that message alone whether the Redmi is **still** playing that same movie/episode, has changed to B, returned to A, or the viewer selected OFF/OTHER. Thus no D1/D2/Gemini call until a separately signed **current native UI snapshot** is both fresh and identity-matched.

## Status wire: distinct domain from P3 event and P4 subtitle

TV sends **POST /p3/state** through the existing owner-approved P4 pinned-TLS HTTPS handler. Explicitly optional route; no listener is created here. Packet `TTV-P3-TV-STATE-V1` contains only:

- `boot_id`: new 128-bit random per Android process; `sequence`: monotonic per process;
- `kind`: accepted PLAY or NEXT (same current selection kind); `tv_session_id`: random 128-bit ID created by P3 native Play/Next, not OMP WebView session counter;
- `torrent_hash`: lower 40-hex; `file_index`: exact selected TorrServer file; `active`: sampled true only while native VLC session still matches; `subtitle_choice`: actual G1/P4 `automaticChoice` ON/OFF/OTHER;
- `sent_at_ms`, random 128-bit `nonce`, `signature`: HMAC SHA256 of canonical ASCII fields under the existing paired TV secret and the distinct **TTV-P3-TV-STATE-V1** domain. Never disclose title, subtitle bytes, LAN URL, profile, API key or pairing material.

Canonical MAC lines: schema / boot / sequence / kind / session / hash / fileIndex / active(1|0) / choice / sentAt / nonce, separated by ASCII newline (no trailing newline). TV must SAMPLE native `PlayerSession.request/index`, VLC type, `closedSent`, and `P1ProductionSubtitles.automaticChoice(...)` **on the Android main thread at each status send**, not replay a prior accepted event as a fake heartbeat. Pause/resume may leave `active=true` but never create a new Play/Next event. OFF/OTHER and close cause a signed inactive/not-ON report immediately, as well as 3-second refresh while active.

## Owner state validation and use

`p3_redmi_current_state.SignedRedmiStateCache` verifies bounded JSON, constant-time HMAC, ±15-second clock skew, bounded nonce replay, boot and strictly ascending sequence. A new boot cannot replace a fresh old process state. A signed sample is accepted at most **8 seconds from local monotonic RECEIVE time**; silence, stale timestamp, stopped/closed or OFF/OTHER strictly HOLD.

`p3_owner_current_redmi.OwnerCurrentRedmiReader` creates the sole current OMP state for both existing `SignedP3ToOwner` and #148 `VerifiedV3Processor` from **two separate sources**: fresh authenticated TV state + exact owner-pinned localhost TorrServer `/torrents get` file metadata. Owner AUTO permission, media rights and local VI-track inventory come from explicit configured owner-only callbacks; the wire cannot assert them. Read status twice around metadata/owner checks to stop A→B/session race; downstream #148 revalidates again and D3/P4 must recheck immediately before subtitle delivery.

`p3_p4_shared_https_route` preserves existing /p4/activate and /p4/revision and P3 /p3/selection semantics; /p3/state is optional and is 404 until explicitly configured with the paired cache. It receives HMAC status but **does not enqueue a job or run providers merely because a heartbeat arrived**.

## One existing owner gateway/worker composition

`p3_owner_state_wiring.compose_owner_redmi_status` is the concrete typed glue between the already built components. An explicit owner-local process supplies:
- the **existing** P4 `PairedActivation` controller and its same P4-paired key;
- the already owner-pinned `OwnerTorrServerReader` from #153;
- absolute private owner inbox/media roots and exact per-media file mapping;
- **separate** owner AUTO consent, media rights and local VI-track inventory readers, none derived from TV JSON.

The composition returns `handler` for the already approved P4 TLS server, `cache` for signed native status, `signal` for selection HMAC and `trusted_v3_factory` for the **existing #146 owner agent**, not a new translator/queue. The factory supplies the #148 `VerifiedV3Processor` read-only selected-media checks. A synthetic test proves that without a distinct signed current state a perfectly valid Play HMAC cannot queue work, while valid state + exact media does reach the **same existing V3 worker once**. Status alone cannot trigger translation.

The composition intentionally has no `serve_forever()`, Windows background service, credential loader, pairing-installer, model call or on-TV operation; no owner runtime invokes it until separately approved.

## Remaining security and release gates

The current cache's boot/sequence/nonce high-water marks are in-process: **not persistent across owner process restart**. This remains a real acceptance blocker for an unattended network service. A production owner runtime must durably persist replay high-water marks, verify paired identity and restrict concurrency. Same paired secret must be provisioned and owner-local Windows port explicitly approved; no development test creates a Windows LAN endpoint.

Owner-native Kotlin sender, PlayerActivity current-state callbacks, pinned Android Debug build and test are separate sibling PR based on #151. No real TV change or Play-initiated status proof is made in this PC PR.

**Do not automatically set 'ON'.** In P4 the current G1 `automaticChoice` is ON only after explicit per-media P4 opt-in; if unselected it is OTHER even if global P3 metadata reporting is enabled. The follow-up product choice whether to change the per-film opt-in UX must be made separately and should not be silently broadened by status transport work.

Evidence is source/synthetic only, not Redmi network validation or Gemini/OpenSubtitles provider success; all PRs remain Draft/HOLD until Issue #42 independent review, exact HEAD CI and required real consumer proof.
