# TorrServer interface contract — DISCOVERY REQUIRED

Dependency: upstream https://github.com/YouROK/TorrServer; no fork or included binary in this initial repo.

## Proposed adapter methods

- `checkConnection(endpoint, auth?) -> Health | TypedError`
- `listTorrents() -> List<TorrentSummary> | TypedError`
- `listVideoFiles(torrentId) -> List<VideoFile> | TypedError`
- `resolvePlayableUrl(torrentId, fileId) -> StreamHandle | TypedError`

Exact paths, verbs, authorization and response schemas **MUST** be recorded against a pinned, deployed TorrServer release; example routes `/echo`, `/torrents`, `/stream`, `/play` are unverified. Do not hardcode undocumented assumptions as acceptance evidence.

## Test taxonomy

`SERVER_OFFLINE`, `SERVER_TIMEOUT`, `AUTH_REQUIRED`, `API_INCOMPATIBLE`, `NO_METADATA`, `NO_PEERS`, `HTTP_RANGE_UNSUPPORTED`, `MEDIA_UNSUPPORTED`, `SUBTITLE_UNSUPPORTED`.

Test mock offline/HTTP status/parser without Internet or BitTorrent. Real server smoke later using an authorized open-license fixture; record version and redacted request trace.

## Deep Research adapter/verification proposal (NOT DEPLOYED)

The 2026-10-28 research reported optional upstream experimental streaming features; these are not deployed capability evidence. **The project's isolated GStreamer trial was retired on 2026-11-22.** The active embedded-EN diagnostic uses bounded EBML/HTTP Range reads, independently of those experimental features. Check the deployed TorrServer binary, REST/auth and Range responses before claiming live support.

- Prowlarr/Jackett through Torznab is optional alongside existing OMP website-source search; Torznab is a schema, not a repository of licensed media.
- Candidate verifier: source-rights and metadata prefilter -> optional tracker scrape (store tracker, timestamp, scrape support) -> TorrServer metadata/file list -> selected-file validation -> ffprobe resolution, codec, audio, bitrate -> actual download rate and buffer ahead.
- Distinguish reported, scraped and connected seeders, as well as observed peers/throughput; never sum duplicate tracker peer counts or treat a release name as codec proof.
- Adaptive readiness research POC targets: observe torrent rate for 10–20 seconds; initial playable buffer 30–60 seconds; target sustainable throughput >=1.5–2.0 × average media bitrate. Real peaks/server cache/hardware can require more. Targets are not TorrServer defaults or guarantees.
- Delivery order: direct HTTP first. Remux or transcode is a separate, explicitly verified future option, not part of the English subtitle extraction path. Do not change server cache, streaming defaults or binaries because of this historical research.
- No direct ChatGPT access to native TorrServer /mcp. Gateway calls scoped REST methods inside LAN; secrets must never enter native/VLC media URLs, model context or logs. Typed errors, idempotent requests, timeouts and cleanup need negative tests.

Record deployed API/schema/version/build, basic authentication mode, permitted fixture, Range/seek, server metrics and exact test evidence before REAL_SERVER_VERIFIED.
