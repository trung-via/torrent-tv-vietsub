# P2-AISUB.2b — Attended Antigravity 12-cue synthetic benchmark

**Purpose:** Human-confirmed proof of Antigravity CLI `agy -p ... --model gemini-3.8-flash-medium --output-format json` from Windows. This experiment is a **manual CLI session**, **not** a supported automation API for OMP/Torrent TV and **not** a substitute for Gemini Developer API. No script here invokes `agy`, calls a provider, consumes quota, downloads media or modifies TV/TorrServer. A CI pass proves only offline parsing logic, never a new model run.

## How to run (PowerShell, inside a fresh checked-out Torrent TV repository)

```powershell
# Run from the checked-out repository ROOT with Python available.
# This PoC handles only its 12 original synthetic SRT cues.
$script = "poc/p2-aisub/agy_handoff.py"
$dir = Join-Path $env:LOCALAPPDATA "TorrentTVVietsub\AgyManual12"
New-Item -ItemType Directory -Path $dir -Force | Out-Null

# Unique paths: prepare/ingest fail if any output file already exists.
$tag = Get-Date -Format "yyyyMMdd-HHmmss"
$promptFile = Join-Path $dir "$tag-prompt.txt"
$receiptFile = Join-Path $dir "$tag-agy-receipt.json"
$subtitleFile = Join-Path $dir "$tag-vi.srt"

# 1. OFFLINE: create a 12-cue synthetic prompt; no AI call.
python $script prepare --prompt-out $promptFile

# 2. HUMAN RUNS AGY DIRECTLY, ONCE: this WILL consume Antigravity quota.
# No Gemini API key; no background script calls agy; no real film text.
$promptText = Get-Content -LiteralPath $promptFile -Raw -Encoding UTF8
agy -p $promptText --model gemini-3.8-flash-medium --output-format json |
  Set-Content -LiteralPath $receiptFile -Encoding UTF8

# 3. OFFLINE: validate exact 12 IDs and create an SRT in this local folder.
# Stops (no new SRT) on status != SUCCESS, duplicate/missing IDs,
# invalid UTF-8, markup, JSON errors or incomplete translation.
python $script ingest --agy-json $receiptFile --output $subtitleFile `
  --confirm MANUAL_SYNTHETIC_12_CUE
```

Expected final marker: `AGY_SYNTHETIC_12_CUE_IMPORT_PASS no_provider_call_by_script`. The output is a NEW locally stored SRT using the original cue start/end times and no real film audio or subtitle. Keep `*-agy-receipt.json` and `*-vi.srt` **private**; do not commit/upload them to GitHub. Never share Antigravity `conversation_id` or full subtitle text in a public issue. Share only command result marker, model alias, duration, and token counters if useful.

### Import envelope examples

Actual Human first smoke (2 cues, 2026-11-08) observed an outer CLI `status:"SUCCESS"`, `num_turns:1`, and a `response` string with numeric-string keys. This importer supports both:
- `response` of `{"1":"...","2":"...", ...,"12":"..."}` as an *escaped string field* in the outer CLI JSON; and
- `response` of `{"translations":[{"id":1,"vi":"..."},...,{"id":12,"vi":"..."}]}` as an escaped string field.

For safety it rejects anything else, including markdown fences, extra keys, missing cues, any skipped ID, incorrect order, multiple turns, failed responses and writes to an existing output. An outer `SUCCESS` alone is never a product PASS.

### Acceptance and next branch

- [x] Original synthetic 12-line scene (Linh/Minh, former lovers, train station) kept inside repo; no copyrighted dialogue or real audio.
- [ ] Offline contract/unittest suite green at PR HEAD; preserve existing P2-AISUB.1 QA and P2-AISUB.2a behavior.
- [ ] Actual Human-run 12-line Antigravity session logged as separate `HUMAN_REPORTED_CLI_12_PASS` *after* user returns its validated marker and redacted metrics.
- [ ] Real bilingual quality review (context/pronouns/nuance) still unverified; count/timing tests cannot score translation quality.
- [ ] A separate Gemini Developer API integration for automatic in-app translation requires API quotas, approved privacy/rights, user confirmation and a separate PR. Google AI Pro/Antigravity quota is not a general purpose OMP backend entitlement.

**No release, Windows runner dispatch, app install, host changes or automatic Antigravity wrapper.**
