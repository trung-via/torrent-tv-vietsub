# P2 Subtitle source fallback: VI-first → EN → AI Vietsub

**Status:** DRAFT. Depends on D1 #122 and D2 #124; this slice tracked in #125 and Draft PR #126. No production TV, real EN download or model API proof.

## Decision and routing

Human decision, 2026-11-13: **Before D3/OMP media delivery, finish the source fallback path.**

1. Inspect authorized selected film identity, trustworthy title/IMDb metadata and verified actual movie hash if available. A manually typed release name is not a movie hash or verified sync proof.
2. Search **VI** first, bounded to 2 OpenSubtitles pages, and combine all candidates *before* making the release decision. If a single unambiguous confident match survives D1, route `VI_READY`.
3. If no confidently matched VI, search **EN** with the same bounded search/cross-page aggregation. If a single confident EN match survives D1, route `EN_TRANSLATE`.
4. If either search is incomplete, or only ambiguously matched subtitles exist, set `REVIEW_REQUIRED`. If nothing rankable exists, set `NO_MATCH`. Never silently promote an unrelated VI/EN subtitle, never claim source metadata proves actual media synchronization.
5. `VI_READY` means approved route toward **one owner-authorized VI download** and SRT QA. `EN_TRANSLATE` means approved route toward **one owner-authorized EN download** and SRT QA, then a **separately approved** AI translation session.

## EN downloading

`OpenSubtitles.download_manual_en` (on Draft #126) requires explicit `authorized=True`, exact media/discovery binding, the confident EN winner's file ID, and a one-POST latch shared with manual VI. It asks OpenSubtitles for `sub_format=srt`, validates UTF-8/cues/timestamps and returns EN `Asset`. It does **not** send text to an AI or cache without a calling owner-approved workflow.

All download and translation costs require separate deliberate approvals. A provider POST may consume download quota even if output fails QA.

## EN → VI timed subtitle translation

`timed_translation.translate_en_to_vi` accepts only a verified **English SRT Asset**. All three conditions must be true before invoking any translator callback: legal source translation rights; approval to send subtitle dialogue to the specific provider; consent to provider quota/cost.

An injectable `Translator` callback receives immutable `Batch` objects, each with:
- max 120 target cues, max 6,500 source characters;
- 4 read-only cues before/after, when available;
- exact original cue IDs/timecodes preserved by the local assembler;
- exact target ID coverage required for every result, no missing or extra IDs;
- optional stable 8–20 term glossary and speaker→addressee guidance to be provided by the selected model adapter, grounded in source context.

The local output is a VI UTF-8 SRT, preserving source ID/timestamp strings byte-for-byte after normalization, plus SHA256, cue count and `STRUCTURAL_PASS_SEMANTIC_UNVERIFIED`. Deterministic QA does **not** certify Vietnamese accuracy, pronouns, humor, or actual video synchronization.

A production AI adapter is **not yet connected**: the user requested an API pathway, but provider/model/endpoint, provider key, cost ceiling, data retention terms, legal content scope and external transmission authorization have not been configured. Legacy LEAN120 Brain workflow remains a separate chat-based option; do not confuse it with a paid/automated API. No model network call occurs in Draft #126 or CI.

## Exit gates before moving to D3

- [x] VI → EN fallback contract and offline tests, including pagination and ambiguity.
- [x] EN manual single POST method and offline mock tests.
- [x] 120-cue translation handoff + structural QA and offline mock tests.
- [ ] Choose and wire a provider-specific model adapter and local credential/cost guard, without leaking subtitle dialogue to PUBLIC GitHub.
- [ ] A separate owner-authorized real matched-EN download (not needed merely to prove existing VI source download).
- [ ] A permitted real model translation of a bounded lawful EN fixture, preserving cue IDs/timestamps, glossary context, with semantic QA.
- [ ] D3 real TorrServer media binding + Windows/NAS → OMP subtitle delivery, and P1 G1 auto-render-after-reopen repair on real Redmi.

Do not infer any of the unchecked gates from CI PASS. No AIOS dependency, TV installation, public media path, or extra OpenSubtitles quota action in this branch.

## Local VI/EN owner workflow (added after initial draft)

Run `owner_vi_en_trial.py --imdb-id <verified-title-id>` only in the owner's
local, explicitly authorized shell with temporary `OPENSUBTITLES_API_KEY`.
It performs read-only VI-first search and EN fallback, prints the chosen release
hint privately, and prompts for the literal `DOWNLOAD ONE` before one quota
POST. The selected EN or VI SRT is cached privately and structurally validated.
An EN result reports `NEXT_GATE=EN_TRANSLATION_PROVIDER_AUTHORIZATION`,
`AI_TEXT_UPLOADED=NO`, and never invokes any translation model. A local
release filename is not an actual TorrServer media binding.

`translation_api_contract.py` provides the provider-agnostic LEAN120 system
rules, untrusted EN subtitle source wrapper, stable glossary input and strict
`ID|VI` response parser. A concrete API client must place the system rules
separately from source data, handle its own auth/budget/timeouts/retries safely,
and pass validated per-batch mappings to `timed_translation.py`.
Neither module opens network connections. No translator-provider choice or
subtitle-upload authority is presumed by these files. Real semantic accuracy
must be independently reviewed after structural QA.
