# P2-AISUB Context Engine v2a — source-bound, offline, no inferred casting

**Status:** Original synthetic engineering fixture and context-plan contract only. This is **NOT** actual long-film memory, automatic speaker diarization, Gemini/Antigravity backend, subtitle renderer, audio analysis, or OMP/Redmi acceptance.

## Why this exists

The 36 independent context benchmark v1 (Issue #67, PR #68) achieved 36/36 JSON **IMPORT** PASS after three attended Gemini CLI calls. Assistant's editorial comparison flagged pronoun and character-role ambiguity (#3/#8/#19/#21/#28/#33), added meaning, and overlong subtitles. **All five 1–5 Human rating fields and hallucination decisions remain unscored** across the 36 examples. The existing `benchmark_synthetic.json`, `benchmark36.py`, all historical outputs, and score protocols are intentionally unchanged.

v2a takes a smaller, testable step: an explicit human-authored **one-source** context manifest, source SHA256 pin, ordered nonoverlapping scene/cue mapping, directed `speaker -> addressee` address rules and original SRT/VTT timestamps. Instead of assuming that a character is male/female, older/younger or a noble from an English sentence, **unknown values remain `null`** and are reported for human review. v2a does not perform inference or any mutation of the actual translation.

## File boundaries

- `cue_pipeline.py`: canonical UTF-8 SRT/VTT parser, exact cue identity/order and original milliseconds.
- `subtitle_quality.py`: existing 17 CPS / 42 CPL / 2-line readability *heuristics*; no semantic PASS.
- `context_engine_v2.py`: local manifest validator, JSON context-packager and read-only translation-map inspection; **no network subprocess, API key, model invocation, transcript upload or file rewrite**.
- `fixtures/context_v2_synthetic.json`: authored `Linh`/`Minh` test-only fictional context bound to SHA256 of `fixtures/agy_scene12_en.srt`, split into two synthetic scene segments. Alternating speaker turns and direct `em -> anh`, `anh -> em` rules come from the *existing authored fixture's synopsis*, **not detected from audio** or learned about real individuals.
- `test_context_engine_v2.py`: deterministic positive/negative tests, SRT/VTT/timestamps, 12/13 cue boundaries, missing cast or relations, SHA drift, CP437, no overwrite, no secret/text stdout.

### Windows Git checkout SHA-256 compatibility (Issue #71)

Windows `git checkout` may have previously materialized the original `.srt` fixture as CRLF while GitHub stores LF. The v2a implementation originally hashed those **raw checkout bytes**, causing a false `CONTEXT_SOURCE_SHA256_MISMATCH` even though the parsed cue text, IDs and timestamps were identical. CI on LF fixtures did not reproduce Windows's line-ending conversion.

The repair keeps `source_sha256` as an **integrity gate on the original source**: checksum only canonicalizes **CRLF → LF** before calculating SHA-256, matching the behavior of the SRT/VTT cue parser; all other bytes (including UTF-8 BOM, dialogue, punctuation and timecodes) remain significant. Unsupported bare CR is refused. `.gitattributes` pins original SRT/VTT fixture checkouts to LF for future clones, but runtime validation also supports older already-checked-out CRLF files. There is **no manifest manual edit and no bypass of SHA validation**. This hash is a canonical *text-content* identity, not a claim that raw on-disk bytes are equal.

After obtaining the new merged main, **rerun exactly the original `prepare` command** with a *new* `$plan` filename. Expect `CONTEXT_V2A_PLAN_PREPARED scenes=2 cues=12 no_model_call`. No Antigravity, provider quota, TV access or subtitle modification is needed. GitHub synthetic Windows-CRLF regression PASS is not itself proof of execution on the Human laptop; keep the local rerun evidence separate.

### Scope/authority model

The manifest is exact strict JSON with `schema, provenance, source_sha256, characters, address_rules, scenes`. The PoC `prepare` action deliberately supports **only `original_synthetic`** and requires `PREPARE_ORIGINAL_SYNTHETIC_CONTEXT_V2`. It never prepares real captions for upload.

Each scene defines consecutive `cue_start .. cue_end` and an explicit `turns` row for **every** source cue. Invalid cast references, duplicate-directed address rules, overlapping/gapped scenes, source SHA drift, changed IDs or bad UTF-8 fail closed. For unknown speaker or unknown addressee, or absent `speaker/addressee` rule, a plan records `SPEAKER_OR_ADDRESSEE_UNKNOWN` or `UNCONFIRMED_PRONOUN_PAIR` instead of fabricating pronouns.

The isolated scene planner provides target cues in chunks up to 12, `read_only_before` and `read_only_after` cues **from the same scene only**. A cue is never a target twice; neighboring examples from another scene are not silently imported. An authored rule in another scene is available only when the same characters and source manifest are explicitly referenced. For any production future `human_supplied_local` manifest, address rules must be `human_reviewed`, but the v2a command doesn't permit production `prepare`.

Source text and context appear **only in the newly written local plan**. Standard output contains an ASCII status line or numeric/ID-only QA JSON. Avoid sharing private plan files or real subtitle files outside a separately authorized rights/privacy gate.

### Test locally — no AI tokens consumed

In a pinned checkout on current `main` after merge:

```powershell
$engine = "poc/p2-aisub/context_engine_v2.py"
$source = "poc/p2-aisub/fixtures/agy_scene12_en.srt"
$context = "poc/p2-aisub/fixtures/context_v2_synthetic.json"
$plan = Join-Path $env:TEMP ("context-v2a-" + (Get-Date -Format "yyyyMMddHHmmssfff") + ".json")

python $engine prepare `
    --input $source `
    --context $context `
    --out $plan `
    --confirm PREPARE_ORIGINAL_SYNTHETIC_CONTEXT_V2
```

Expected: `CONTEXT_V2A_PLAN_PREPARED scenes=2 cues=12 no_model_call`. Inspect the plan **locally**; cue 1 speaker Linh → Minh has `em/anh` with `fixture_authored` evidence; cue 2 Minh → Linh has `anh/em`. Each cue's real 2500ms duration gives a target **42-character heuristic budget**, not 42 characters guaranteed to preserve meaning. Do not send the plan to a provider automatically.

For a **local, manually prepared** UTF-8 mapping file (simple `{"1":"...", "2":"...", ..., "12":"..."}`) use:

```powershell
python $engine inspect `
    --input $source `
    --context $context `
    --translations $localTranslationMap
```

The command verifies exact IDs, UTF-8 and no known CP437 mojibake, runs existing readability QA against the **actual** start/end milliseconds, and emits only a numeric/ID report with `context_warnings` and `quality_certified=false`. No output SRT/VTT is written, no dialogue is printed, and no human score is inferred.

**Important:** Previous `agy-recovered-*.srt` or `agy_scene12_reviewed_vi.srt` files are **SRT**, not `translations` **JSON maps**; do not pass them to `--translations`. Use a separate, local explicitly mapped JSON file if testing the optional inspect command. Existing `benchmark36` artifacts also have a separate schema and are not implicitly accepted as v2a translation maps.

## Acceptance boundaries

- **Source-only:** Can prepare an authored, source-pinned context plan for synthetic SRT/VTT and detect missing metadata and readability warnings. CI tests are not evidence of genuine long-film identity memory, real media/AI translation accuracy or shadow runtime state.
- **No semantic PASS:** Human still needs to examine source/target intent, referents, title, role, tone, pronoun consistency and reduced wording for *each* cue.
- **Next versioned scope:** Character/alias extraction with **confirmed** identity events; explicit recipient/relationship state transitions and narrator/off-screen dialogue; cue scene assignment after actual speaker-diarization; real-time cue durations; controlled compression proposals with human approval; per-character trust provenance and source/session isolation. No automatic provider/TV/host action until separate consent and appropriate rights/CI/Redmi gates.
