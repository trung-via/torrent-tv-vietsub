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
4. Existing P2 hosted CI invokes the Kotlin smoke and patcher tests. It
   separately tests the actual pinned G1 source, not only a fake one.

## Not implemented / no inflated acceptance

There is NO Android LAN listener, no TV receiver subscription, no
service or TorrServer change, no live Gemini request, no ADB install,
no real subtitle delivery, and no composed G1+G2+P4 Android Gradle
proof yet. A Kotlin callback contract is not a real active player hook.

A live PlayerActivity integration needs to stage an incoming revision,
import app-private bytes, reuse the existing G2 rollback path, and only
acknowledge successful application on confirmed first frame (not
merely when session.load returns). Current in-memory receiver advances
on callback true, so an asynchronous callback must be treated as
pending until proof of success; do not wire it directly to a
fire-and-forget session load. Persistence across Android process
restart and secure private pairing are also open.

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
