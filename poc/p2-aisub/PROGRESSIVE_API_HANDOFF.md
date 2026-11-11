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

## LEAN120 API adapter (new on this Draft PR)

- \`lean120_api.py\` adapts the **same LEAN120 contract** to an actual Gemini
  \`generateContent\` request. Cues are chunked at **120 target IDs / 6500
  source characters**, with **4 neighboring cues on each side as read-only
  context**; a stable film glossary is carried to every request. The API
  transport uses structured JSON \`[{id, vi}]\`, semantically identical to the
  compact, historical \`ID|VI\` outputs. Only translated text is replaced:
  cue ID, timing, order and context association are immutable.
- The temporary model is set in **editable**
  \`poc/p2-aisub/translator_profile.json\`:

  \`\`\`json
  {"provider":"gemini","model":"gemini-3.8-flash","thinking_level":"medium"}
  \`\`\`

  This is **configuration, not a hard-coded fallback in the Python client**.
  Change the model string or thinking level in the profile without touching
  the parser/translation algorithm. To switch to a different provider family,
  implement its dedicated adapter against the same \`TranslationWindow\`
  and \`SubtitleRevision\` interface; do not rename Gemini models into
  another provider's endpoint.
- The official Google API model ID is **\`gemini-3.8-flash\`** and the separate
  \`thinkingLevel\` value is **\`MEDIUM\`**, *not* a synthetic model ID like
  \`gemini-3.8-flash-medium\`. Source:
  https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
  and https://ai.google.dev/gemini-api/docs/generate-content/thinking
- \`translate_all()\` processes every window sequentially without a Human
  file-picking step. Its \`on_revision\` callback publishes the **validated**
  cumulative payload after each batch (120 → 240 → …), not at end of film.
  Existing G1's 256-KiB per-file cap still applies.
- The CLI needs only an existing user-supplied \`.srt\`/\`.vtt\`, opaque
  \`media.<64 hex>\` identity, API key in \`GEMINI_API_KEY\`, output dir,
  and explicit \`--execute-api\`. Keys never enter JSON profile or repo.
  The CLI writes versioned files, not the TV; no provider calls occur in CI.
  Example (locally, with a source the user may submit to that provider):

  \`\`\`powershell
  $env:GEMINI_API_KEY = '<key in local secret environment>'
  python poc/p2-aisub/lean120_api.py --source source.srt --media-key "media.$('a' * 64)" --output-dir .\local-revisions --execute-api
  \`\`\`

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

1. **API adapter + initial LEAN120 implementation:** now present in this PR
   for \`gemini-3.8-flash\` / \`MEDIUM\` via replaceable JSON profile, strict
   structured response validation and on-demand \`generateContent\` client.
   The **first live request** remains untested until an authorized source
   and local API key are available. The older \`cloud_contract.py\` is a
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

\`python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v\`

New tests exercise 120→240→245, true original timeline, media/source
identity, stale/extra/unsafe values, in-memory rollback, TV 256 KiB size cap,
first/last horizon, VTT settings, and pure no-transport operation. A green CI
result means **OFFLINE CONTRACT PASS**, not live API, TV auto-update or release.

No new user interaction, existing media upload, public subtitle text, ADB,
TorrServer, cloud bill or host service is authorized/attempted here.
