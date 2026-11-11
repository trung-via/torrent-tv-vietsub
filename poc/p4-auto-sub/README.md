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
5. Existing P2 hosted CI invokes Kotlin receiver smoke and patcher tests,
   including the actual pinned G1 source and bounded G2 source-shaped
   PlayerActivity fixture; no public network or real movie source involved.

## Not implemented / no inflated acceptance

There is NO Android LAN listener, no registered TV receiver or pairing
UI, no service or TorrServer change, no live Gemini request, no ADB install
or real subtitle delivery. The source patch NOW includes an internal,
Activity-scoped callback wiring to G1/G2, but it has not been compiled
against an actual full Android/Gradle OMP checkout or installed on Redmi.
The authenticated caller is not implemented; merely adding methods does
not cause a subtitle file to arrive automatically.

P4SignedReceiver now implements two-phase acceptance. A callback that starts
the G2 reload returns G2_PENDING_FIRST_FRAME, without advancing the applied
version. Only acknowledgeFirstFrame() confirms the same active session/media,
ON preference, VLC engine and digest. abortPending() discards a failed or
timed-out revision, so it can be retried. Kotlin tests exercise these paths.

The Activity overlay now includes calls to first-frame ACK and the
existing G2 rollback/lifecycle guards, plus per-request identity checks to
avoid an unrelated/manual reload acknowledging a P4 revision. However,
the source hooks are STILL unverified by Android Gradle and real LibVLC
events. Preserve the previous subtitle on rollback; in particular, abort
a pending revision if the player changes media or OFF/OTHER is chosen.
Process-restart persistence and private pairing/transport remain open.
## Next bounded gates

- Compile actual pinned OMP+G1+G2+P4 in disposable Android Gradle.
- Implement lifecycle-safe P4 first-frame ACK and owned LAN-only
  paired transport with no arbitrary exported Android intent.
- Owner-approved physical Redmi 120→240 automatic update without
  opening the document picker, including OFF/OTHER, A→B→A, error rollback.
- Separate live Gemini API demo with an available private key and
  chosen right-cleared source.
- G4 release/signing separately.

Offline test: python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v
