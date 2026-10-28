# Deep Research 2026-10-28 — AI Entertainment Agent alignment for Torrent TV Vietsub

**Status:** RESEARCH_REVIEWED / PROPOSED_ARCHITECTURE / IMPLEMENTATION_UNVERIFIED
**Source:** user-provided deep-research-report.md, “Nghiên cứu kiến trúc AI-driven Torrent TV: từ câu lệnh tự nhiên đến phát phim và thuyết minh tiếng Việt trên Redmi TV”.
**Authority:** Human decision 2026-10-28 > PROJECT_CONTRACT > accepted ADR > report recommendations.
**Important:** report citations, vendor claims, API versions, pricing, firmware and performance are research inputs, NOT independent deployed evidence.

## Quyết định tiền đề và phần xung đột

- **OMP FIRST (HUMAN_DECIDED):** tiếp tục trên OMP TypeScript/Preact/Capacitor và các native playback components 2160 Player/Media3/VLC/Kotlin có sẵn. **Không** tạo client Kotlin + Jetpack Compose + Media3 mới dù báo cáo khuyến nghị native app độc lập. Mọi deep-link, WSS, track selection, MediaSession phải đánh giá khả năng tích hợp vào OMP hiện có.
- **Independent AIOS (HUMAN_DECIDED):** repo, CI, runner, secrets, governance, runtime đều thuộc Torrent TV; AIOS chỉ là nguồn template/code đã audit, không có Brain/admission/dispatch.
- **P0 không cần AI agent:** manual magnet và website source adapters OMP vẫn hoạt động; local Gateway là opt-in về sau.
- **No automatic acceptance:** bản báo cáo đã hoàn thành, không đồng nghĩa tính năng, TV, TorrServer, OpenAI MCP hoặc worker đã được test.

## Kiến trúc đích nghiên cứu (PROPOSED)

~~~text
Optional ChatGPT / natural-language interface
       | semantic MCP tools (private connectivity pending official verification)
       v
Home Media Gateway — separate Torrent TV runtime
  auth / policy / consent / confirmation / session FSM / audit / metrics
       +---- existing OMP website source adapters (preserved)
       +---- optional Prowlarr/Torznab (primary candidate) or Jackett
       +---- Candidate Verifier (source/rights, size, seeds, media probe)
       +---- TorrServer REST adapter (Windows/NAS, trusted LAN)
       |       +---- direct HTTP first
       |       +---- remux/HLS/transcode only if deployed build supports it
       +---- Vietnamese Audio Worker (optional; Windows/NAS)
       |       ASR -> MT -> duration rewrite -> vi-VN TTS -> ducking/mix
       +---- OMP device session-control extension (only after TV capability)
                          |
                     OMP-based TV UI + existing native player
                     2160/Media3/VLC; D-pad/seek/VI tracks/subtitles
~~~

**Control plane:** source search, authorization, device identity, playback intent, candidate scoring, session state and telemetry.
**Media plane:** TorrServer swarm/cache/HTTP/HLS and OMP playback engine. No torrent engine in TV APK; do not fork TorrServer.
**ChatGPT is NOT a direct TorrServer /mcp or admin client.** A Secure MCP Tunnel described in the report is a possible mechanism, pending verification of current official documentation, product entitlement and security; never expose inbound TCP 8090/gateway just to test ChatGPT.

## Capability / decision matrix

| Report finding | Adaptation for Torrent TV | Gate |
| --- | --- | --- |
| Prowlarr/Torznab; Jackett backup | Optional adapter alongside OMP website search; legal allowlist, no unauthorized crawl | G-SOURCE, G-VERIFY |
| Seeder semantics | Store reported, tracker-scraped when supported, connected peer/seeders separately, with source and timestamp; never sum duplicate trackers | G-VERIFY |
| “2K” ambiguous | Explicit pixel policy (min width/height) and hard-vs-preference; never accept release name alone | G-VERIFY |
| Torrent/media verification | Torrent metadata/files -> select main media -> ffprobe actual pixels/codec/audio/bitrate -> track throughput and buffer | G-VERIFY, G-SERVER |
| Readiness | Adaptive buffer/rate; direct play -> remux -> transcode as last resort; fallback only if constraints allow | G-SERVER, G-TV |
| Session control | Gateway-owned FSM and authenticated device identity, short-lived session ID/token; OMP adaptation, not rewrite | G-GATEWAY, G-AGENT |
| TV signalling | Feature test Redmi A Pro 55 China; native OMP extension first, Cast Connect conditional, ADB dev-only, DLNA last resort | G-TV |
| Vietnamese audio | Real embedded vi/vie/vi-VN track first, external SRT/VTT fallback, AI only opt-in with rights | G-VI, G-P1 |
| AI voice-over | Multilingual Whisper/faster-whisper candidate, MT adapter, rewrite to timing, TTS, normalize/duck/mix. Batch first, rolling second | G-AUDIO-BATCH, G-ROLLING |
| AI voice privacy | local_only / cloud_allowed / cloud_preferred, cost estimate, retention, consent, no unauthorized voice cloning | G-SECURITY |
| OpenAI private MCP | Semantic only: search, verify, prepare, play, pause/seek/stop/status, device list; scoped auth/confirmation | G-MCP |
| 6–10 weeks / 54–103 person-days | Engineering estimate from report involving a separate new native TV app; not a revised schedule for OMP project | PLANNING_ONLY |

## Interface sketch — NOT implemented API

~~~json
{
  "playback_intent": {
    "media_title": "Authorized test title",
    "resolution_policy": "UNSPECIFIED_2K",
    "min_width": null,
    "min_height": null,
    "size_bytes_min": 8589934592,
    "size_bytes_max": 12884901888,
    "min_reported_seeders": 300,
    "device_id": "living-room-tv",
    "preferred_language": "vi-VN",
    "fallback_audio": "ai_voiceover_opt_in",
    "constraint_mode": "hard"
  },
  "candidate_verification": {
    "rights_status": "must_verify",
    "source_id": "approved-source",
    "reported_seeders": null,
    "tracker_scraped_seeders": null,
    "connected_seeders": null,
    "verified_at": null,
    "media_probe": null,
    "download_rate_bps": null,
    "buffer_ahead_seconds": null
  }
}
~~~

- Seed counts are separate observations; tracker scrape may be unsupported, stale or duplicated. Playback readiness is NOT equivalent to reported seeders >= 300.
- Torznab metadata provides pre-filter only. Resolve video/audio tracks by actual media probe, not untrusted filenames.
- Hard constraints must not be silently relaxed. “2K” needs an explicit policy in pixels, with user or configuration resolution.
- Candidate and indexer text is untrusted data; never execute its instructions or model-generated arbitrary URLs/commands.

**Illustrative REST endpoints:** POST /v1/media/search; POST /v1/candidates/{id}/verify; POST /v1/playback/sessions; POST /v1/playback/sessions/{id}/prepare; POST /v1/playback/sessions/{id}/play; POST /v1/playback/sessions/{id}/control; GET /v1/playback/sessions/{id}.
**Illustrative semantic MCP tools:** search_media, verify_media_candidate, prepare_playback, play_on_device, pause_playback, seek_playback, stop_playback, get_playback_status, list_household_devices.
**Never expose:** shell_exec, arbitrary_http_get, torrent_admin, delete_files, raw_indexer_key, raw_torrserver_credentials or TorrServer's raw /mcp.

## Playback session design / thresholds

~~~text
DISCOVERING -> VERIFYING -> PREPARING -> BUFFERING -> AUDIO_PREP? -> READY -> PLAYING
                                                     |                 |
                                                     v                 v
                                                   FAILED      DEGRADED/FAILED/STOPPED
~~~

**Research POC targets, not vendor guarantees:** initial buffered media 30–60s; rate observation 10–20s; sustainable download >=1.5–2.0 × average media bitrate; first frame <15–30s if swarm healthy; no rebuffer across a 30-minute controlled test; LAN command <1s. Measure average AND peak bitrate, hardware, local network, buffer ahead, EWMA rate, legal fixture license and actual result. Readiness cannot be asserted from target values alone.

Playback fallback: wait/increase buffer -> alternate lawful candidate -> lower bitrate only if user preference permits -> remux/HLS if container mismatch -> transcode as last resort if codec mismatch and server supports it. Real TorrServer version, REST request schema, Range/seek, native /mcp, -gst capability, auth, default cache and binary hash **must be verified** before wiring code.

## Vietnamese path — staged

1. Detect actual vi/vie/vi-VN audio in OMP's player/track model and prioritize it; preserve SRT/VTT UTF-8 and source-agnostic external subtitles (ADR-0006 G0–G4).
2. Licensed/authorized sample only: multilingual ASR -> MT adapter -> dialogue rewrite to fit source duration and terminology -> Vietnamese TTS -> normalize/duck/mix (voice-over, not full character dubbing) -> verified compatible alternate audio/HLS/file path. Do not assume OMP supports standalone audio tracks without testing.
3. **Batch/pre-generated first.** Test language accuracy, timing drift, quality, loudness, pause/seek/reopen, compute/time/cost/privacy. PhoWhisper is Vietnamese-specific and not the default ASR for English/Japanese/Korean source.
4. **Rolling later:** 30–60s look-ahead is a design target; handle seeks by generation priority or temporary original-audio fallback. No immediate/true realtime guarantee.
5. Cloud usage only with explicit processing policy and rights; no automatic upload in local_only mode. TTS vendors/local model licenses and prices require fresh verification; do not hardcode report prices.

## Security, law and evidence

- Gateway must enforce scoped authentication, device pairing (only if OMP device support proven), token lifetime/revocation, authorized source allowlist, user confirmation for side-effect actions, idempotency and sanitized logs.
- No raw TorrServer credentials to ChatGPT, OMP TV or model context; audit pre-existing OMP native/VLC playback URL userinfo risk separately.
- Prompt injection from search metadata, SSRF, redirects, hidden/internal network URLs, media file paths and arbitrary commands must be negative-tested.
- Rights to stream, reproduce, translate and make derivative audio must be checked for media/fixture; BitTorrent protocol does not imply media is licensed. Cloud consent and retention are separate from copyright.
- Use repo-specific PR/ADR/CI and explicit Human approvals. Do not turn on Windows services, runner jobs, server/network ports, AI audio or merges by editing docs.

## Acceptance ordering

G-DEV/G-OMP (pin OMP/submodule SHA, license, build, runner proof) -> G-SERVER/G-TV (actual TorrServer and exact Redmi firmware plus lawful direct playback/seek) -> G-P1 external Vietsub -> G-VERIFY (legal search, provenance/probe) -> G-GATEWAY (FSM/security) -> G-AGENT (authorized candidate + confirmed actual OMP TV session) -> G-AUDIO-BATCH (licensed voice-over QA) -> G-ROLLING + G-MCP (optional advanced gates). P1 and independent audio research can overlap without blocking manual playback.

**Unverified external facts from the report include:** TorrServer MatriX.147.1 and -gst/MCP specifics for deployed host; Redmi firmware/Google Cast; private MCP tunnel current access; pricing/model/locale of speech providers; default TorrServer cache and capacity; real tracker scrape support; GPL obligations/dependencies. Reported research claims are hypotheses pending primary-source and/or deployed evidence.
