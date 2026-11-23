## G3 — source implementation checkpoint (2026-11-23)

**Current code path:** Existing R2 P2 verified checkpoint → original P4 subtitle publication **first** → one bounded VieNeu TTS consumer (Ngọc Linh, Vieneu(mode="v3turbo", backend="onnx")) → verified 48 kHz WAV cache → VoiceoverAudioLane → **same P3/P4 pinned HTTPS listener**. No new AGY call, Windows service, TV app or external HTTP server is introduced.

Opt-in Owner bootstrap (only for the single trusted owner process):
- Existing owner_p3_p4_entrypoint.py --start-lan --owner-root ... --cache-root ... --state-root ... remains subtitle-only by default.
- Add --enable-vieneu-voiceover on an explicitly approved startup to enable the local Owner TTS callback. It never downloads/loads the VieNeu model during import, composition or preflight. First actual committed VI cue may require SDK/model weights and CPU time.
- The --preflight-only path does not synthesize, activate TTS, or open LAN even if the voice flag is provided.
- WAV receipts remain under the configured private cache root, in vieneu-ngoc-linh-wav/, scoped by deterministic film/source/voice/cue key. A failed ambiguous TTS stream remains held for reconciliation rather than blindly rerun.

Read protocol (on existing pinned P4 HTTPS host/port):
- GET /p4/voice/{sessionId} with X-P4-After-Cue: N (default 0) returns up to 32 per-cue HMAC-signed metadata offers for that exact source/session (204 when none); the request MAC is HMAC-SHA256(sessionKey, "TTV-P4-VOICE-READ-V1\n{sessionId}\nmanifest:{N}\n{nonce}").
- GET /p4/audio/{sessionId}/{ttsKey} returns only previously verified 48-kHz PCM16 WAV bytes, Content-Type: audio/wav, X-P4-Audio-Sha256; the request MAC uses the separate scope audio:{ttsKey}. Both require the usual P4 nonce headers, session/read authorization and recheck of currently verified TV media/consent. Duplicate nonces and cross-route MAC reuse are rejected. An unregistered or mismatched media/source key is never read.
- Offers are metadata, **not** audio bytes inside P4 subtitle JSON. TV must verify offer signature and WAV digest; it must never play on OFF/OTHER or stale session. TV-side sources now include P4VoiceoverLanClient.kt (pinned-HTTPS cue/WAV GET), P4VoiceoverReceiver.kt (pure HMAC + movie/session/choice gate), and a Kotlin/JVM Python-signature smoke. The OMP composer copies these classes into a source candidate, but **the PlayerActivity is not yet wired to poll the voice lane, nor is AudioTrack/VLC synchronization or original-audio ducking implemented**. A downloaded WAV is not proof of a cue heard on Redmi.

**Source-only boundary:** CI proves endpoint/callback/offline contracts, not successful VieNeu model installation, real signed Redmi audio GET or audible TV output. Before deployed runtime, verify current Owner's installed files/task/checkpoint and Windows model benchmark; do not replace a running Owner or clear film cache. Before claiming REAL_REDMi_PASS, implement and test OMP audio polling/overlay and SPDIF behavior, pause, seek, A→B→A. Source note only; independent Brain PASS and merge still follow #42.

## Giọng thuyết minh mặc định — quyết định Human 2026-11-23

**Chốt: Ngọc Linh** — preset chính xác `Ngọc Linh` trong `voices_v3_turbo.json` của upstream VieNeu-TTS, **nữ, miền Bắc, phong cách đọc truyện** (`doc_truyen`). Đây là quyết định chọn giọng của Owner, **không phải bằng chứng VieNeu đã được cài hoặc thuyết minh đã phát trên Redmi**.

- SDK: `Vieneu(mode="v3turbo", backend="onnx")`, `voice="Ngọc Linh"`; mặc định này chỉ khởi tạo khi tác vụ TTS được kích hoạt có chủ đích.
- Cache receipt / TTS identity dùng ASCII `ngoc_linh_v3turbo_onnx` (không truyền chuỗi ASCII này làm tên preset SDK). Khi thay model weights, revision, backend hoặc profile âm thanh ảnh hưởng chất lượng, nâng version voice-cache identity để không tái sử dụng WAV sai.
- Mẫu giọng tham khảo: https://raw.githubusercontent.com/sonlovinbot-team/vieneu-audio-studio/main/webapp/static/previews/ngoc-linh.mp3 (nghe thử, không thay thế benchmark giọng trên laptop Owner).
- Duy trì lựa chọn khác trong tương lai; không thay đổi cache phim, Owner Windows, AGY job hoặc OMP/TV tại thời điểm ghi quyết định.

# Vietsub + thuyết minh AI song song — VieNeu R0 contract (2026-11-23)

**Authority:** Human request 2026-11-23; #170 one Owner / one OMP; #180 G1 rolling 50/120; #179 existing AGY/LEAN120 revision contract; #181 G3 roadmap. **Status:** SOURCE PROTOTYPE ONLY. Not a deployed renderer, provider benchmark, audio LAN endpoint, verified TV feature or model selection.

## One producer; two consumers

```text
Redmi OMP signed current-film request
  -> Windows Owner P3 exact TorrServer hash/fileIndex/active session
  -> ONE EN acquisition (current Owner/AGY contract)
  -> ONE EN->VI AGY/LEAN120 translation (first ~50 cues; later <=120)
  -> durable, verified cumulative SubtitleRevision (P2)
     |-> Existing signed P4/G2 -> Vietsub on the same OMP VLC player
     `-> Voice-over planner -> VieNeu TTS -> private WAV/PCM timed cue cache
                                   -> optional signed LAN audio segment feed
                                   -> existing OMP player synchronized overlay
```

**Ordering:** subtitle publish is never blocked by TTS. Each committed revision is handed to both destinations, but only TTS **success** receipts advance its completed prefix. The audio path must use a bounded non-blocking scheduling slot belonging to the existing Owner, not another translator, listener, queue, background Owner or Android app. Never synthesize from raw EN, uncontrolled downloaded VI, rejected/uncommitted AGY output or an unverified revision.

## Source prototype in this PR

`poc/p2-aisub/voiceover_revision.py` consumes the actual existing `SubtitleRevision`, validates its payload hash, cue count and horizon, and yields only unsynthesized cue IDs for a specified voice. A local TTS-success receipt is represented by the exact deterministic `tts_key` for a contiguous prefix of cues. `tts_key` includes exact media identity, source hash, voice ID, cue number, text and timeline. This supports A -> B -> A without re-synthesizing A, while a new voice or rewritten translation generates different keys.

The module makes no network/model call, does not mark unproduced audio as successful and cannot send to a TV. An opt-in lazy VieNeu v3 Turbo ONNX/CPU streaming adapter now exists in `voiceover_vieneu.py` and is tested with an injected fake engine. It is not invoked by Owner and does not install model weights. Real durable receipt storage, output WAV/PCM encoding, LAN manifest and native playback remain next implementation units; integrate with the current #179/#182 candidate rather than deploying this prototype in isolation.

## VieNeu R1 adapter and local audio receipt

Primary local benchmark candidate: upstream [pnnbao97/VieNeu-TTS](https://github.com/pnnbao97/VieNeu-TTS), v3 Turbo, `Vieneu(backend="onnx")` CPU streaming and `infer_stream` first; compare `infer` for offline batch throughput. Use a built-in voice with an owner-private configurable name (avoid voice cloning by default); `style="doc_truyen"` is a benchmark option, not a permanent default. VieNeu supports an OpenAI-compatible local speech API and its Desktop releases describe `.srt`-timeline synthesis. Record exact SDK and model revision, Python/ONNX version and license for model weights separately from the upstream Apache-2.0 code repository. No download/install/remote API cost from this change.

Per cue: normalize plain UTF-8 dialogue for speaking without modifying SRT; generate WAV/PCM into a new private temporary file; validate rate/channels/frames/duration/peak, then atomically publish as `tts_key.wav` plus durable receipt. With unknown-effect synthesis preserve temporary/inflight state and avoid blindly overwriting completed audio. Split visually timed cues only at existing timestamps unless an explicit timing QA allows safe merging. If speech exceeds its slot, time-stretch by <=1.25x only after perceptual benchmark; otherwise request shortened *spoken copy* with a separately checked cue reference, or play original audio (never truncate syllables). This is voice-over, not multi-character dubbing.

## OMP/G2 native audio decision — not yet proven

**First narrow device experiment:** same installed OMP/VLC video, a short owner-supplied original/test WAV fixture played by an in-app audio overlay, keyed to VLC playback position. During speech duck VLC original volume by experimentally tuned amount (start by comparing 25–30% against 40–50%, without presupposing the best); outside voice restore original volume. Pause/seek/rate/reopen apply to both sources. On PCM/mixing-incompatible audio output (including possible SPDIF passthrough), abort the overlay and return to original audio; **do not** silently switch players, decode entire torrent or expose TorrServer. Native VLC audio output/Android AudioTrack coexistence is **UNVERIFIED**.

If on-device overlay cannot mix, evaluate a LAN segmented mix/proxy with `ffmpeg` and `-c:v copy`, *only* with measured TorrServer Range/seek and VLC compatibility. HLS/external-track hot attach is not assumed. GStreamer stays removed. Audio delivery must reuse P4's paired/session authentication concepts, but use distinct typed messages/endpoints and receipt IDs; it must never masquerade as a `SignedSubtitleOffer` or append binary into the JSON SRT contract.

## UX

Remote options in existing OMP UI: `Vietsub AI` (text), `Thuyết minh AI` (voice), `Cả hai`, `Âm thanh gốc`. A single enabled AI request can start the translation producer once; switching presentation only changes live consumers. Translation/checkpoint work for A may continue after switching to B; any audio push/play for inactive session must be rejected. `OFF/OTHER` turns off live subtitle and audio delivery, never accidentally resumes sound on a different film.

## Metrics and acceptance

- Synthetic: 50 -> 170 incremental cues, no repeated TTS keys; voice/media/source drift invalidates cache; missing audio receipt replays only the missing cue; same revision is idempotent; invalid digest/revision rejected.
- Windows real VieNeu: first speech latency, per-cue real-time factor, clip duration ratio, WAV integrity, peak/dynamics and memory consumption measured on actual laptop, optionally CPU vs GPU.
- Live P4/G2: after AGY checkpoint, Vietsub remains usable even if TTS synthesis fails, hangs or arrives late; transport includes exact current media/session and ACK, does not auto-start another AGY call.
- Real Redmi: actual localized speech audible, original audio mixed rather than replaced without user choice; pause/seek/fast-seek/A->B->A/stop/soundbar SPDIF tested with timestamps and no audible drift. Start target <=5 minutes from TV request until first audible narration is a **target**, not PASS.
- Device fallback: if no mix support or narration late, stable original audio + independently functional Vietsub; no restart or hidden source switch.

**Rollback:** disable narration consumer/TV option and delete only explicitly generated TTS trial data after matching identities; leave existing EN/VI checkpoints, Owner and P4 G2 untouched. No owner restart, paid provider replay, cache deletion, APK install or media transfer is authorized by this source prototype.

Related: #170, #179, #180, #181, #182.


## Implementation checkpoint — 2026-11-23 R1 (Draft PR #183)

1. PR #183 has been integrated **as a stacked merge commit** on exact #179 HEAD `efeff245c98f2100164d037e8fe9e77798ea28cf`, with base `fix/p2-dual-candidates-20261122`. This avoids copying 351 unmerged AGY/P4 files or claiming the merge of #179 is complete. If #179 changes, refresh exact base and rerun changed-path tests before Brain review.
2. `owner_r2_verified_processor.py` now attempts the **existing verified** P4 publisher before offering the same committed revision to a separately injected optional voiceover consumer. If P4 rejects an outdated TV session, the already paid P2 batch can still be voiced locally, but no P4 revision is delivered to the stale session. The original R2 checkpoint worker and provider invocation remain unchanged.
3. `p3_owner_state_wiring_r2.py` accepts an **optional** `voiceover_consumer` injection. Default remains `None`: no VieNeu activation on an existing Windows Owner simply because this PR exists. The Owner entrypoint does **not** yet construct or opt in a production VieNeu consumer; there is no boot-time model download or new task.
4. `voiceover_fanout.py`: one bounded local audio scheduling slot, coalescing cumulative revisions, P4 priority, separate film keys; `VieNeuBatchConsumer` emits each finished cue to an optional callback without waiting for the full 50/120-cue batch. This callback is a narrow seam for future **authorized** session-gated transport, not a live TV route.
5. `voiceover_audio_store.py`: 48 kHz mono PCM16 `.wav` under private absolute root, hashed success receipts, no-clobber creation, durable `.inflight` unknown-effect stop, and reuse for the exact text/timeline/voice/film. It does not store subtitle or audio in GitHub artifacts.
6. `voiceover_signed_offer.py`: signed **metadata** offer, scoped to paired P4 session, media key, English source, subtitle revision, TTS cue key and verified WAV hash. Pure receiver contract rejects stale session, wrong media, OFF and tampering, without asserting Android audio apply. It deliberately does **not** put binary WAV in the existing `SignedSubtitleOffer` envelope.

**Current status / explicit missing consumers:** source-only CIs pass for this prototype, but Windows VieNeu runtime, actual pinned source/APK, a same-listener authenticated audio-GET route, PCM/AudioTrack overlay on native OMP/VLC, SPDIF mix, pause/seek/volume ducking and real Redmi audio ACK are **NOT EXECUTED**. No actual audio has been delivered to or heard on Redmi. Model license and private weight installation need a separate recorded benchmark. An HMAC-valid audio manifest is not proof of an Android receiver.

### Future deployment boundary

- First pin the installed Owner/AGY source to the accepted #179 + #183 combined tree, verify no uncertain P2 call is in flight, and check the target TV/Owner session; do not restart an active translation.
- Provision VieNeu only under Owner-private Windows runtime, with explicit, selected voice and model/weight license verified. For a local preview, instantiate `VieNeuBatchConsumer(VoiceoverWavStore(private_root), VieNeuOnnxSession(voice=...), voice_id="v3turbo_onnx_<pinned_weight_revision>")`, then inject `DualSubtitleVoiceConsumer(..., voice_sink=..., voice_id=same)` into `compose_owner_redmi_status`. The `subtitle_sink` on that class is not used if the integrated R2 processor calls its `offer` method; existing P4 remains authoritative.
- Audio segment/manifest HTTP must be added to the **existing P3/P4 HTTPS listener**, not a second server, and gated on the current signed TV session and viewer's audio choice. No unauthenticated LAN audio URLs or public GitHub binary transfer.
- A small actual OMP audio-overlay proof on the user's Redmi + SPDIF is required before automatically enabling voice. If native separate audio is impossible, benchmark FFmpeg segment mix with direct video-copy, not GStreamer. An audio TTS job should never block the P4 subtitle hot reload.
