# P2-AISUB.2g — Brain36 context/readability guard (SOURCE-ONLY)

Status: **source-only candidate; not a production subtitle quality certificate**.

## Why

Brain reviewed all 36 original synthetic English→Vietnamese translations in Issue #79, using
the original corpus SHA256 `9b1e787c79af7866a81921f57e55f9aa4332e5b316fd122d539dbcff185459ca`.
Human Batch1 (12 manual subjective ratings) remains separate. Brain found 11
high-priority examples (#2, #5, #7, #8, #17, #20, #23, #26, #27, #28, #33).
Many problems involve insufficient recipient relationships, status and
historical titles, which code cannot infer safely from a single line.

This is a deterministic **review-flag** helper. It cannot rewrite a translation,
deduce a character's gender, read a movie or certify semantics. There is no new
provider call, data upload, Windows service, TorrServer, OMP or TV action.

## Input / use

Run only on a trusted checkout of this repository. Generate the Brain36 export
locally from the previously accepted three batch imports. Use the **same pinned**
`benchmark_synthetic.json`; don't edit corpus bytes or create fake translations.

```powershell
python poc/p2-aisub/brain36_context_gate.py `
  --corpus poc/p2-aisub/benchmark_synthetic.json `
  --input "$env:LOCALAPPDATA\TorrentTVVietsub\Benchmark36\brain36-export-20261108-134358-646152.json" `
  --out "$env:LOCALAPPDATA\TorrentTVVietsub\Benchmark36\brain36-context-audit.json"
```

The output path must not already exist. Re-run under a new filename. The input
stays untouched; report includes only case IDs, genres, non-semantic numeric
metrics and REVIEW flag names, never source lines, translations, user scores,
provider receipt, paths, tokens or account information.

## Checks and boundaries

- SHA256 of **raw corpus bytes** must equal `corpus_sha256` of export.
- The report pins both `input_export_file_sha256` (exact input bytes) and
  `input_export_canonical_sha256` (normalized JSON content); changing the
  Vietnamese text changes the latter. Reports are never allowed to overwrite.
- CPS is compared at unrounded precision; the printed two-decimal CPS is for
  presentation only and cannot suppress a threshold warning.
- The input must contain exactly 36 ordered IDs and valid strings, label A.
- Hypothetical speed assumes **2.5 seconds** per isolated sentence. 17 CPS,
  42 characters per line, max 2 lines are **heuristics**, not real timecode
  or film-voice evidence. Actual P2/P4 acceptance requires timed SRT/VTT.
- Context-sensitive `risk_focus` requires `CHARACTER_CONTEXT_REVIEW` when
  recipient metadata isn't explicit. An unfamiliar pronoun is a **warning**,
  not automatically a mistranslation.
- `TITLE_ASSUMPTION_REVIEW` and `PEJORATIVE_REGISTER_REVIEW` flag potentially
  unjustified gender/status/title/hostile wording. They do **not** prove
  hallucination, and may include false positives.
- The gate never changes `benchmark36.py` Human score contract or fills
  a single rubric value. No Human score is fabricated.
- `semantic_quality_certified=False`, `real_timecodes_verified=False`
  are hard invariants even when there are zero flags.

## Recommended repair ordering

1. Brain's 11-case **proposed** rewrites remain in private chat artifacts,
   not committed as default translations; original experimental responses
   are preserved unchanged for v1 comparability.
2. Clarify character metadata for #2, #7, #8, #26, #27, #28 before accepting
   a register/pronoun/title change. Other high-priority candidates can be
   compared editorially but are not silently promoted.
3. Get an **independent bilingual reviewer** for semantic disputes; running
   this deterministic gate is not a second independent AI semantic reviewer.
4. Test speed against *real cue durations* and voice cadence before any OMP
   release or real playback acceptance. If context is insufficient, output
   `REVIEW_REQUIRED` and propose a safe alternative without guessing.

## Verification

```powershell
python -m unittest discover -s poc/p2-aisub -p "test_brain36_context_gate.py" -v
```

Keep GitHub issue updates to summary counts and source/CI commit refs; do not
post the local Vietnamese candidate JSON or private Human ratings.
