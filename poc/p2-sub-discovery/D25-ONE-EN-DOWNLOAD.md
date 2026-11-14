# D2.5 owner-local one approved English subtitle download trial

**Purpose:** The owner has authorized **one quota-bearing download** of the
previously discovered **ordinary, non-SDH, exact-video-group English source**.
This is a bounded real-provider acquisition trial, not the Gemini/TV gate.
The repo is PUBLIC: owner media names, OpenSubtitles file IDs, API keys,
download links, local paths, and copyrighted subtitle text stay on the
owner's Windows laptop only.

## Entry point

Run `owner_en_single_trial.py` locally using:
- `--release-name`: exact authorized selected TorrServer video name;
- `--expected-en-release`: exact previously observed ordinary EN release
  hint (not the SDH version);
- `--expected-group`: exact video release group, case-insensitive;
- optional `--imdb-id` only if independently verified. By default searches
  title and year parsed from the release filename.

Set `OPENSUBTITLES_API_KEY` only in the local process environment using a
hidden input and remove it afterwards. No key or provider URL is embedded
in code, scripts or GitHub comments.

## Mandatory barriers

1. Search with **VI_FAST** (one VI metadata GET; then EN up to two pages),
   no POST. If a *confident VI* now wins, stop: this permission is **EN-only**.
2. EN route must be confident, single unambiguous winner, matching exactly
   the owner-approved ordinary EN release string. Exact video group plus
   title/year/source/resolution/codec evidence required; SDH is prohibited.
   Any provider result drift or source ambiguity stops without POST.
3. Show status and ask for `DOWNLOAD ONE` locally. Any other input cancels.
4. Check private cache writability BEFORE posting. Create a per-target
   content-hashed `.en-once-*` attempt marker by exclusive creation BEFORE
   provider POST. An uncertain outcome or process restart must not silently
   retry. Reattempt requires a new specifically reviewed authorization; do
   not delete the marker just to make a test pass.
5. Use existing D2 `download_manual_en` and request `sub_format=srt` through
   **one provider POST**; no retries. Verify returned UTF-8 timed SRT, cue count,
   content SHA-256 and save privately using the existing content-addressed
   cache with no-clobber.
6. Never invoke Gemini, upload dialogue, bind to TorrServer/OMP or deliver
   to TV inside this owner trial. `REAL_VIDEO_SYNC_VERIFIED=NO`.

## Evidence distinctions

- Prior owner `D25_SEARCH_ONLY` (real OpenSubtitles metadata): successful,
  `VI_CONFIDENT=0`, `EN_CONFIDENT=2`, standard EN outranks SDH; **0 POST**.
- This trial's **Python synthetic CI PASS** proves the one-POST contract,
  source pin and local private-cache guards; it does **NOT** prove a new
  real OpenSubtitles download. `D2_EN_REAL_DOWNLOAD=NOT_RUN` until the
  owner returns real statuses.
- A real `DOWNLOAD_AND_SRT_QA=PASS` confirms legal provider bytes/SRT QA,
  **not** on-video timing or Gemini semantic translation.
- If a local attempt prints `DOWNLOAD_POST_ATTEMPTS=1` and later fails,
  consider quota spent. Do not rerun merely to retrieve the same SRT.

## Successful handoff

Return only safe output status: `ROUTE`, `EXACT_RELEASE_MATCH`,
`EN_WINNER_SCORE`, `DOWNLOAD_POST_ATTEMPTS`, `DOWNLOAD_AND_SRT_QA`,
`SRT_CUES`, `PRIVATE_CACHE_SAVED`, `AI_TEXT_UPLOADED`, `NEXT_GATE`.
The saved asset remains owner-private pending an independently trusted
actual-media binding and a separate existing P2 Gemini LEAN120 API step.
