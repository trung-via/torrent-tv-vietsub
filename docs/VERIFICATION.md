# Verification contract

Layer A (no external hardware): OMP TypeScript/Preact/Capacitor checks, existing native Kotlin/2160/Media3/VLC unit tests where supported, mocked HTTP/session APIs, APK build and emulator tests. **No new Kotlin/Compose client.** Layer B: live TorrServer LAN health + legal fixture/seek test when endpoint & permission available. Layer C: physical TV install/navigation/playback/subtitles when TV, ADB and permission available.

Report each layer independently: `NOT_RUN`, `PASS`, `FAIL`, `BLOCKED`, `UNVERIFIED`. No default PASS for absent hardware. Do not invoke AIOS-renew suites, AIOS canonical governance or dispatch. Review/test/CI belong only to Torrent TV and must pin source SHA, fixture, run ID and verified environment. Preserve evidence; do not silently retry until green.

## Deep Research acceptance gates — independent evidence

- **G-VERIFY:** lawful source, candidate source/time provenance, distinct reported/scraped/connected seeders, explicit resolution pixel policy, media probe and measured throughput/buffer. Seed>=300 is not stream readiness.
- **G-GATEWAY:** control-plane FSM, authentication, device pairing, idempotent writes, status/rollback, input validation, anti-SSRF and indexer prompt-injection negative tests.
- **G-AUDIO-BATCH:** real vi audio selection priority; licensed clip multilingual ASR/MT/TTS, timing, voice-over duck/mix, pause/seek, consent/privacy/cost measurements.
- **G-ROLLING:** only after batch proof; seek catch-up, audio fallback, generated-ahead buffer, underrun/drift/latency, resource usage.
- **G-MCP:** optional; independent proof of official private connectivity/product entitlement, semantic tool authorization, confirmation, no raw TorrServer MCP exposure.

The Deep Research estimates discovery <5s on responsive sources, first frame <15–30s on a healthy swarm, initial buffer 30–60s, sustained rate >1.5× avg bitrate, zero rebuffer over 30-min controlled test, LAN commands <1s and rolling buffer 30–60s. **These are experimental POC targets, not observed PASS or platform guarantees.** Record actual fixtures, codecs, hardware, network and failures.
