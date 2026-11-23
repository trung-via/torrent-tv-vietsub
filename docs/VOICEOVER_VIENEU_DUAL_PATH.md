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
