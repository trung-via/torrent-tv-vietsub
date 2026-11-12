# D2 — OpenSubtitles REST acquisition (Issue #123)

STATUS: source candidate, independent and Free-first. No live credentials, movies, downloads or TV operations.

## Workflow
1. The caller identifies one authorized TorrServer media using (server_profile_id, torrent_hash, file_index); D1 #122 handles release-name ranking.
2. Search Vietnamese with GET /subtitles using the selected filename, year, and optional previously verified moviehash.
3. Only after D1 returns confident VI_MATCH, explicitly request one POST /download by file_id. This request consumes download quota. If no VI_MATCH, search EN and require confident EN_TRANSLATE before handoff to P2-AISUB.
4. Fetch the temporary HTTPS link only from approved OpenSubtitles hostnames. Never persist this temporary URL. The link may expire within three hours.
5. Validate UTF-8, SRT/VTT timestamps, size <=256 KiB and sha256. Cache the subtitle bytes by media binding, file_id and digest in an owner-private local folder. D2 does not connect TV or trigger translation.

## API boundaries
Official docs: https://ai.opensubtitles.com/api-docs
Help center: https://opensubtitles.tawk.help/article/about-the-api

- Base https://api.opensubtitles.com/api/v1
- Headers Api-Key and User-Agent, optional Authorization Bearer token; no silent login
- Free key search supported; download allowance varies by identity and account; no hardcoded free quota or retries
- HTTP errors 401, 403 and 429 classified without exposing keys/URLs; redirects with cross-host credentials rejected
- Live provider headers, URL redirects and quota require a separate approved real-key smoke test

## Offline tests
Run from repo root:
    python -m unittest discover -s poc/p2-sub-discovery -p 'test_*.py' -v

Synthetic tests exercise API query, candidate matching, signed exact-media decisions, request count, auth/quota errors, untrusted URLs, caption validation, digest cache and file A/B isolation. Hosted-only CI definition in .github/workflows/tv-sub-discovery-ci.yml runs no privileged Windows process and no secrets. Existence of a CI YAML file is not CI_PASS.

## Source-only acceptance and next gates
- No direct TorrServer API integration; no local cache daemon; caller invokes API/download/cache explicitly.
- API key from OpenSubtitles consumer must be provisioned privately on laptop (e.g. OPENSUBTITLES_API_KEY environment variable); no hard-coded keys, passwords or subtitle content in GitHub.
- D1 review is pending (#122). D2 Draft PR is stacked on D1. P2 LEAN120 and P4 receiver #119/#120 remain independent.
- Real OpenSubtitles API/login/download/quota: NOT_RUN. Redmi LAN pairing, G1/G2/G3/G4 and release: NOT_RUN. Rollback by discarding this isolated branch.

Repo is currently PUBLIC even though older documentation says PRIVATE. No private filename, movie dialogue, secrets, magnet URL, tracker passkey or home IP may be placed in GitHub.

## One-time Human action for real-key testing (no password shared)

1. Open https://www.opensubtitles.com and register/login; navigate to https://www.opensubtitles.com/en/consumers and generate a **free API Consumer key** for the personal app. Keep all credentials private on the owner's laptop, never GitHub comments/PR/ChatGPT.
2. From a trusted checkout of this reviewed Draft branch on Windows, use PowerShell and run the local script `./poc/p2-sub-discovery/owner-smoke.ps1` (relative to repo root). It prompts for key without showing typed characters and clears the API key from that script's environment after the request.
3. The script calls **only** `GET https://api.opensubtitles.com/api/v1/infos/languages`. It never logs in, sends a movie title, consumes subtitle-download quota, or posts the key to any third-party host.
4. Report only a sanitized code: `API_READONLY_SMOKE_PASS`, `API_KEY_NOT_CONFIGURED`, `API_AUTH_DENIED`, `RATE_LIMITED_429`, `API_NETWORK_ERROR`, or `API_RESPONSE_INVALID`. **No screenshots of Consumer/key page**, password, Bearer token, home IP or full HTTP response.
5. This read-only probe establishes API-key access **only**. A separate Human-authorized real search and `POST /download` for a rights-cleared subtitle fixture will be necessary to prove login/account quota/redirects and actual SRT behavior. No TV pairing required for this D2 stage.

## D2 Human real search-only checkpoint (after API readonly smoke)

The prior `GET /infos/languages` success only establishes endpoint connectivity.
It may not authenticate the key because language-list access may be public.
Only a real `GET /subtitles` response establishes authorized search access.

**On Windows with a reviewed checkout of this D2 Draft branch** run
`& .\poc\p2-sub-discovery\owner-search.ps1` as a single PowerShell command.
The script hides the API key as it is typed and prompts for **one authorized
media release filename**. The input is not committed to GitHub or printed
by the tool. Provider sees the selected filename/title in the API query.

The owner search does at most four API GET calls:

1. VI query = full filename release (without extension), optional year.
2. VI query = parsed movie title, optional year (only if first has no confident match).
3. EN release query (only if no confidently ranked VI).
4. EN title query (only if earlier searches had no confident match).

It prints sanitized counts/decisions:
`VI_RELEASE_CANDIDATES=N`, `VI_RELEASE_DECISION=...`,
`BEST_LANGUAGE=VI|EN`, `BEST_MATCH_EVIDENCE=...`,
`NEXT_GATE=VI_MATCH|EN_TRANSLATE|REVIEW_REQUIRED|NO_MATCH`,
and `DOWNLOAD_REQUESTS=0`. If API key is invalid, expect sanitized
`API_AUTH_DENIED`. Do not share key, password, full URL, original filename
or subtitle dialogue with PUBLIC GitHub. Share only these codes.

**This is a standalone search proof only.** It uses a clearly labeled unverified
placeholder identity rather than reading the actual TorrServer file hash,
index, embedded subtitles or bytes. No movie hash matching claim, no
`POST /download`, no SRT/VTT payload and no TV auto-refresh claim.
Real title/release results are unverified until the owner runs the command.

## Diagnostic repair after real owner search returned nonzero rows and no candidates (2026-11-12)

**HUMAN_REPORTED:** selected filename entry `thor 2017`, search-only `imdb_id=3501632`.
VI IMDb API returned 6 of 6 rows; EN IMDb returned 50 of 58 rows.
Both languages had `CANDIDATES=0`, `RANKED=0`, `DOWNLOAD_REQUESTS=0`.

This is **not** OpenSubtitles lacking subtitles, nor proof that any SRT is
available. The parser rejected rows for an as-yet unverified reason.
The current parser explicitly accepts only file names ending `.srt` or
`.vtt`; provider may return other formats or incomplete metadata.
Do **not** auto-download or infer format until a real response validates
conversion via `POST /download` with optional `sub_format`.

**New targeted owner diagnostic:** `owner_search.py --imdb-id 3501632 --diagnose-imdb`
sends only **two** API GET requests (`languages=vi` and `en`, no
filename/year filters), then prints `VI_IMDB_RAW_ROWS`, `VI_IMDB_CANDIDATES`,
`VI_IMDB_RANKED`, and `VI_IMDB_REJECT_...` counts (similarly EN).
Safe codes include: `MISSING_ATTRIBUTES`, `UNEXPECTED_LANGUAGE`,
`MISSING_FILES`, `INVALID_FILE_ENTRY`, `INVALID_FILE_ID`,
`MISSING_FILE_NAME`, `UNSUPPORTED_EXTENSION`, `DUPLICATE_FILE_ID`,
`OVERSIZED_NAME`. Real release name, user identity, API key,
server/TV address, file id and text are NOT printed.
Still **zero** subtitle downloads. Do not claim verified
TorrServer identity or matching `YAWNTiC` if the owner only supplied
`thor 2017` instead of the selected video's exact filename.

Official schema for `/subtitles` response includes `attributes.language`,
`attributes.files[].file_id` and `attributes.files[].file_name`;
official `POST /download` optionally accepts `sub_format`, but it
still costs a download-quota event and remains **NOT_RUN**.
Reference: https://ai.opensubtitles.com/api-docs

Next accepted step after diagnosing: targeted fix for the observed provider
schema with synthetic fixtures, CI, and explicit review of the conversion/
format gate. No untrusted raw API response may be attached to the public repo.

## D2 parser format gate root cause (HUMAN_REPORTED 2026-11-12)

Owner's two-GET IMDb diagnostic on selected release
`Thor Ragnarok 2017 1080p BluRay x265-YAWNTiC` showed:
- VI: 6/6 provider rows rejected as `UNSUPPORTED_EXTENSION`.
- EN: 50 of 58 provider rows (page 1) rejected as `UNSUPPORTED_EXTENSION`.
- `DOWNLOAD_REQUESTS=0`, no TorrServer media binding.

**Proven:** Original parser was discarding valid provider search **metadata**
before release ranking because `files[].file_name` did not have an accepted
`.srt`/`.vtt` suffix. The precise unknown source filename extensions were
not disclosed and must not be guessed.

**Change:** D2 source accepts sanitized provider metadata with a valid
`file_id` even when the filename suffix is not SRT/VTT. Common subtitle
suffixes (`.ass`, `.ssa`, `.sub`, `.txt`, etc.) are stripped for
release matching. Obvious non-subtitle binaries/archives remain rejected.
`Subtitle.fmt=provider` means **unverified** source formatting, not "SRT".
Source format and trustworthy sync are not proved by the candidate title.

**Future owner-authorized download** for a confident provider candidate:
OpenSubtitles `POST /download` with `sub_format=srt`, then strict UTF-8
SRT timeline/cue/size QA **before** returning any asset/cache path. Requesting
conversion may spend a download-quota event even if the returned file is
invalid. There is no attempt to download in CI or owner search-only tools.
This path remains NOT_RUN with real credentials/film.

**Targeted same-release verification:** Re-run only two read-only queries with
`--imdb-id 3501632 --diagnose-imdb`; print `CANDIDATES`, `RANKED`,
`CONFIDENT`, `GROUP_MATCHES`, `DECISION`, `DOWNLOAD_REQUESTS=0`.
All output is aggregate counts, never provider filenames or user tokens.
The owner must use the exact selected file release, not a shorthand such as
`thor 2017`. Even a group match is only a provisional sync hint until
actual media and track timing are checked.

Official provider conversion parameter:
https://ai.opensubtitles.com/api-docs
