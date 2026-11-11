# P2/P4 — API-first progressive subtitle handoff (OFFLINE seam)

## Human direction and separation of responsibility (2026-11-11)

Human wants an eventual one-tap **Xem ngay với Vietsub AI** experience:
start authorized media once, translate through an approved API in batches
without returning to interactive Brain, compile cumulative captions, deliver
revisions to the matching TV session, and refresh G2 without manual track
selection. Lower API speed than Brain is acceptable **only while the playback
buffer/horizon remains adequate**. Cost, privacy and translation quality remain
mandatory controls.

This PR implements **only a pure, deterministic source-to-revision bridge**.
It does not configure credentials, select a provider, perform HTTP, access a
torrent/MKV/video, change TV/APK, run an AI model or transport subtitle text.
It leaves historical 90-cue Gemini/R3.3 and Brain LEAN120 workdirs unchanged.

## Module: progressive_handoff.py

- Parses original authorized SRT/VTT with existing strict cue_pipeline.
- Splits canonical cue IDs into sequential output windows: at most **120 cues,
  6500 source characters** and **±4 read-only neighboring cues**, with a
  stable SHA256 of the full original source, plus a scoped opaque
  \`media.<64 lowercase hex>\` identity. A long cue exceeding this budget fails.
- Caller obtains next immutable TranslationWindow and supplies a map of **only
  its target cue IDs**. The module neither calls nor chooses an API.
- Requires exact IDs **in original order**, unchanged source/media identity,
  expected current version, plain UTF-8 Vietnamese text and valid original
  timestamps/metadata. A missing/extra/stale/unsafe response is rejected
  without changing the preceding revision.
- Generates cumulative, versioned SRT/VTT bytes: first 1–120, then 1–240,
  then 1–360 etc. Timing and cue indices are **never based on viewing time**.
  Each payload has SHA256, version, exact media identity, cue count and
  translated end timestamp; future transport must check these fields before
  applying it. Byte size is capped at G1 TV's current **256 KiB**.
- The offline \`horizon(playback_ms)\` method returns
  \`NO_SUBTITLES_YET\`, \`AVAILABLE\`, \`NEAR_TRANSLATED_HORIZON\`, or
  \`TRANSLATION_BEHIND_PLAYBACK\`. It does not actually pause a film, schedule
  a translation call, or estimate provider latency.

## Next independently authorized stages

1. **API adapter:** choose an actual supported provider/model/API, opt-in
   scope, secret storage outside repo, privacy/rights to send subtitle text,
   budget/quotas, bounded retries, QA and exact-ID parsing. Existing
   \`cloud_contract.py\` is a **12-target-cue Gemini-specific offline contract**
   and must not be silently called or mutated into the future 120-cue
   default. A model-neutral adapter should explicitly map a Window to a
   provider request and verify its response. ChatGPT Brain may remain a
   quality reference; it is not an unattended service.
2. **Durable checkpoint/publisher:** persist only in private scoped storage
   (source+media+model/version identity, monotonic revision and atomic
   commits); retry without double-paying; handle restart, cancellation,
   rate limits and costs. Deliver each verified cumulative revision using an
   authenticated LAN-only transport to the exact TV media session.
3. **G2 integration:** TV validates identity/version/SHA256 and only refreshes
   when opted in and subtitles ON, preserving OFF/OTHER, audio, position and
   pause state. An automatic feed must not defeat a user's OFF selection.
   G2 PR #115 is a **manual in-player import/reload** candidate; it does not
   yet subscribe to this revision feed.
4. **End-to-end gates:** same right-cleared SRT/VTT on Redmi, no per-window
   Human action, tested position/horizon/seek/reopen/A→B→A and bad files,
   no copyrighted subtitle text in public GitHub; separately verify real VLC
   recovery and G4 release isolation.

## Offline test

\`python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v\`

New tests exercise 120→240→245, true original timeline, media/source
identity, stale/extra/unsafe values, in-memory rollback, TV 256 KiB size cap,
first/last horizon, VTT settings, and pure no-transport operation. A green CI
result means **OFFLINE CONTRACT PASS**, not live API, TV auto-update or release.

No new user interaction, existing media upload, public subtitle text, ADB,
TorrServer, cloud bill or host service is authorized/attempted here.
