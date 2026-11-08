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
# Windows PowerShell (especially legacy console) must interpret native
# Antigravity stdout as UTF-8. Session-local, not persistent OS config.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
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

### Windows CP437 mojibake detection and offline one-time recovery

A Human experiment on 2026-11-08 succeeded with the 12-cue import marker and token metrics, but the `Get-Content` output showed characteristic text `kh├┤ng`, `sß║╜`, `─æ`. Exact reversal of the displayed sample proves a UTF-8 → **CP437** misdecode signature, and recovers `không`, `sẽ`, `đ`. This is NOT evidence of bad model translation, and does NOT alone prove whether the saved file was already corrupted or only the terminal display. The prior source validator accepted structurally valid but potentially garbled Unicode.

On a checkout containing this fix, diagnose the existing locally saved 12-cue SRT **without any AI call or file write**:

```powershell
python poc/p2-aisub/agy_handoff.py inspect --srt $subtitleFile
```

- `AGY_SYNTHETIC_SRT_ENCODING_STATUS=CP437_MOJIBAKE_SUSPECTED` means the **saved SRT itself** contains CP437 symptoms. This must no longer count as a quality PASS.
- `AGY_SYNTHETIC_SRT_ENCODING_STATUS=NO_CP437_MOJIBAKE_FOUND` means no known CP437 markers were found in the saved text; any garbled console output may be display-only. Confirm in a UTF-8 aware editor. This does NOT certify the actual Vietnamese translation quality.

If the saved SRT is corrupt **and** the previously captured `agy` receipt still exists, recover deterministically from the receipt without another Antigravity call. Do not use this on clean input or real movie files. The recovery requires an explicit separate confirmation and new output path, refuses mixed/unrecoverable text, and leaves source artifacts untouched:

```powershell
$recovered = Join-Path $dir "$tag-cp437-recovered.vi.srt"
python poc/p2-aisub/agy_handoff.py ingest `
  --agy-json $receiptFile `
  --output $recovered `
  --confirm RECOVER_CP437_SYNTHETIC_12_CUE `
  --repair-cp437

python poc/p2-aisub/agy_handoff.py inspect --srt $recovered
```

Expected recovery marker `AGY_SYNTHETIC_12_CUE_CP437_RECOVERY_PASS` then status `NO_CP437_MOJIBAKE_FOUND`. **If the receipt is clean while the SRT display is weird, the recovery intentionally refuses** with `AGY_CP437_REPAIR_NOT_NEEDED`: diagnose the terminal separately, rather than double-decoding the text.

For future tests, set `[Console]::OutputEncoding` / `$OutputEncoding` to UTF-8 *before* `agy | Set-Content` as shown above. If that environment still emits mojibake, STOP and inspect provider bytes; do not blindly transcode or rerun paid/quota-consuming inference. Never upload CLI receipts to a public repository. The new importer rejects recognizable CP437 mojibake by default with `AGY_CP437_MOJIBAKE_DETECTED`, before any SRT is written.

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


## P2-AISUB.2c — Read-only Vietnamese readability QA (after recovery)

After a successful import or CP437 recovery, run this **offline** command in the checked-out repository (PowerShell variable `$recovered` is the NEW recovered SRT from the previous step):

```powershell
python poc/p2-aisub/subtitle_quality.py --input $recovered --profile adult
```

This prints a single ASCII JSON report with cue IDs, duration, character count, CPS (tenths), and warning codes. **No dialogue, private file path, session ID, credentials or title** is printed or uploaded. The command never edits the original or generated SRT.

Initial defaults are **17 characters/second for adult Vietnamese subtitles; 13 for children; maximum 42 characters per line and 2 lines per cue**. They are reference heuristics from the publicly available [Netflix Vietnamese Timed Text Style Guide](https://partnerhelp.netflixstudios.com/hc/en-us/articles/220447048-Vietnamese-Timed-Text-Style-Guide), not proof of compliance with Netflix or that captions will fit on the user's TV.

The 12-cue Human-reported repaired translation from 2026-11-08 has, by nonbinding hand calculation, four likely adult-speed warnings: **cue 7 (44 chars/2.5s = 17.6 CPS), cue 9 (51/2.5 = 20.4), cue 10 (54/2.5 = 21.6), cue 11 (46/2.5 = 18.4)**. This observation is based on chat-pasted text, not a direct read of the user's private local file. Run the command to obtain the actual saved-file report. Line-length warnings can overlap speed warnings.

For a children-oriented film, use `--profile children`. You can explicitly tune `--max-cps`, `--max-line-chars` and `--max-lines` if the device/player profile requires it; the tool restricts these values to bounded ranges.

**Important acceptance boundary:** `READABILITY_HEURISTICS_PASS` means only that character count/line-count checks did not warn. The report **always** carries `human_semantic_review=REQUIRED`. Human review must check translation fidelity, tone, slang, context across scenes, relation-dependent “anh/em”, and whether reductions lose meaningful lines. Do not automatically paraphrase, change timestamps, or invoke Gemini/Antigravity from this QA command.

The attended *future* manual Gemini prompt generated by `agy_handoff.py prepare` now asks for concise natural Vietnamese within the existing 2.5-second cue budget **without sacrificing meaning or pronoun consistency**. Previously prepared `agy-prompt.txt` files will not change; generating a new prompt is a separate manual action that may later consume quota only if the Human explicitly calls `agy -p`. The 36 original synthetic cases in `benchmark_synthetic.json` remain available for later bilingual blind review but have not been translated/scored by this change.
