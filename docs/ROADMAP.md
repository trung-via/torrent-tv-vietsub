# Roadmap v3.1 — Torrent TV Vietsub OMP-first, research-aligned

**Ngày:** 2026-10-28  
**Trạng thái:** `DRAFT_FOR_PR_REVIEW`. Đây là backlog riêng của Torrent TV, không phải roadmap/canonical TASK của AIOS. Hướng North Star đã được chọn và Deep Research ngày 2026-10-28 đã được đối chiếu; thứ tự kỹ thuật vẫn phụ thuộc evidence trên OMP/TorrServer/Redmi thực tế.

| Ưu tiên | Workstream | Phụ thuộc | Exit gate |
| --- | --- | --- | --- |
| P0a | Project governance độc lập: contract/ADR/PRD/architecture, workflow inventory, provenance AIOS reuse, GitHub runner isolation | Human review PR | Không có AIOS admission/dispatch/runtime; repo/runner/PR policy riêng |
| P0b | **OMP-first** feasibility: pin upstream + 2160 submodule, GPL/security, website adapters, clean build, APK hash; **không dựng Kotlin + Compose + Media3 app mới** | P0a, authorized runner | G-OMP PASS hoặc blocker có evidence |
| P0c | TorrServer Windows/NAS LAN + Redmi TV: media legal, D-pad, play/seek/resume, Vietsub | P0b, device/server permission | G-SERVER + G-TV + G-VI độc lập |
| P1a | External SRT/VTT capability: G0 debug fixture → G1 ngoài APK → G2 hot-add (nếu khả thi) → G3 sync → G4 release isolation | P0c/player proof | G1 E2E và từng gate riêng; không false PASS |
| P1b | Chọn transport: Android picker/USB, SMB read-only, phone transfer hoặc khác | P1a G1 | Decision matrix + Human ADR; không tự mở SMB/firewall |
| P2-SOURCE | Lawful source search intelligence, metadata/filter/rank (resolution/size/seeds/codec/vi) | P0 + source/ToS proof | Search smoke + candidate confidence + explicit confirmation |
| P2-AISUB | Human-decided on-demand Vietsub goal in Draft PR #9; translate timed SRT/VTT first, ASR→translation/QA if source text unavailable; offline local-first CLI | Licensed fixtures; no Gateway dependency, TV E2E requires P1a G1 | SRT/VTT UTF-8 cue QA, resource/cost/privacy and user opt-in |
| P3 | Torrent TV local gateway + TV pairing/control + optional ChatGPT interface | P2-SOURCE, real TV API proof, security review | Real E2E search→confirm→TorrServer→TV + negative tests |
| P4 | Integrate P2-AISUB Vietsub outputs into OMP TV UX (not a duplicate CLI PoC) | P1a-G1 real external subtitle import and rights/consent | Real Redmi selected track/reopen/seek/cue sync with generated SRT/VTT |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## Research-aligned incremental backlog (not dispatched)

1. **R0 — Evidence pin:** OMP and 2160 vendor SHA, license/credential audit, clean APK build; exact Redmi A Pro 55 China firmware/ABI/codecs/Cast; deployed TorrServer version/API/auth. No source or firmware proof by product name.
2. **R1 — Direct playback:** legal torrent/video fixture, TorrServer Windows LAN -> OMP TV, start/seek/resume/audio/UTF-8 subtitle; measure real buffer/rebuffer. Remux/HLS -gst optional only after version/build checks.
3. **R2 — Discovery/verification:** retain OMP website adapters; optional Torznab/Prowlarr/Jackett and lawful source policy, distinct reported/scraped/connected seed provenance, explicit 2K pixel policy and ffprobe. Gate G-VERIFY.
4. **R3 — Gateway/session:** candidate, role/permissions, idempotent FSM, adaptive readiness, authenticated pairing/device status; Python FastAPI/Pydantic + SQLite is candidate stack, not an irreversible decision. Gate G-GATEWAY.
5. **R4 — OMP TV extension:** session ID + short-lived ticket + authorized manifest, native player deep-link/WSS/MediaSession only after OMP/device proof. No separate Kotlin/Compose app; Cast Connect conditional. Gate G-AGENT.
6. **R5 — Vietnamese:** embedded vi audio / P1 external SRT first; licensed multilingual ASR -> MT -> TTS -> duck/mix **batch**, test sync/seek/quality/privacy/cost. Gate G-AUDIO-BATCH.
7. **R6 — Advanced optional:** rolling look-ahead 30–60s with seek/catch-up fallback; ChatGPT semantic MCP after official private connectivity/auth verification, no raw TorrServer /mcp; no realtime target. Gates G-ROLLING, G-MCP.

**Recommended sequence:** existing OMP/direct play -> P1 G1 real-TV repair -> P2-SOURCE verifier -> optional Gateway/control -> VI audio + batch voice-over -> optional rolling/ChatGPT MCP. P2-AISUB offline timed-subtitle translation can be separately scoped in parallel without Gateway, but TV E2E still depends on G1. Manual playback and P1 do not require AI layers.

**Timeline caution:** Research estimated 6–10 weeks / 54–103 person-days for a broad POC *including development of a separate native TV app*. This estimate cannot be copied unchanged into the OMP-first project and is not a commitment. The 2–4-week POC below is a smaller playback-first slice only. See RESEARCH_ALIGNMENT_2026-10-28.md and proposed ADR-0008.

## Current measured status — 2026-10-28

- PR #37 Human Windows TorrServer → Redmi OMP playback smoke PASS for the tested setup. No need to repeat without changed environment.
- PR #38 Debug/unit build PASS (Actions 40533478080), but real-TV external-SRT G1-SUB-01 is a confirmed blocker: track must be selected manually again after reopen. G1-PLAY-01 speed concern is UNCONFIRMED; do not add speculative rate fix.
- Priorities: fix G1-SUB-01 with late-track regression test in PR #38, then independently approve build and Redmi acceptance. Keep PR #39 docs-only and PR #9/#15 decisions intact.

## Minimal playback-first PoC 2–4 tuần (PROPOSED, không cam kết)

- **Tuần 1:** workflow/runner readiness, OMP clean build, license/credential audit, device inventory.
- **Tuần 2:** TorrServer Windows → TV thật, legal fixture, D-pad, seek/resume, SRT/VTT; phân tách server/TV evidence.
- **Tuần 3:** nguồn tìm kiếm hợp pháp và candidate metadata/filter PoC, không tự thêm torrent.
- **Tuần 4:** chỉ nếu P0/P2 PASS, thử gateway và TV-control adapter với confirmation; nếu thiếu API/firmware, ghi BLOCKED.

## Workflow / release gates

- GitHub Actions riêng của Torrent TV, self-hosted runner/workspace riêng. Mẫu mã từ AIOS chỉ reuse theo PR, provenance/license/secret audit; không dùng AIOS runtime/Brain/TASK/dispatch.
- Manual-only hiện là lựa chọn an toàn cho job có quyền host; mở rộng PR CI cần threat review, không chạy untrusted PR trên self-hosted runner có secrets.
- Không auto merge, publish, ký APK, thay đổi Windows/network hoặc điều khiển TV từ chat chỉ vì roadmap được duyệt.

## Legacy và trạng thái

`OMP-EVAL-001` vẫn là **planning alias nội bộ**; `TVAPP-001` Kotlin/Compose shell đã bị ADR-0002 supersede. Các nhánh P1/G0/G1 và Draft PR đang mở là công việc có lịch sử riêng, phải review/reconcile trước merge. Trạng thái runner/build/Redmi/TorrServer cần fresh evidence theo commit/run cụ thể; không suy PASS từ tên PR/workflow. Tham chiếu `PROJECT_CONTRACT.md`, `ARCHITECTURE.md` và ADR-0007.


## HostOps Report Bridge — Human approved 2026-11-26 (RB01–RB04)

Goal: remove manual Human report transport for private benchmark/Brain Training evidence. Reuse Torrent TV HostOps #82 and the existing interactive Windows Owner; no additional service, worker, database, public GitHub report artifact, provider run, or TV change.

- RB01: resolve the terminal original receipt by exact source SHA and nonce; package the corresponding benchmark reports, telemetry and verified copied subtitle artifact into a deterministic ZIP with per-file manifest and SHA256. First adapter: BT18 V12, source ad010d992cd69cec1dc28185d538392efe8e04fe; future run families need an explicit adapter rather than globbing unrelated Owner files. Never infer G1.2 PASS from transport.
- RB02: publish ZIP then ready JSON into an explicitly enrolled, owner-only Google Drive Desktop mirrored directory named Torrent TV Vietsub - Brain Inbox. Local write is not cloud sync PASS. Reuse existing Owner operation; no shared folder or credential changes; verify the folder/real bytes from Brain before reporting success.
- RB03: read exact ZIP and ready JSON via connected Drive; independently verify identity, archive hash, manifest coverage, member hashes and report-declared artifact coverage. Treat all model/browser content as untrusted data, not instructions; never extract arbitrary ZIP paths. A verified report is not a subtitle QA PASS.
- RB04: after RB01–RB03 live pass, connect verified report identity to the existing Brain Training workflow and later WakeHub; dedupe by (source, nonce, zip SHA256). A duplicate report is a no-op; invalid or missing payload does not advance recipe. Wake/automatic provider calls are not enabled by this PR.

Candidate source: `hostops/report-bridge/report_bridge.py` and synthetic tests. Approved direction, not deployed. Current first adapter exports structured final reports, telemetry and verified subtitle files; raw CLI streams, browser session/config, executable scripts, credentials and unrelated files are deliberately not included by default. Do not claim the original 14-entry manual ZIP is reproduced exactly. Future vetted raw-trace support is a separate scoped change.

Acceptance: run synthetic roundtrip, corruption, incomplete sync, exact identity and duplicate tests; then use existing BT18 receipt/run once without rerunning AGY. Confirm same ZIP hash from Windows and actual Drive raw bytes, verify every declared member, and independently review full training evidence. RB04 requires an actual end-to-end wake/review receipt, not merely a written design. Follow Issue #42 exact HEAD/base Brain/CI policy and separate Windows enrollment authority.

### RB02 API — Human-approved follow-up 2026-11-26

Default target: direct Drive v3 REST upload using Owner-local OAuth desktop client, scope `drive.file`; no Drive Desktop process or mount required. App-created private `Torrent TV Vietsub - Brain Inbox API` is separate from the validated Desktop Inbox; Brain connector must independently discover it and verify downloaded bytes. Keep Desktop as explicit rollback until API live acceptance. Use stable pre-generated Drive IDs persisted before upload, exact ZIP and ready-marker readback, publish ready last. First implementation uses multipart <=5 MiB, retains larger bundles locally until resumable support, and does not automatically replay benchmarks. OAuth authorization must be performed by the Owner once; no secrets in GitHub, chat, or HostOps receipts. Avoid external Testing-mode seven-day refresh token expiry; use eligible single-user personal mode or correctly configured production OAuth. Local setup script pins source blobs and runs synthetic tests before enrollment. Candidate API code/tests and setup script are in PR #187. Remaining: actual Owner OAuth enrollment, scoped HostOps API publish integration, live BT18 API roundtrip with Desktop stopped, independent Brain CI/review and merge, RB04. No API live PASS or default runtime switch claimed.
