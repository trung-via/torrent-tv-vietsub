# P2-AISUB.1 — Offline timed-cue preparation and translation QA

**Current feature:** parse/validate UTF-8 SRT or WebVTT, import a *separately prepared* Vietnamese translation map keyed by cue number, preserve every original cue's millisecond start/end, render SRT/VTT, and refuse missing/extra cues and unsafe markup. Two original synthetic fixture examples are in unit tests.

**Not yet implemented:** AI inference/model translation, ASR, voice-over, provider consent/selection, remote media upload, subtitle download, GPU resource measurement, OMP UI integration or on-TV test. These are separate acceptance gates; this step is the deterministic data contract needed before any model-generated Vietsub.

Example: with `source.srt` containing exactly two cues and locally prepared `vi.json`:

```json
{"1":"Xin chào","2":"Hẹn gặp lại"}
```

```powershell
python poc/p2-aisub/cue_pipeline.py --input source.srt --translations vi.json --output output.vi.srt --confirm LOCAL_OFFLINE_ONE_FILE
```

The command rejects an existing destination, refuses writes to the input/translation file, emits only a cue count (no private caption text), and requires explicit one-file confirmation. No network call and no media processing are performed. The output may be imported with the previously accepted G1 SRT/VTT picker, but this PR does **not** claim the output was tested on Redmi TV.

Limits: 1 MB per input/translation JSON, 2000 cues, strict SRT 1..N sequence, WebVTT header required, cue timestamps valid and ordered, no STYLE/REGION/NOTE preservation in this first slice, plain translated text only (no HTML/WebVTT markup). Failing formats must be fixed explicitly rather than silently dropped. It normalizes cue timestamp spelling while preserving millisecond values; VTT cue identifiers and timing settings remain.

**Test:** `python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v`.

**Historical P2-AISUB.1 next step (superseded):** originally proposed a local translator. The latest Human choice is cloud-first (see P2-AISUB.2a below); retain only deterministic local timing/QA, never alter cue timing or fabricate missing subtitles.

## P2-AISUB.2a — Cloud-first request/response contract (2026-11-07)

**Human decision:** Laptop cannot run local AI. Target Gemini Developer API Free Tier on a *separately approved* real-data/provider call, after a privacy/rights and quota check. This first engineering PR is **offline-only**: it creates Gemini `generateContent` JSON request bodies but has **no HTTP client, API key, authentication, cloud upload, billing action or model inference**. It cannot be used to send or download real subtitles by itself.

- `cloud_contract.py` partitions canonical cue IDs into non-overlapping batches (default 12 target cues) with read-only previous/next context. Prompt requests natural Vietnamese, character-relational pronouns and scene consistency. Surrounding captions, glossary and synopsis are labeled **untrusted data**. Only target IDs may be emitted. Output timestamps remain owned by `cue_pipeline.py`, never the model.
- `parse_gemini_response` validates the single completed `STOP` candidate, JSON-only envelope, exact ordered IDs, one-to-one completeness, plain UTF-8 nonempty Vietnamese, no markup/unsafe Unicode and no extraneous fields. Incomplete, refused/blocked, duplicated, or malformed replies fail closed. `finalize_cues` only renders an SRT/VTT once *all* batches and existing QA checks pass; it is an in-memory function with no file-system effect.
- `benchmark_synthetic.json` has **36 original fictional English micro-dialogues** across six film genres (action, romance, comedy, mystery, historical, family). This is a **benchmark protocol/fixture**, not a claim that Gemini, GPT or Claude was executed or that translation quality has been scored. Subsequent approved, double-blind bilingual human scoring must check meaning, Vietnamese naturalness, xưng hô, tone, subtitle readability and hallucinations.
- The production provider implementation must be separate: choose a valid model/endpoint from current official docs; use an explicitly approved API key stored **outside the repo**, live Free Tier project/quota verification, per-request user consent for cloud text transfer, bounded token estimate and per-film budget ceiling, 429/backoff/cancel/restart policies, private content handling and rate limits. Google AI Pro subscription is **not** Gemini API quota. API or model availability is not guaranteed by this mock contract.
- Scope excludes extracting embedded MKV subtitles, OpenSubtitles/SubDL downloads, OCR, ASR, TV APK/ADB or Windows TorrServer changes. Embedded → authorized matching external → ASR remains the staged source waterfall in Issue #60. Full P4 real Redmi export/import is blocked until separate G1/P4 evidence.

### Offline test command

```powershell
python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v
```

No provider secrets, real subtitles, torrents, licensed media downloads or cloud calls appear in the CI tests. A source/test PASS does **not** prove live Gemini Free Tier availability, Vietnamese translation quality, a synced subtitle retrieved from a provider, or real TV playback.
