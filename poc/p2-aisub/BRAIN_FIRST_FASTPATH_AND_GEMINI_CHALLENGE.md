# P2-AISUB — BRAIN FIRST / Gemini FastPath challenge (2026-11-10)

**HUMAN_DECIDED, supersedes earlier Gemini-first acceptance text in Issues #88/#89 and the label in R3.3:** The default translator is **ChatGPT Brain GPT-6**, via the already installed `torrent-tv-engineering-flow/torrent-tv-brain-subtitle-translation` skill **v0.3.5**. Gemini/Antigravity must first be tested using the **same Brain FastPath method**; it does not become primary just because R3.3 contains a Gemini-specific model label. Reference tracking [#109](https://github.com/trung-via/torrent-tv-vietsub/issues/109).

## What was actually observed (never inflate confidence)

- The original owner-supplied Thor trial: Brain translated 1,761/1,761 SRT cues in a **single interactive ChatGPT session**, with 743.8 s historical wall from start through automated QA. This included 71 cue revisions in that version. This is not unattended API throughput, not a randomized match with Gemini, and not a guaranteed future SLO.
- Owner/Brain subsequently improved Brain FastPath with compact `ID|Vietnamese text`, 120-cue provisional FAST mode, deterministic SRT assembly, resumable checkpoints, and targeted semantic patching. Skill v0.3.5 has cross-cue semantic triage and protected edit ledger.
- Brain-only three same-source window 3×3 exploratory mode trial: 60-cue mode 228.507 s, 120-cue mode 226.239 s, 160-cue mode 224.980 s (sum over three 160-cue windows per mode). The small difference does NOT establish a winner; overall repair time and blinded semantics were not captured. **FAST120 remains provisional**.
- The completed Thor VI SRT is preserved on owner Windows: exact SHA in #89, real 1,761 cue structural validation in #88; on Redmi Debug Font v3 owner reported G1 reopen auto-subtitles and G3 post-seek sync (#96). Those on-TV claims are bounded to those user-tested actions, NOT bilingual semantic certification or a new measured Brain-vs-Gemini result.
- Historical Antigravity R2 793.44 s was a **partially cached** 12-uncached-of-20-batch operation, not a matching full-film FastPath translation. Do not conclude a measured speed ranking from 743.8 s vs 793.44 s or an approximate 13 minutes.

## Single canonical translation method for both engines

Use the installed skill as source of truth: `skills://plugins/torrent-tv-engineering-flow/torrent-tv-brain-subtitle-translation/skill.md` and its `references/prompts.md`, `scripts/subtitle_fastpath.py`, `references/benchmark.md`, `scripts/semantic_audit.py`. Keep all subtitle source, translated lines and private workdirs **outside this PUBLIC GitHub repo**. Neither Gemini nor a self-hosted runner has direct access to the ChatGPT Brain interactive model unless an actual separately approved transport is proved.

1. Prepare **one approved SRT/VTT** with canonical source SHA, real rights/consent and **same** windows, source cue ordinals and read-only context for each engine. For the first matched benchmark use 3 non-overlapping windows of exactly 160 source cues (e.g., 120+40 in FAST120); confirm 1..N original cue IDs, original millisecond timecodes, UTF-8, markup and two-speaker boundaries.
2. Keep **same FAST config** on both: target max 120 cues/chunk, target ~6,500 source characters, ±4 neighbors (read-only context), stable character-specific glossary and whole-story facts only as independently available. Shared deterministic prompt protocol: one target line = `ID|natural Vietnamese`; `\\n` encodes an intentional second visual line. No English echo, timestamps, markdown, wrapper explanations, or extra dialogue. Do NOT move a question/speaker/reply from cue N to N+1 to satisfy format rules.
3. **Brain lane:** ChatGPT Brain GPT-6 translates each target chunk in the conversation; user/authorized local tooling ingests `ID|VI` into its source-pinned FastPath checkpoint. Do not call this a Python/ChatGPT API or an autonomous background worker. Keep original outputs for quality review, edits as separate ledger.
4. **Gemini lane:** only after inspecting actual installed `agy` CLI, model identity and privacy/rights/quota, run Antigravity Gemini 3.8 Flash High using **the same per-chunk prompt, glossary and context**, accepting one final successful `ID|VI` result per exact cue (or strictly parsed equivalent). No guessed CLI flags, no paid API, silent fallback, automatic replay of quota-consuming failures, or sharing the Brain-generated VI as Gemini's allegedly fresh output.
5. Use the **same deterministic** Python ingest/assemble and `semantic_audit.py` plus independent bilingual cue-level rubric on both. Compare original source IDs and context; do not treat 42 CPL and 17 CPS soft warnings as proof of mistranslation. Target ≥30 risk-priority IDs across beginning/middle/end, including pronoun/relationship, omission, negation, joke, question drift and speaker assignment. Brain self-review is not blinded independent QA.

## Fair measurement and default choice

For each matched window and each engine, record actual model/transport, source SHA, cue ID range/hash, glossary hash, FAST configuration, fresh output/checkpoint hash, timestamps, `T_preflight`, `T_translate`, `T_ingest`, `T_QA`, `T_repair`, `T_total` (wall including overhead/idle unless separately measured), errors, missing/duplicate IDs, failed batches, attempts, number of corrected cues and verified semantic findings. Use monotonic elapsed clock *for the process measured*; ChatGPT interactive vs AGY CLI are different transports, so describe limitations, do not compare token/s without real receipts. Each benchmark arm must be a new translation of the same **licensed** source IDs. Rotate run order, repeat if possible, and compare speed **only after equal or non-inferior quality**. Publish **sanitized aggregate metrics only**, no user SRT, names, source paths, prompt content, account identifiers or provider raw logs.

**Decision rule:**
- Brain is **DEFAULT NOW** and remains the default when data is incomplete, Brain is faster or equal, Gemini fails a structure/semantic gate, or evidence is not comparable.
- **Only consider Gemini as a challenger candidate** if real matched total *including repair* shows a repeatable ≥20% improvement **without worse independent semantic findings**. That is a review gate, not automatic traffic migration. User can keep Brain even then.
- Do not spend Gemini quota on a completed movie already valid on Redmi merely because its old R3.1 ZIP expired. Use a separate approved new source or rights-cleared trial; leave existing VI untouched.

## Relationship to merged R3.2/R3.3

- `r3_2_continuous_queue.py` is useful model-neutral *batch scheduling infrastructure* for an actual authorized concurrent provider.
- `r33_new_film_core.py` currently pins `BATCH_SIZE=90` and `MODEL_PIN=ANTIGRAVITY_GEMINI_3_8_FLASH_HIGH`. It is a **legacy Gemini-specific source-only PoC** with generic callbacks, **not a Brain-First policy, not a deployed Gemini adapter, and not a fair comparator to Brain FAST120**. DO NOT update its existing private manifest or saved 90-cue checkpoints in place to 120 or relabel their model provenance. A new isolated workdir/schema and reviewed matching-FastPath adapter are required.
- No raw Cloud model transfer or new Windows/TV/ADB operations are authorized by merging this document. The user explicitly removed G4 signed Release; keep it NOT_PLANNED.

## Acceptance status on 2026-11-10

`BRAIN_FASTPATH_PLUGIN=v0.3.5_PRESENT`; `BRAIN_DEFAULT=HUMAN_DECIDED`; `BRAIN_THOR_HISTORICAL_1761=OBSERVED_SESSION_743.8S`; `REDMI_V3_G1_G3=HUMAN_REPORTED_SCOPED_PASS`; `GEMINI_FASTPATH_IMPLEMENTED=NO`; `MATCHED_BRAIN_VS_GEMINI_REAL_RUN=NOT_RUN`; `SPEED_WINNER=NOT_ESTABLISHED`; `PRODUCTION_MODEL_SWITCH=NO`; `G4=NOT_PLANNED`.
