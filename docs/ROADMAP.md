# Roadmap v3.0 — Torrent TV Vietsub độc lập AIOS

**Ngày:** 2026-10-28  
**Trạng thái:** `DRAFT_FOR_PR_REVIEW`. Đây là backlog riêng của Torrent TV, không phải roadmap/canonical TASK của AIOS. Hướng North Star agent đã được chọn; thứ tự kỹ thuật vẫn phụ thuộc PoC và Deep Research chưa hoàn tất.

| Ưu tiên | Workstream | Phụ thuộc | Exit gate |
| --- | --- | --- | --- |
| P0a | Project governance độc lập: contract/ADR/PRD/architecture, workflow inventory, provenance AIOS reuse, GitHub runner isolation | Human review PR | Không có AIOS admission/dispatch/runtime; repo/runner/PR policy riêng |
| P0b | OMP feasibility: pin upstream + 2160 submodule, GPL/security, website adapters, clean build, APK hash | P0a, authorized runner | G-OMP PASS hoặc blocker có evidence |
| P0c | TorrServer Windows/NAS LAN + Redmi TV: media legal, D-pad, play/seek/resume, Vietsub | P0b, device/server permission | G-SERVER + G-TV + G-VI độc lập |
| P1a | External SRT/VTT capability: G0 debug fixture → G1 ngoài APK → G2 hot-add (nếu khả thi) → G3 sync → G4 release isolation | P0c/player proof | G1 E2E và từng gate riêng; không false PASS |
| P1b | Chọn transport: Android picker/USB, SMB read-only, phone transfer hoặc khác | P1a G1 | Decision matrix + Human ADR; không tự mở SMB/firewall |
| P2 | Lawful source search intelligence, metadata/filter/rank (resolution/size/seeds/codec/vi) | P0 + source/ToS proof | Search smoke + candidate confidence + explicit confirmation |
| P3 | Torrent TV local gateway + TV pairing/control + optional ChatGPT interface | P2, real TV API proof, security review | Real E2E search→confirm→TorrServer→TV + negative tests |
| P4 | Opt-in AI Vietsub offline: ASR/dịch/QA/SRT | P1, lawful media + compute | QA tiếng Việt, cue sync, provenance, measured cost |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## PoC 2–4 tuần (PROPOSED, không cam kết)

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
