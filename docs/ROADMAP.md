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
| P2 | Lawful source search intelligence, metadata/filter/rank (resolution/size/seeds/codec/vi) | P0 + source/ToS proof | Search smoke + candidate confidence + explicit confirmation |
| P3 | Torrent TV local gateway + TV pairing/control + optional ChatGPT interface | P2, real TV API proof, security review | Real E2E search→confirm→TorrServer→TV + negative tests |
| P4 | Opt-in AI Vietsub offline: ASR/dịch/QA/SRT | P1, lawful media + compute | QA tiếng Việt, cue sync, provenance, measured cost |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## Research-aligned incremental backlog (not dispatched)

1. **R0 — Evidence pin:** OMP and 2160 vendor SHA, license/credential audit, clean APK build; exact Redmi A Pro 55 China firmware/ABI/codecs/Cast; deployed TorrServer version/API/auth. No source or firmware proof by product name.
2. **R1 — Direct playback:** legal torrent/video fixture, TorrServer Windows LAN -> OMP TV, start/seek/resume/audio/UTF-8 subtitle; measure real buffer/rebuffer. Remux/HLS -gst optional only after version/build checks.
3. **R2 — Discovery/verification:** retain OMP website adapters; optional Torznab/Prowlarr/Jackett and lawful source policy, distinct reported/scraped/connected seed provenance, explicit 2K pixel policy and ffprobe. Gate G-VERIFY.
4. **R3 — Gateway/session:** candidate, role/permissions, idempotent FSM, adaptive readiness, authenticated pairing/device status; Python FastAPI/Pydantic + SQLite is candidate stack, not an irreversible decision. Gate G-GATEWAY.
5. **R4 — OMP TV extension:** session ID + short-lived ticket + authorized manifest, native player deep-link/WSS/MediaSession only after OMP/device proof. No separate Kotlin/Compose app; Cast Connect conditional. Gate G-AGENT.
6. **R5 — Vietnamese:** embedded vi audio / P1 external SRT first; licensed multilingual ASR -> MT -> TTS -> duck/mix **batch**, test sync/seek/quality/privacy/cost. Gate G-AUDIO-BATCH.
7. **R6 — Advanced optional:** rolling look-ahead 30–60s with seek/catch-up fallback; ChatGPT semantic MCP after official private connectivity/auth verification, no raw TorrServer /mcp; no realtime target. Gates G-ROLLING, G-MCP.

**Recommended sequence:** OMP/direct play -> discovery/verifier -> Gateway/control -> existing VI audio + batch voice-over -> rolling -> optional ChatGPT MCP. Manual playback and existing P1 work do **not** require the optional AI layers.

**Timeline caution:** Research estimated 6–10 weeks / 54–103 person-days for a broad POC *including development of a separate native TV app*. This estimate cannot be copied unchanged into the OMP-first project and is not a commitment. The 2–4-week POC below is a smaller playback-first slice only. See RESEARCH_ALIGNMENT_2026-10-28.md and proposed ADR-0008.

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
