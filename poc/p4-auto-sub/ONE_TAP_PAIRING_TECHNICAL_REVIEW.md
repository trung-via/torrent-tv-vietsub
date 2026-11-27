# One-tap Vietsub AI — P4 technical review
2026-11-12 | DRAFT, for engineering review. Independent Torrent TV; OMP-first.

## Pinned evidence

- G2 PR #115 on b0994c7: Human-reported 8/8 manual Thor tests PASS, not automatic delivery.
- P2 PR #118 on 5eddf77: configurable Gemini 3.8 Flash / Medium LEAN120, max 120 cues / 6500 chars / +/-4 read-only cues, cumulative SRT/VTT and signed feed. Mock API/transport only.
- P4 PR #120: signed receiver, G1 private bytes import, G2 first-frame ACK, bounded Android RFC1918 pull client. The composed Android Gradle PASS at 16a2a984 (Actions #43066156626) predates new opt-in repair.
- OMP upstream 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f, 2160 submodule 6ba6edd39f5d986ddfae29b5425b8ac0b319844e.
- OMP PlayerActivity has a native D-pad AlertDialog menu and subtitle picker; extend those, not a separate Kotlin/Compose client.
- OMP Android manifest already declares INTERNET and its network_security_config.xml currently enables base cleartext for legacy localhost/TorrServer. So global Android 9 defaults alone do not prove LAN requests are blocked. Release security still needs review.
- The existing OMP Phone RPC's 128-bit token is for another scope; do not silently reuse it for P4.
- References: https://developer.android.com/privacy-and-security/security-config ; https://developer.android.com/develop/adaptive-apps/guides/tv/build-adaptive-apps-for-tv ; https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash .

## Final intended interaction

1. Pair PC and TV **once** with a strong random, device-scoped credential and validated PC identity, stored privately on the TV with a revoke path. Prefer phone-assisted QR/token transfer plus a short confirmation code over typing 256 bits with D-pad.
2. On the playing film, user selects a single focusable menu entry **Bật Vietsub AI**. The active media key and selected source must match the PC's authorized timed English subtitle. If source is missing, report SOURCE_MISSING; do not invent dialogue or auto-launch ASR without a separate gate.
3. Windows PC runs configurable API LEAN120, validates exact ID/time/glossary and publishes cumulative revisions 1-120, 1-240, 1-360, etc. No per-batch Human selection.
4. TV pulls the latest only for the paired film, verifies source/media/session identity and signed version, stages G1 app-private bytes, uses G2 in-place VLC reload and acknowledges ONLY after the correct first frame. Preserve audio, position, pause and ON/OFF/OTHER preference.
5. Explicit Tắt Vietsub AI or selecting OFF/OTHER revokes auto-updates. Do not silently resume on another film or after activity/process restart.

## Architecture selection

Use a PC-owned P2 feed and TV **outbound pull**, not a TV socket/listener or TorrServer admin/MCP. Do not expose WAN/router/UPnP. One-time pairing secret should be device-scoped and cryptographically strong, with per-media/source/session keys derived from it; no model ID is hardcoded. Use a signed, monotonically versioned offer with bounded size.

Current P2 Draft serves Base64 subtitles over HTTP on the trusted private LAN; HMAC authenticates the revision but does NOT encrypt subtitle content or authenticate readers. An opaque URL alone is not reader authentication. For production, design HTTPS with explicit identity/pinning, authenticated access, or an equivalent verified secure channel. Never disable all Android TLS checks or trust-all certificates. A 6-digit PIN alone must not serve as the long-term HMAC key; require expiry, attempt limits and explicit confirmation if short-code pairing is used.

Host owns Gemini API key, model profile and subtitles. TV never receives the API key or raw magnet/admin credentials. Reject replays and incorrect episode/source even if the HMAC was valid for another session.

## Evidence gates

| Gate | Acceptance | 2026-11-12 status |
| --- | --- | --- |
| A - first-batch AI consent | Explicit ON before any saved G1 SRT; OFF/OTHER cancels | Source repair in PR #120, CI pending |
| B - durable pairing | One-time strong key, host validation, revoke and negative tests | NOT IMPLEMENTED |
| C - source/session mapping | Film media key bound to authorized SRT/VTT and source hash | Pure contract only; live mapping NOT RUN |
| D - real API | Configurable provider and Gemini 3.8 Flash Medium real call, exact cue QA | Mock PASS; live NOT RUN |
| E - LAN transport | Real authenticated private PC/TV exchange, retry and timeouts | Source only, no real network |
| F - player | Exact-head composed Android Gradle, first-frame ACK and rollback | Prior head PASS; new repair needs CI |
| G - single-button UI | Native OMP D-pad Bật/Tắt Vietsub AI and statuses, no per-batch picker | NOT IMPLEMENTED |
| H - Redmi E2E | Synthetic 120 to 240, cue 131, OFF/OTHER, seek, A to B to A, pause/reopen, recovery | NOT RUN |
| I - G4 release | Signed release isolation, GPL/source and safe rollback | NOT RUN |

## Known blocking defects and order of repair

1. **First batch:** existing G1 automaticChoice originally requires selection ON, which exists only after manual import; explicit AI consent must create ON before the first SRT. Strictly require AI opt-in to import and revoke on manual OFF/OTHER. This repair is in progress.
2. **Rollback transaction:** G2RefreshRecovery.restoreOldFile restores the old subtitle file, but explicitly does **not** restore G1 registry metadata. A failed auto-update must reverse both old bytes and registry pointer without undoing a user's OFF/OTHER choice. Current rollback is not sufficient to call this gate PASS.
3. **Durable replay:** native P4 receiver stores last version only in memory. A process restart then receiving a previously valid signed older revision must be rejected by an app-private per media/source/version ledger, committed only after first-frame confirmation.
4. **One-time pairing/UX:** user must not paste a long per-film secret on every playback. Build a device-level pairing bootstrap, store and revoke it securely, derive movie sessions, expose one D-pad button and status without adding a parallel app.
5. **Source:** P2 cannot guarantee automatic subtitles without timed source SRT/VTT; add PC-selected per-film source matching and a clear missing-source fallback. ASR-on-demand is a separate task, not a silent default.
6. **LAN proof:** test real PC service binding and TV request with synthetic files, focus on auth, relay/malformed packets, reconnect and timeout. Do not open router or firewall as a side effect of CI.
7. **Real TV:** require one consolidated owner-accepted checklist, not repeated individual Thor questions. G2 manual acceptance and Gradle CI cannot be reused as proof of P4 no-picker.
8. **Release:** keep #115, #118, #120 Draft and unmerged until reviews; G4 and licensing separate.

No network service, firewall, ADB, TV application install, actual Gemini call, real subtitle upload, release or merge is authorized/claimed by this review.
