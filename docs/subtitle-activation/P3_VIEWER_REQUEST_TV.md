# Issue #157 — Explicit on-TV Vietsub AI request (native OMP)

**Decision 2026-11-14:** Playing a video only identifies it. Pause/resume/seek never trigger D1/D2 or LEAN120. Only the direct **Bật Vietsub AI** button on the exact currently playing native VLC queue item may request subtitle acquisition. Implementation is a Draft child of [#155](https://github.com/trung-via/torrent-tv-vietsub/pull/155); its owner-PC counterpart is [#158](https://github.com/trung-via/torrent-tv-vietsub/pull/158).

## Native state machine

- **IDENTIFIED:** existing G1/G2/P4-composed activity accepts a true native Play/Next, generates session and signs selection and current-state heartbeat. Windows **SKIPs** subtitle work.
- **REQUESTED_BY_VIEWER:** on the **direct button** only, `P3SelectedMediaPublisher.requestViewer` checks enabled private P3 metadata sharing, already paired P4 and the exact current VLC request/index/hash/file. The in-Activity session owns a volatile `requestedByViewer` flag (never a global or another episode). It sends signed **REQUESTED current-status first** and then HMAC **VIEWER_VIETSUB_REQUESTED** event with the same native session/hash/fileIndex. It never fabricates a new PLAY event.
- **WAIT_SOURCE:** the same existing P4 `beginP4Activation` is called on the current TV item while the PC existing D1/D2→LEAN120 acquires authorized VI/EN source. `/p4/activate` initially reports source missing; existing TV request retries at most once per 15 seconds, **max 120 attempts / 30 min** while same session and user request survive. At each retry it can resend the same explicit viewer intent with a **new HMAC nonce** after a fresh REQUESTED status; owner V3 private dedup + one-POST claim prevent duplicate downloads. No added worker or second provider.
- **P4_RECEIVER_ACTIVE:** after the **existing authenticated P4 source-ready activation** succeeds, original G1 `setAutomaticOptIn(...,true)` grants exact per-film ON and P4 signed reception; retry stops and status reports ON. Until then P4 ON is never fabricated.
- **CANCEL:** user presses Tắt or chooses another subtitle/turns OFF: aborts pending retries and invalidates P4 in-flight generation, clears `requestedByViewer`, emits signed status OTHER/OFF and stops the current P4 session if active. Switching file B replaces native session, closes player stops heartbeat and pending retry; old A intent must never control B. If 30 min expires the current request clears, requiring a new direct tap.

`P3SelectedMediaPublisher` is disabled until the separate on-TV private metadata consent is enabled and PC P4 pairing exists; pressing Vietsub AI while disabled explains the prerequisites. This is intentional owner consent, not a silent new network permission. No title/subtitle bytes/provider API key, server URL or LAN IP in signed payload. The recipient server and owner Windows replay journal remain controlled by existing P4 pinned HTTPS and #156.

## Acceptance boundaries

Source-only patch/fixture tests and exact self-hosted Windows G1/G2/P4/P3 Gradle Android Debug build are separate from real device acceptance. This PR does **not** install APK, bind Windows TLS route, configure TorrServer or charge OpenSubtitles/Gemini.

Still necessary: authenticated owner **source-ready receipt** from existing D2/P2 cache to P4 `authenticated_source_factory` for correct `mediaKey`, actual local Windows P4 gateway and owner current-status, signed real Redmi consent event and P4 no-picker subtitles after explicit ON. OFF while a provider HTTP call is already in flight cannot undo the charge already incurred; the native receiver must nevertheless refuse later revisions when OFF/OTHER. All PRs Draft/HOLD under Issue #42.
