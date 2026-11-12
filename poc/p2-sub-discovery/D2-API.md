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
