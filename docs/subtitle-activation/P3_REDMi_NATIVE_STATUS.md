# Redmi OMP P3 signed current-state native heartbeat (Draft source only)

**Human approved 2026-11-14 ~13:43 ICT**: add real current playback state from Redmi, not merely a one-shot PlayRequest. This candidate is stacked above [PR #151](https://github.com/trung-via/torrent-tv-vietsub/pull/151), and its Windows verifier is sibling [PR #154](https://github.com/trung-via/torrent-tv-vietsub/pull/154) above [#153](https://github.com/trung-via/torrent-tv-vietsub/pull/153).

Pinned upstream OMP `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, G1/G2/P4-composed `PlayerActivity` only. **No new TV app or service.**

## Signed source

`P3SelectedMediaPublisher` continues to send `/p3/selection` for a genuine accepted Play or next QueueItem, with a native 128-bit random `tv_session_id`. It now sends a separate `/p3/state` **first**, over the SAME single background executor, so the PC has a fresh status before it considers selection.

It samples `PlayerSession.request` and actual index, requires VLC engine and matches the current queue item's `hash/fileIndex` to the original native selection. It reads `P1ProductionSubtitles.automaticChoice()` from G1/P4; global metadata ON does **not** fabricate the viewer's per-film ON. Pause/Resume/Seek never cause a new selected-media event. Separate `p3StatusTick` samples state every 3 s while activity is active, and `trackChosen` sends immediately after OFF/OTHER. Closure stops the tick and sends signed inactive status.

Status format `TTV-P3-TV-STATE-V1`: process random `boot_id` + monotonic `sequence` + current selection kind/session/hash/index + active + actual choice + timestamp + nonce + HMAC-SHA256 signed with P4-paired key under a NEW domain. No title, filename, video bytes, LAN server URL or API secrets. It uses existing P4-pinned certificate HTTPS/AndroidKeyStore. Source sample older than 2s is not signed; status receiver expires after 8s silence.

**OFF by default:** P3 owner metadata setting still requires a separate user on-TV toggle and existing P4 pairing. If a movie was already playing before enabling, this source does not synthesize a false new native Play event; next genuine Play/Next is required. P4 per-film ON may still be OTHER before explicit P4 opt-in; this work does not silently turn it ON, and no cloud/provider work is authorized by sending a heartbeat.

## CI and proof limits

Source-only patcher tests and separately scoped disposable **OMP+G1+G2+P4+P3** Android Gradle Debug build are required, without ADB, TV install, artifact upload or release. The owner PC sibling tests cover signed freshness, nonce/replay, A→B→A and HTTPS loopback. Source success ≠ paired Redmi online heartbeat or independently observed no-picker Vietsub.

Remaining: actual owner PC paired HTTPS listener and port consent, installed correct Debug APK/SHA, secure pairing and explicit P3 TV on, verified live TorrServer metadata, 8s/current-state receipt, restart-durable anti-replay, rights/local-VI checks, independent provider and P4 cue 131/no-picker real-TV acceptance. Preserve all previous G1/G2/P4 pause/seek/audio behavior.
