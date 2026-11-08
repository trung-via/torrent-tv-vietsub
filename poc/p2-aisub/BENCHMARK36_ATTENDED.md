# P2-AISUB.2d — 36 *independent* contextual subtitle benchmarks (offline source)

**Source data:** `benchmark_synthetic.json` (36 original, fictional, individually contextualized **single-dialogue situations**, **NOT 36 movie scenes** and **NOT a full-film memory test**). Every case has ID, genre, independently applicable short scene context, speaker and translation-risk category. Six cases each in action, romance, comedy, mystery, historical and family. Benchmark corpus is SHA-256 pinned in prompt, output, ratings and review summary so attempts cannot be silently mixed.

**Authority and side effects:** This source **NEVER calls** `agy`, Gemini API or any other provider. It does **not** create an automatic Antigravity/Google Pro backend for OMP; it **does not** read real film subtitles, send licensed media or use API keys. An authorized Human may run **ONE** manual `agy -p` command per chosen batch. That costs Antigravity quota and might expose these **original synthetic-only** texts to the provider under its own data policies. No cloud calls occur merely by preparing a prompt, importing a user-saved JSON receipt, or scoring.

## How the 36 are split

| batch | ID range | Genres (6 examples per genre) |
|---|---|---|
| 1 | 1–12 | Action, Romance |
| 2 | 13–24 | Comedy, Mystery |
| 3 | 25–36 | Historical, Family |

**Crucial design rule:** these are unrelated mini-situations. A battle captain, a former partner, a queen, and a parent are not the same characters or a connected film universe. The prompt expressly isolates their `scene_context` and speaker. No invented plot, names, real film clips, timestamps, or "correct" human translations have been supplied.

## One attended batch on Windows PowerShell

Run inside a current pinned checkout **after this PR is merged**. The following does not assume your existing `$result` / `$recovered` variables (those belong to the earlier 12-cue test). It creates **exclusive** new files under local user data. Repeat manually for batch 2 and then batch 3 using fresh `$tag`; **never make an automatic `agy` loop or register this as an OMP backend**.

```powershell
$ErrorActionPreference = "Stop"
$tool = "poc/p2-aisub/benchmark36.py"
$dir = Join-Path $env:LOCALAPPDATA "TorrentTVVietsub\Benchmark36"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$batch = 1
$tag = Get-Date -Format "yyyyMMdd-HHmmss"
$prompt = Join-Path $dir "$tag-b$batch-prompt.txt"
$receipt = Join-Path $dir "$tag-b$batch-receipt.json"
$translation = Join-Path $dir "$tag-b$batch-translation-A.json"
$scores = Join-Path $dir "$tag-b$batch-ratings-A.json"
$report = Join-Path $dir "$tag-b$batch-report-A.json"

# Step 1: prepare original synthetic 12-case prompt. Does not call model.
python $tool prepare --batch $batch --prompt-out $prompt
if ($LASTEXITCODE -ne 0) { throw "BENCHMARK_PREPARE_FAILED" }

# Step 2: optional HUMAN-ATTENDED model invocation. This consumes quota.
# Prevent known Windows PowerShell native UTF-8 -> CP437 misdecoding.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
$text = Get-Content -LiteralPath $prompt -Raw -Encoding UTF8
agy -p $text --model gemini-3.8-flash-medium --output-format json |
    Set-Content -LiteralPath $receipt -Encoding UTF8
if ($LASTEXITCODE -ne 0) { throw "BENCHMARK_AGY_FAILED" }

# Step 3: OFFLINE exact-ID/import contract; saves translated text LOCALLY only.
python $tool ingest --batch $batch --blind-label A `
    --agy-json $receipt --out $translation `
    --confirm MANUAL_SYNTHETIC_BENCHMARK_36
if ($LASTEXITCODE -ne 0) { throw "BENCHMARK_IMPORT_FAILED" }

# Step 4: OFFLINE blank score sheet, not automatic quality judgement.
python $tool template --batch $batch --blind-label A --out $scores
```

The accepted `translation` artifact is local JSON holding source-case IDs and Vietnamese answers. Do **not** post it, provider `conversation_id`, a real movie file or personal paths to public GitHub issues.

If a receipt contains CP437 mojibake *despite UTF-8 session configuration*, plain ingest refuses it with `BENCHMARK_CP437_MOJIBAKE_DETECTED`. It can be recovered only from the **saved same synthetic receipt** with **a distinct new output path** and explicit `--repair-cp437 --confirm RECOVER_CP437_SYNTHETIC_BENCHMARK_36`. Reversible CP437 decode errors and already-clean receipts fail closed. The repair action itself uses no extra AI tokens.

## Human blinded/masked scoring protocol

Before scoring, a separate reviewer should open the source `benchmark_synthetic.json` and local `translation` file to compare context/speaker/risk against the Vietnamese rendering, **without being told which provider/model corresponds to label A**. The CLI cannot verify actual blindness or reviewer expertise.

Open only your local `ratings-A.json`. For **every ID**, replace `null` with the following independently chosen values:

- `semantic_accuracy`: 1–5 (retains actual meaning, no omitted essential detail).
- `vietnamese_naturalness`: 1–5 (feels like natural on-screen Vietnamese, no awkward literalism).
- `relationship_pronouns`: 1–5 (correct `anh/em`, rank, age, family, deference **given only scene context**).
- `tone_register`: 1–5 (sarcasm, subtext, humor, historical/formal speech, empathy).
- `subtitle_readability`: 1–5 (concise without sacrificing meaning; **hypothetical** 2.5s screen limit, not a real timed movie cue).
- `hallucination`: `true` or `false` (any invented significant fact, character relationship, or meaning).

Interpret 1=seriously wrong, 2=weak, 3=usable but needs edit, 4=good, 5=excellent. Each 1–5 is a **human subjective judgment**, not automatic technical verification. Don't populate scores from the model itself; an independent reviewer is ideal. The `blind_label` is a local masking convention, **not proof of a blinded A/B trial**.

Once all twelve cases of a batch have been genuinely reviewed:

```powershell
python $tool score --translations $translation --ratings $scores --report-out $report
```

An incomplete ratings sheet **fails**, it does not silently pass. A successful score command produces `BENCHMARK36_HUMAN_SCORE_RECORDED ... quality_certified=False` and a local report **without dialogue text**. No score means no model-quality result.

After all **three** batches have real Human-filled score sheets and corresponding local review reports:

```powershell
# Replace paths with the actual existing THREE completed report files.
python $tool aggregate --reports $report1 $report2 $report3 --out $combinedReport
```

The aggregate refuses missing/duplicate batches, mismatched corpus SHA, conflicting masked labels, altered case IDs, invalid ratings or tampered score statistics. Its output contains global/genre averages and hallucination counts, but still marks `quality_certified=false`. A result that clears all format and readability gates does **not** automatically prove semantic translation accuracy, actual user satisfaction, TV display, subtitle sync, cloud model entitlement, or movie-subtitle rights.

## Acceptance / outstanding stages

- **SOURCE/CI:** 36 original single-dialogue cases, deterministic SHA-pinned 3×12 preparation, strict single-turn CLI receipt QA and CP437 protection, fully blank human scoring sheets, complete-rating enforcement, genre-level and aggregate metrics.
- **HUMAN ATTENDED:** actual model calls, corresponding token/time observations and local translations for 3 batches — **not executed by this PR**.
- **HUMAN SEMANTIC:** ratings and model comparisons — **not executed by this PR**.
- **P2-AISUB/OMP:** authorized real movie sources, optional external subtitle/ASR, official Gemini API (if approved), full-film persistent character memory and Redmi G1/P4 integration — **not executed**.

This PoC may be removed or replaced with a supported provider API later without a change to the existing OMP player or timing/sidecar contract.
