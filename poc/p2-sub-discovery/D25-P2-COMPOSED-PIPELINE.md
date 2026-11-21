# D2.5 → P2 Direct Pipeline — composed source, no redundant handoffs

**Owner decision:** continue the small, direct integration. This is the
standalone composed source candidate in [Draft #134](https://github.com/trung-via/torrent-tv-vietsub/pull/134),
tracking [Issue #132](https://github.com/trung-via/torrent-tv-vietsub/issues/132).
The repo is PUBLIC; no owner movie name, downloaded subtitle text, API key,
provider file ID or owner cache digest belongs in GitHub.

## One production chain

```text
Selected authorized media name
      |
      v
Current VI track/verified cached VI? ─YES─> VI SRT
      | no                           |
      v                              |
VI_FAST (<=1 VI GET)                 |
      | no confident VI             |
      v                              |
EN metadata (<=2 pages)              |
      | one confident EN            |
      v                              |
One approved OpenSubtitles POST       |
      | timed EN asset QA            |
      v                              |
Exactly one private EN cache file     |
      | SHA256 + cue count receipt   |
      v                              |
P2 cached_en_direct_handoff          |
      | original existing EN bytes  |
      | explicit owner cloud consent|
      v                              |
EXISTING #118 LEAN120 worker          |
      | <=120 cues / <=6500 chars    |
      | +/-4 read-only context       |
      | durable no-retry checkpoints |
      v                              |
Private VI SRT/VTT <-----------------+
      |
      v
D3 real TorrServer+OMP media match -> P4 signed receiver -> existing OMP/G2
[only at delivery stage; NEVER use local-only source key as TV identity]
```

## Composed source details

- Integration branch is a two-parent source-preserving Git composition of
  upstream D2.5 Draft #130 and P2 API/bridge Draft #133 (which contains #118).
  No second Gemini client, VTT serializer, parser, prompt, model selection,
  directory cache, dispatcher or new TCP/LAN listener was created.
- Existing D2 function `download_one_exact_en(...)` now has an **optional**
  `on_cached_en(path, Asset)` callback, invoked once **only after successful
  quota POST → SRT QA → private cache save**. Existing D2 CLI leaves it unset,
  retaining all existing quota/one-POST/consent behavior.
- `owner_vietsub_pipeline.acquire_and_translate_en_once(...)` registers the
  callback and calls the **existing** P2 `run_local_translation`. Its two
  separate permissions are checked BEFORE provider use: download consent
  via the existing one-time `DOWNLOAD ONE` interaction, and an explicit
  per-session cloud-upload authorization. No approval prompts per 120-cue
  batch. Any P2 error does **not** erase the D2 cache or download attempt
  marker; resume from the already cached EN, not by repeating OpenSubtitles
  GET/POST.
- **Already-downloaded EN** is the expected owner trial path:
  `validate_existing_en` / `translate_existing_en` re-verify the existing
  cached file and invoke P2 directly, **without ANY OpenSubtitles request**.
  The P2 worker owns its own checkpoints, revision semantics and final
  private `vi-final.srt`.
- D3 verified media manifest is NOT a prerequisite for translation-only
  testing. It is required to assert an actual viewer/media binding before
  delivery to OMP, where the existing P2 worker can publish cumulative
  revisions through the existing signed P4 feed (instead of local-only
  `on_revision=None`).

## Owner cached-file CLI (defaults to offline/read-only)

From a local checkout of the **composed source branch**, the owner may run:

```text
python poc/p2-sub-discovery/owner_vietsub_pipeline.py \
  --cache-filename <64-hex-content-addressed-name>.srt \
  --sha256 <64-hex-owner-local-download-content-sha256> \
  --cues <actual-count>
```

This only performs local path/SHA/cue verification and reports
`P2_CACHED_EN_REVALIDATED=PASS`, `OPEN_SUBTITLES_GET_POST=0`,
`GEMINI_API_REQUESTS=0` and `TV_DELIVERY=NOT_RUN`. Keys do not need to be
configured to verify local cache. The baseline real EN provider acquisition
is **HUMAN_REPORTED_PASS** with 1,761 cues; do not download it again just
to start translation.

The flags `--execute-api --authorize-cloud-upload` **both** must be present
before the CLI uses the existing Gemini API/LEAN120 worker and the owner-local
`GEMINI_API_KEY`. This is a distinct, future **authorized provider action**:
it can translate all source windows and incur quota, so do not run merely to
prove the source integration. Provider/model are chosen by the existing local
P2 `translator_profile.json` (configurable; current provisional Gemini
profile). No source text is printed or sent to public GitHub. There is no
P4 network activation in this CLI.

## Acceptance / failure boundaries

**Source-only/MOCK**: test D2 VI_FAST and EN ranking, exactly one POST,
SRT QA, callback, fake Gemini two LEAN120 windows, original source timestamps,
per-job checkpoint reuse, local read-only revalidation, no second POST or
provider call, cancel/VI precedence/SDH denial/source tamper, cloud gate,
and fail-closed provider uncertainty. Both D2 and P2 CI suites must PASS at
the same combined SHA, not separately cited as composed proof.

**Real evidence:** Human has already reported one EN provider acquisition
and private cache PASS. This is **not** Gemini live translation, TorrServer
video synchronization, verified real OMP media binding, signed P4 delivery or
Redmi on-screen E2E PASS. Do not merge this Draft to main without required
review and the independent evidence gates of the applicable source and TV
lanes. There is no provider upload, network/TV/ADB change or background work
created merely by committing or reviewing this source.
