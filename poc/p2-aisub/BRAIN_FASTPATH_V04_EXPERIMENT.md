# P2-AISUB — Brain FastPath v0.4 experimental research harness (R1/R2)

**Human-authorized scope:** investigate and test ways to make **ChatGPT Brain** translate subtitles faster before any Gemini challenger. Brain is PRIMARY. v0.3.5 FAST120 remains the production/default translation procedure until real quality-adjusted repeated measurements support a change. This is an **offline prompt planner + timing/structure recorder**, not a model client, not a faster Brain model and not a claim that 3–5-minute whole-film translation has been achieved.

Tracked at [Issue #109](https://github.com/trung-via/torrent-tv-vietsub/issues/109). Follow the installed skill `torrent-tv-brain-subtitle-translation v0.3.5` for real translation, glossary, deterministic SRT ingest/assemble, semantic audit and patch ledger. The harness uses `cue_pipeline.parse_cues` **only for synthetic/offline experimental planning/QA**; it does not replace the skill's VTT metadata-aware implementation. Initial v0.4 trial is **SRT ONLY** and restricts each trial to three or more non-overlapping 160-original-ID windows, respecting the canonical repo parser's existing 2,000-cue/1-MB maximum. It does not read the historical unavailable EN Thor source or modify the existing complete VI output.

## Candidate profiles

- `BASE120`: v0.3.5-aligned **FAST120** control, <=120 target cues per chunk, <=6,500 source characters, neighbor context ±4, original IDs.
- `LEAN120`: same 120/6,500/±4 boundaries and same exact global translation rules; shorten redundant **per-chunk** header text only. This is a candidate for lower prompt overhead, not proven faster.
- `ADAPTIVE`: same exact global translation rules; limit dense/risky source regions to 72 or 100 cues/context ±8, allow low-risk up to 160/context ±4 and prefer boundaries at a >=4-second gap after >=60 cues. Risk signals are purely heuristic: question, source negation, pronouns, dual-speaker dash and high source CPS. No cues are modified/re-timed or semantically classified.

The **same exact** `GLOBAL_INSTRUCTIONS.txt` SHA (and an optional privately supplied glossary SHA) is pinned for all arms. In a Brain session, present global instructions **once per trial/session**, then translate each private prompt chunk in order. All outputs must be original `ID|Vietnamese text` without explanations/timecodes and with literal `\n` for intended line two. Context cues are READ-ONLY. The `BASE120` layout is aligned with the v0.3.5 protocol, **not a byte-for-byte replay of the original ChatGPT conversation or a proof the model used precisely the same hidden configuration**. Measure actual prompt/translation time, do not assume the shorter header improves performance.

## Use, private, authorized material only

Run from repo checkout or copy the Python script alongside the repo's `cue_pipeline.py`. **Choose a fresh private workdir OUTSIDE the public GitHub repo** (do not run in any GitHub-hosted Actions with private media). Example commands use placeholders, not real user paths:

```powershell
python poc/p2-aisub/brain_fastpath_v04_experiment.py plan --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --ranges 1-160,561-720,1081-1240 --glossary PRIVATE_GLOSSARY.txt
python poc/p2-aisub/brain_fastpath_v04_experiment.py start --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage translation --event begin
# Human interacts with ChatGPT Brain to actually translate private prompt_01.txt, ...
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage translation --event end
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage ingest --event begin
# Save freshly generated, complete ordered 160 cue ID|VI translation to PRIVATE_W01_BASE120.tsv
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage ingest --event end
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage qa --event begin
# Real deterministic QA + context-based Brain self-review; preserve original/source IDs and timestamps
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage qa --event end
# If zero corrections: mark explicitly; otherwise time repair begin/end around real fixes
python poc/p2-aisub/brain_fastpath_v04_experiment.py phase --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --stage repair --event skip
python poc/p2-aisub/brain_fastpath_v04_experiment.py finish --source PRIVATE_ORIGINAL.en.srt --workdir PRIVATE_BRAIN_V04_STUDY --trial W01-BASE120 --translations PRIVATE_W01_BASE120.tsv --repairs 0
python poc/p2-aisub/brain_fastpath_v04_experiment.py summary --workdir PRIVATE_BRAIN_V04_STUDY
```

Use all 9 trial arms across 3 windows with rotated order, fresh translation output in each trial; never copy Brain's output from another arm, an old Thor translation or a Gemini output to fill an unfinished trial. The private prompt files contain source subtitle text and must never be committed/published. The manifest and CLI summaries contain only source SHA, glossary SHA, numeric cue ranges, mode and timing metadata, not real source lines, filenames or paths. All user source, glossary and output remain private.

## Measurement / honesty boundaries

- `start` and `phase begin/end` use **local monotonic clock**; if executed across distinct hosts or reboots, do not claim a valid consistent wall interval. Total wall from `start` through `finish` includes unattributed tool/chat/human idle time, separately labeled. Timed stages: translation, ingest, QA and repair; repair may be explicitly skipped only if none occurred. It intentionally cannot measure internal ChatGPT inference tokens/sec, actual prompt-cache utilization, host GPU utilization, or automatically attest a fresh model response.
- `finish` requires exactly 160 ordered target `ID|VI` rows, no blank/missing/extra IDs, max 2 visual lines, exact source markup and two-speaker boundary preservation. It records translated-file SHA and raw readability flags, **NOT** a bilingual semantic accuracy score. A structural check is not a validated 1,761-cue whole-film completion.
- `summary` **never chooses a winner or changes Brain default**, even after 9/9 trials: independent bilingual review (>=30 high-risk original IDs distributed through beginning/middle/end), repeated true elapsed comparisons and quality-noninferiority require separate evaluation. A timer that a person starts/stops is not a cryptographic attestation of new model generation.
- The existing v0.3.5 Brain historical Thor full film `743.8s`, exploratory v0.3.4 3×3 time differences (~0.56% between FAST120/EXP160), and Gemini's R2 partially cached `793.44s` remain **historical different-scoped data**, not v0.4 results.
- Targeted speed improvement gate: repeatable >=20% improvement in **full translation + QA + repairs wall** with independent semantic non-inferiority; otherwise keep current Brain FAST120. Do not treat prompt length, batch count, simulated duration, synthetic test seconds or error-free CI as proven Brain speed improvements.
- No external model calls, paid API, automated UI relays/WakeHub, TV/ADB/TorrServer mutation, G4 signing, legacy R3.1/90-cue checkpoint import or real protected subtitle fixture is performed by this PR.

## Source/CI acceptance vs actual Brain translation

`python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -v` should run local synthetic deterministic tests on repo Ubuntu CI. Unit tests cover 1,761 synthetic cues, 9 trial plans, 120/160 target coverage, adaptive risk windows, source/glossary/global prompt SHA, private output, prompt tampering, partial TSV refusal, stage monotonic and phase order, and fail-closed semantic/TV status. **Only model generation in ChatGPT with authorized actual SRT can create genuine Brain FastPath speed evidence.** This experiment remains *opt-in* and is not promoted into installed plugin version v0.3.5 by a source-only merge.
