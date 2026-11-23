# P4 native subtitle receiver — source candidate

Base: G2 Draft PR #115, pinned at b0994c7b33b7dac1d8fdacda1c49af853c32285d.
P2 publisher/API work is separate Draft PR #118. This P4 change is a
stacked branch, and does not modify the already tested G2 source.

## Implemented

1. P4SignedReceiver.kt checks Python-compatible HMAC-SHA256 with exact
   session, media, source digest, file digest, monotonic version, UTF-8
   SRT/VTT timing, cue count and 256 KiB cap. OFF/OTHER, wrong engine,
   stale or invalid offers are never applied.
2. P4SignedReceiverSmoke.kt has precomputed cross-language Python
   signatures and both positive and negative pure Kotlin/JVM tests.
3. apply.py is a guarded dry-run by default for an already G1+G2-patched
   disposable OMP tree. It keeps the original human file picker and adds
   an internal app-private G1 byte import method. It rejects wrong
   media and persisted OFF/OTHER, uses existing G1 validation/registry,
   and serializes user track selection with P4 imports.
4. activity_patch.py now adds Activity-scoped bindP4Session() and
   receiveP4Revision() for FUTURE private pairing/transport integration. It
   snapshots G1 subtitle bytes before importing the next revision, invokes
   G2RefreshInPlace.prepare() and session.load() for the SAME VLC queue item,
   restores pause, current position and selected audio, and calls the P4
   two-phase ACK only from the G2 first-frame callback with the exact
   P4-created PlayRequest identity. Failure, load/switch and destruction
   abandon an unacknowledged revision without advancing the accepted cursor.
   The patch is guarded by exact existing G2 activity anchors, and preserves
   the original manual picker callback.
5. P4LanClient.kt adds a **pull-only** Android client for a fixed RFC1918
   IPv4 PC address and session-specific endpoint. It reads a bounded JSON
   envelope from a local HTTP feed, refuses redirects and oversized data,
   then passes unsigned/untrusted bytes to P4SignedReceiver for SHA/HMAC
   and current movie/ON preference verification. It does NOT open an
   inbound port on the TV. HTTP over trusted LAN is integrity-protected
   by HMAC but is **not confidential/encrypted**.
6. activity_patch.py includes **internal** startP4LanSession/stopP4LanSession
   hooks and a lifecycle-scoped 6-second poll loop. Pairing/opt-in must
   explicitly invoke start; no listener, hidden background service, or
   automatic startup is registered. Poll results are returned to the UI
   thread and fed to the existing signed receiver. Activity destruction,
   media switching or new playback cancels the poll session.
7. P2 hosted CI tests Kotlin receiver, actual G1 overlay and Activity
   guards. A new owner-only PR #120 Windows CI composes pinned OMP+G1+G2+P4
   into a disposable checkout and runs full Android Gradle Debug/unit
   without publishing APK artifacts.

## Not implemented / no inflated acceptance

There is NO Android LAN listener, no pairing UI/provisioned secret,
no public service or TorrServer change, no live Gemini request, no ADB
install and no real subtitle delivery. The P2 branch Draft #118 now has a
synthetic-verified SessionRevisionFeed serving HMAC-signed cumulative
revisions on an explicitly bound RFC1918 address; **the server has not
been started** on a real PC. The P4 Android client exists but will not
poll until a future one-time pairing/opt-in UI calls its internal start
method. No Windows firewall, router or TV settings were changed.

The preceding composed build [Actions #43063364920] PASSED pinned
OMP+G1+G2+P4 Android assembleDebug/testDebugUnitTest (runner-local APK
hashes recorded on PR #120). That prior proof is for the source HEAD
**before** adding P4LanClient: this new source needs its own exact-head
Gradle run. No on-device network fetch or automatic Vietsub playback
has been tested.

P4SignedReceiver now implements two-phase acceptance. A callback that starts
the G2 reload returns G2_PENDING_FIRST_FRAME, without advancing the applied
version. Only acknowledgeFirstFrame() confirms the same active session/media,
ON preference, VLC engine and digest. abortPending() discards a failed or
timed-out revision, so it can be retried. Kotlin tests exercise these paths.

The Activity overlay includes first-frame ACK, existing G2 rollback
and per-request identity checks to prevent unrelated/manual reloads
from acknowledging a P4 revision. A compiled APK cannot prove real
LibVLC first-frame or rollback events without device validation.
Process-restart revision persistence and one-time pairing UX remain open.

## Next bounded gates

- Verify the new P4 LAN pull client in exact-head composed Android Gradle.
- Implement a private, one-time LAN pairing/secret-provision UX and a
  **single per-film "Bật Vietsub AI" action**, without overriding OFF/OTHER.
  The first batch may need an explicit "ON" opt-in instead of assuming
  an existing saved SRT already exists.
- Test actual local source P2 feed→P4 client→G2 reload with synthetic
  captions and inspect first-frame ACK/rollback before any real film.
- Owner-approved physical Redmi 120→240 automatic update without
  opening the document picker, including OFF/OTHER, A→B→A, error rollback.
- Separate live Gemini API demo with an available private key and
  chosen right-cleared source.
- G4 release/signing separately.

Offline test: python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v
