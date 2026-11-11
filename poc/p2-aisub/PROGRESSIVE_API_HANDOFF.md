# P2/P4 — API-first progressive subtitle handoff (OFFLINE seam)

## Human direction and separation of responsibility (2026-11-11)

Human wants an eventual one-tap **Xem ngay với Vietsub AI** experience:
start authorized media once, translate through an approved API in batches
without returning to interactive Brain, compile cumulative captions, deliver
revisions to the matching TV session, and refresh G2 without manual track
selection. Lower API speed than Brain is acceptable **only while the playback
buffer/horizon remains adequate**. The Human does not want a separate
per-film spend calculator or repeated rights-approval flow; accuracy and
secrecy still matter.

This PR provides a deterministic subtitle revision bridge **and an optional
CLI Gemini API client**. A network request occurs only if a user explicitly
runs the CLI with --execute-api and a local GEMINI_API_KEY. No key or real
source was used in GitHub CI; no TorrServer, TV/APK or media extraction is
included. Historical 90-cue Gemini/R3.3 and Brain LEAN120 workdirs stay intact.

## LEAN120 API adapter (new on this Draft PR)

- `lean120_api.py` adapts the **same LEAN120 contract** to an actual Gemini
  `generateContent` request. Cues are chunked at **120 target IDs / 6500
  source characters**, with **4 neighboring cues on each side as read-only
  context**; a stable film glossary is carried to every request. The API
  transport uses structured JSON `[{id, vi}]`, semantically identical to the
  compact, historical `ID|VI` outputs. Only translated text is replaced:
  cue ID, timing, order and context association are immutable.
- The temporary model is set in **editable**
  `poc/p2-aisub/translator_profile.json`:

  ```json
  {"provider":"gemini","model":"gemini-3.8-flash","thinking_level":"medium"}
  ```

  This is **configuration, not a hard-coded fallback in the Python client**.
  Change the model string or thinking level in the profile without touching
  the parser/translation algorithm. To switch to a different provider family,
  implement its dedicated adapter against the same `TranslationWindow`
  and `SubtitleRevision` interface; do not rename Gemini models into
  another provider's endpoint.
- The official Google API model ID is **`gemini-3.8-flash`** and the separate
  `thinkingLevel` value is **`MEDIUM`**, *not* a synthetic model ID like
  `gemini-3.8-flash-medium`. Source:
  https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
  and https://ai.google.dev/gemini-api/docs/generate-content/thinking
- `translate_all()` processes every window sequentially without a Human
  file-picking step. Its `on_revision` callback publishes the **validated**
  cumulative payload after each batch (120 → 240 → …), not at end of film.
  Existing G1's 256-KiB per-file cap still applies.
- The CLI needs only an existing user-supplied `.srt`/`.vtt`, opaque
  `media.<64 hex>` identity, API key in `GEMINI_API_KEY`, output dir,
  and explicit `--execute-api`. Keys never enter JSON profile or repo.
  The CLI writes versioned files, not the TV; no provider calls occur in CI.
  Example (locally, with a source the user may submit to that provider):

  ```powershell
  $env:GEMINI_API_KEY = '<key in local secret environment>'
  python poc/p2-aisub/lean120_api.py --source source.srt --media-key "media.$('a' * 64)" --output-dir .\local-revisions --execute-api
  ```

- **Human operational simplification:** no per-120-cue manual confirmation,
  budget calculator, quotas comparison or repeated rights questionnaire.
  A single explicitly initiated API job and lawful user-supplied source are
  the trust boundary. Existing privacy safeguards (don't log caption text
  or credentials, no GitHub upload) remain.
- **Verified level:** synthetic CI with injected mock transport; **no live
  Gemini API token was used and no real subtitle text was sent**.

## Module: progressive_handoff.py

- Parses original authorized SRT/VTT with existing strict cue_pipeline.
- Splits canonical cue IDs into sequential output windows: at most **120 cues,
  6500 source characters** and **±4 read-only neighboring cues**, with a
  stable SHA256 of the full original source, plus a scoped opaque
  `media.<64 lowercase hex>` identity. A long cue exceeding this budget fails.
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
- The offline `horizon(playback_ms)` method returns
  `NO_SUBTITLES_YET`, `AVAILABLE`, `NEAR_TRANSLATED_HORIZON`, or
  `TRANSLATION_BEHIND_PLAYBACK`. It does not actually pause a film, schedule
  a translation call, or estimate provider latency.

## P2→P4/G2 authenticated revision handoff (source-only contract)

The new `revision_delivery.py` defines a **signed cumulative revision offer**.
It is a reusable *data/policy contract*, not a running socket server or an
Android receiver. The caller supplies a paired TV session identifier and
a private 16+-byte pairing secret; the offer binds:

- opaque `media.<sha256>` key and original subtitle source SHA256;
- TV session identifier, monotonic version, SRT/VTT format;
- cumulative cue count, total cue count, translated timeline horizon;
- exact subtitle payload SHA256 and a canonical HMAC-SHA256.

A future native G2 receiver must validate the same fields and HMAC before
accepting a subtitle revision, then atomically import the new app-private
subtitle and invoke the *existing* G2 in-place VLC reload. It must never
use an external URL, file-picker location, TorrServer admin endpoint or
GitHub artifact as a replacement for the authorized local transport.

The offline `PairedSubtitleReceiver` demonstrates the desired behavior:
the current TV session+media key must match; when subtitles are OFF/OTHER,
the offer is deferred without forcing subtitles ON; non-VLC engines are
deferred; duplicate versions do nothing; stale versions and payload tampering
are rejected. A later **complete cumulative** version can be selected
after OFF→ON without requiring earlier partial versions. The callback
receives only validated UTF-8 SRT/VTT bytes and updates the applied revision
cursor **only if** the G2 apply callback succeeds.

**Important proof boundary:** the current callback is a **synthetic injected
test callback**. This file does not make a real LAN connection, install an
APK, patch `PlayerActivity`, write to Android storage, or prove LibVLC
reload-after-transport. Existing G2 PR #115 still needs a real app-private
import entrypoint and lifecycle-aware receiver, and the Windows publisher
needs an authenticated local delivery path. Do not label this stage real
no-picker Redmi PASS.

### Integration stages

1. **Current:** callable Gemini API adapter + versioned LEAN120 translation
   output + authenticated signed delivery offer (all reviewed via synthetic
   tests; live API not yet tested).
2. **P4 receiver:** native OMP/Android activity or session-scoped subscriber
   using paired credentials in private app storage. The receiver must validate
   session identity, SHA256/version/HMAC and ON/OFF/OTHER before importing
   validated bytes through G1 and then invoking G2's in-place reload. Test
   rollback and process/lifecycle restart. Never expose a generic broadcast,
   an arbitrary file path or public LAN admin API.
3. **Authorized LAN transport:** publisher stores only scoped revision payloads
   and sends them over authenticated home LAN to the paired TV; no WAN
   port-forwarding or TorrServer control. Network/listener changes require
   a separate security/host review.
4. **TV acceptance:** send 120→240 valid synthetic revisions *while playing
   a lawful test video* without opening the subtitle menu. Check cue 131,
   pause/seek/reopen, A→B→A, OFF/OTHER and recovery. Existing manual G2 Thor
   acceptance does **not** replace this new automatic-delivery test.

## Next independently authorized stages

1. **API adapter + initial LEAN120 implementation:** now present in this PR
   for `gemini-3.8-flash` / `MEDIUM` via replaceable JSON profile, strict
   structured response validation and on-demand `generateContent` client.
   The **first live request** remains untested until an authorized source
   and local API key are available. The older `cloud_contract.py` is a
   separate 12-cue Gemini-specific offline contract and is not silently
   mutated. ChatGPT Brain remains a quality reference only, not a required
   interactive per-batch step.
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

`python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v`

New tests exercise 120→240→245, true original timeline, media/source
identity, stale/extra/unsafe values, in-memory rollback, TV 256 KiB size cap,
first/last horizon, VTT settings, and pure no-transport operation. A green CI
result means **OFFLINE CONTRACT PASS**, not live API, TV auto-update or release.

No new user interaction, existing media upload, public subtitle text, ADB,
TorrServer, cloud bill or host service is authorized/attempted here.
