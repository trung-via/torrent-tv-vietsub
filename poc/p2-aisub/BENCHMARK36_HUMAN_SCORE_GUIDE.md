# P2-AISUB.2e — Attended Human scoring on Windows (36 original synthetic cases)

**Status:** Source-only offline scoring helper. Does NOT call Gemini, Antigravity, APIs or other AI; never provides assistant/model/default ratings, edits the original corpus or changes OMP/Redmi.

## Purpose

The 36 original fictional *independent single-dialogue* translations have all passed strict JSON import in three batches of 12; the official Human rating sheets are still blank. The existing benchmark36.py score and aggregate remain canonical; this helper makes real Human score entry resumable and easier than editing JSON manually. Prior assistant editorial comments are NOT Human ratings.

## One line per original dialogue

The local interactive terminal displays the genre, speaker, scene context, English source and Vietnamese translation. The reviewer enters five integer scores 1..5 followed by y or n, e.g.:

    4 5 3 4 2 n

The five fields (in order) are semantic_accuracy, vietnamese_naturalness, relationship_pronouns, tone_register, subtitle_readability. Use 1=seriously wrong, 2=weak, 3=usable with edits, 4=good, 5=excellent. Last field hallucination is y when significant new meaning/facts/relationship have been invented, n otherwise. Readability is for a *hypothetical 2.5-second cue*, not a real timecoded subtitle.

No defaults are supplied. Press q or Enter to pause; s skips a case. Every completed case saves immediately. Restarting with the SAME draft file resumes only unfinished cases. A label A alone is not proof of a genuinely blind A/B review.

## Windows PowerShell — batch 1

Run in the Torrent TV checkout after PR merge. Reuse exact original translated and blank ratings artifacts, not the separate 12-cue SRT artifacts.

    $ErrorActionPreference = "Stop"
    $env:PYTHONIOENCODING = "utf-8"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
    $humanTool = "poc/p2-aisub/benchmark36_human.py"
    $dir = Join-Path $env:LOCALAPPDATA "TorrentTVVietsub\Benchmark36"
    Get-ChildItem -LiteralPath $dir -Filter "*-b1-translation-A.json" | Select-Object Name,FullName
    Get-ChildItem -LiteralPath $dir -Filter "*-b1-ratings-A.json" | Select-Object Name,FullName

    # Use the exact existing paths from the previous Human-attended batch.
    $translation1 = "<EXISTING-B1-TRANSLATION-PATH>"
    $scores1 = "<EXISTING-B1-BLANK-RATINGS-PATH>"
    $humanDraft1 = Join-Path $dir ((Get-Date -Format "yyyyMMdd-HHmmssfff") + "-b1-human-ratings-A.json")
    python $humanTool review --translations $translation1 --template $scores1 --out $humanDraft1 --confirm ATTENDED_HUMAN_SCORE_36
    if ($LASTEXITCODE -ne 0) { throw "BENCHMARK36_HUMAN_REVIEW_FAILED" }

Private source and translation strings print only on the attended local terminal. The new ratings draft has the **exact old benchmark36 ratings schema**, plus a companion .binding.json with the content SHA of the original translation. Keep both files together; no raw dialogue is stored in the binding file. Do not upload local drafts to GitHub.

## Status, resume, finish

Rerun the SAME review command with the SAME draft path after an interruption; do not generate a new timestamp. A later terminal can locate the already created human-ratings file and set $humanDraft1 to that exact existing path.

    python $humanTool status --translations $translation1 --draft $humanDraft1

Example: BENCHMARK36_HUMAN_PROGRESS batch=1 scored=3/12 remaining=9 human_input_only.

When all twelve answers have genuinely been entered:

    $report1 = Join-Path $dir ((Get-Date -Format "yyyyMMdd-HHmmssfff") + "-b1-human-report-A.json")
    python $humanTool finish --translations $translation1 --draft $humanDraft1 --report-out $report1 --confirm ATTENDED_HUMAN_SCORE_36
    if ($LASTEXITCODE -ne 0) { throw "BENCHMARK36_HUMAN_FINISH_FAILED" }

Expected: BENCHMARK36_HUMAN_SCORE_RECORDED batch=1 cases=12 quality_certified=False. Incomplete or invalid sheets FAIL. This reuses the existing score_review function rather than altering its rubric.

Complete batch 2 using its matching $translation2/$scores2 and a new $humanDraft2/$report2, then batch 3 using matching $translation3/$scores3 and $humanDraft3/$report3. There are NO new Gemini calls.

After all THREE batches have real Human scores:

    $benchTool = "poc/p2-aisub/benchmark36.py"
    $combined = Join-Path $dir ((Get-Date -Format "yyyyMMdd-HHmmssfff") + "-36-human-summary-A.json")
    python $benchTool aggregate --reports $report1 $report2 $report3 --out $combined
    if ($LASTEXITCODE -ne 0) { throw "BENCHMARK36_AGGREGATE_FAILED" }

The resulting aggregate holds five score means by genre and overall, hallucination counts, and quality_certified=False. It does not prove actual movie quality, subtitle synchronization or Redmi E2E.

## Evidence boundary

Source CI uses invented *test-only* scores, never actual Human responses. The program is a Human entry workflow, not an automatic quality grader. It cannot independently prove reviewer identity, independence/blinding or correctness of the subjective judgments. No model/network/TV/Windows service action occurs.