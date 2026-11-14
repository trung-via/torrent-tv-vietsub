# P3 native OMP selected-file sender — candidate, not installed

**Source-only sibling** of [Issue #149](https://github.com/trung-via/torrent-tv-vietsub/issues/149), based on [P4 session reliability Draft #137](https://github.com/trung-via/torrent-tv-vietsub/pull/137). PC signed verifier [Draft #150](https://github.com/trung-via/torrent-tv-vietsub/pull/150) is stacked on V3 [#148](https://github.com/trung-via/torrent-tv-vietsub/pull/148). These are **two branches**, not a merged/installed product.

## Exact source anchors (OMP pin)

`spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` — `PlayerActivity`:
- `private fun load(r: PlayRequest...)`: after `session.load(r,next)`, new accepted queue/file
- `private fun playItem(i: Int)`: after `switcher.goTo(i)` succeeded, new selected file
- `private fun emitClosed(...)`: replacement, exit, active file closed
- **No** signals on tick/browse/pause/resume/seek/phone pairing alone
- `QueueItem.hash` and `fileIndex` supply selected source coordinates; `title` is **not a trustworthy video filename**; `PlayRequest.session` is a nullable local web-view Long, not a collision-resistant owner event session.

The producer `P3SelectedMediaPublisher.kt` uses `SecureRandom` for a new 128-bit `tv_session_id` per actual selection. It signs only `kind, session, hash, fileIndex, timestamp, nonce` with **domain-separated HMAC-SHA256** using existing P4-paired device key; no subtitles, video bytes, title, LAN IP or user credentials in signed body. The PC (not TV) must retrieve exact filename and release metadata from owner-configured TorrServer after authenticating the message. P3 sender cannot itself authorize search/API calls. The PC V3 bridge still must re-read current TV file/ON state and check exact hash/index/session.

The TV may only POST to `https://<private IPv4>:<existing P4 TLS port>/p3/selection`, with `P4PinnedTls` trust and P4 pairing from AndroidKeyStore. **There is no new TV listener**. It returns a single 204 response expectation, never waits for subtitle text. No insecure HTTP, redirects or WAN. Network and signing run off UI thread; packet failure cannot interrupt playback.

## Consent and owner deployment

**OFF by default.** P4 device pairing alone does NOT activate P3 event forwarding. A separate on-TV menu row **Bật/Tắt tín hiệu tự tìm Vietsub** calls `P3SelectedMediaPublisher.setEnabled()`; enabling is refused if P4 pairing is absent. It does not enable automatic subtitle replacement on a movie whose P4 viewer choice is OFF/OTHER. Disabling stops emitting future selection metadata. **No owner consent was activated by committing this source.**

`p3_activity_patch.py` is a *bounded overlay for an already P4-composed disposable source checkout*, not a script that reaches real TV. It:
- defaults to dry-run; --apply requires explicit absolute source root and checks P4 pinned classes/Activity anchors;
- copies only `P3SelectedMediaPublisher.kt` and edits exact one-time `load` / `playItem` / `emitClosed` / menu anchors; does not alter underlying G1/G2/P4 import, seek, audio or Manual OpenDocument selector;
- refuses reapplication, missing P4 overlay or anchor drift; never uploads APK or calls ADB.

## Cross-branch live gap

The TV source is **candidate only**. PC Draft #150 provides strict signed message validation and links origin to existing V3 owner queue, but **does not register /p3/selection on any real owner Windows HTTPS server**. It also requires an independent owner-trusted current TV session and read-only TorrServer selected-file reader. Missing any of these means no event can actually start the automatic flow. P4 pairing TLS not yet verified on the owner's customized Redmi Debug, independent of the previously Human-PASS Xiaomi OMP remote pairing.

## Acceptance gates
- Source: patcher source-anchor guards, explicit opt-in default off, TLS/HMAC cross-language layout, no pause/seek trigger, synthetic tests.
- Compose: build pinned G1+G2+P4+P3 disposable Android Debug APK with Kotlin compile, no TV install (NOT_RUN here).
- Device/server: owner approves P3 P4 pairing, on-TV consent, PC pinned HTTPS route and real one-play signed event, PC source identity read; phone-initiated and D-pad play, A→B→A/closed and OFF/OTHER (NOT_RUN).
- Provider/D3/P4: real allowed EN/local or OpenSubtitles source into LEAN120 and correct Redmi subtitle no-picker (NOT_RUN). Standalone APK release/signing separate approval.

Repository remains PUBLIC; do not publish real torrent hash, movie names, IP, certificate pins, device pairing secrets, API keys or subtitles.
