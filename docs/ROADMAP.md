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
| P2-SOURCE | Lawful source search intelligence, metadata/filter/rank (resolution/size/seeds/codec/vi) | P0 + source/ToS proof | Search smoke + candidate confidence + scoped Human authorization (C1.5/C5) |
| P2-AISUB | Human-decided on-demand Vietsub goal in Draft PR #9; translate timed SRT/VTT first, ASR→translation/QA if source text unavailable; offline local-first CLI | Licensed fixtures; no Gateway dependency, TV E2E requires P1a G1 | SRT/VTT UTF-8 cue QA, resource/cost/privacy and user opt-in |
| P3 | Torrent TV local gateway + TV pairing/control + optional ChatGPT interface | P2-SOURCE, real TV API proof, security review | Real E2E search→scoped approval→TorrServer→TV + negative tests |
| P4 | Integrate P2-AISUB Vietsub outputs into OMP TV UX (not a duplicate CLI PoC) | P1a-G1 real external subtitle import and rights/consent | Real Redmi selected track/reopen/seek/cue sync with generated SRT/VTT |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## Giai đoạn 2 — Brain Movie Concierge (quyết định 2026-11-27)

Authority: [Issue #191](https://github.com/trung-via/torrent-tv-vietsub/issues/191), [PR #192](https://github.com/trung-via/torrent-tv-vietsub/pull/192), Project Contract C1.5/C5. Đây là định nghĩa G2 hiện hành, thay phần yêu cầu xác nhận thao tác lặp lại trong backlog cũ và Draft #181; không tuyên bố các phần G1/G3 của #181 đã merge.

**Luồng phẳng:** Human yêu cầu phim → Brain tìm bản phù hợp qua nguồn được phép (EXT.TO là giao diện tra cứu ưu tiên) → Windows Owner/runner gọi TorrServer loopback → OMP Redmi phát khi Human yêu cầu. Prefetch EN→VI là thao tác riêng; giữ opt-in Vietsub/P4 và không tự bật phim nếu chỉ yêu cầu thêm thư viện hoặc prefetch. Không xây player/gateway thứ hai, không mở WAN. Phê duyệt thao tác theo phạm vi đã cấp một lần; quyền nội dung và điều kiện truy cập nguồn theo C1.5/C5.

| Mã | Việc triển khai | Acceptance |
| --- | --- | --- |
| G2.1 | Brain chọn đúng phim/năm/tập và yêu cầu phiên bản; ưu tiên 5–12 GB (mềm), seed reported cao, codec/audio tương thích; yêu cầu cụ thể thắng mặc định. Không hard-code ngưỡng seed hoặc băng thông. | Đúng metadata/release trong phạm vi được phép; báo thiếu dữ liệu hoặc không có bản phù hợp, không tự hạ hard constraints. Seed không bảo đảm tốc độ. |
| G2.2 | Owner/runner thêm bản được phép vào TorrServer localhost theo lệnh Human hoặc phê duyệt thường trực; dedupe hash; không lặp tác dụng chưa rõ. | Readback thư viện, đúng hash/file ID, không trùng; đo thời gian đến Library (≤30 giây là mục tiêu, chưa PASS). |
| G2.3-PREFETCH | Giữ G2.3 prefetch của Draft #181: đọc đúng metadata/hash/fileIndex, phát một TTV-OWNER-VIDEO-EVENT-V4 idempotent nếu prefetch được yêu cầu; checkpoint EN/VI. | Một event hợp lệ, không giả tín hiệu nút TV, không đưa P4 vào session khác. Phụ thuộc G1 real-TV. |
| G2.3-PLAY | Lát remote-play riêng tại #191: tái sử dụng OMP native /omp/info, pairing đã xác minh và /omp/launch; xác định file ID từ metadata; chỉ launch một lần khi được yêu cầu. | ACK không phải playback PASS; đúng video/session và timecode tiến triển trên Redmi thật. Không phá phiên hiện hành; chỉ wake khi trạng thái thực cho phép. |
| G2.4 | Đo throughput/buffer, thời gian vào Library, first frame và prefetch riêng; không đánh đồng các cổng. | Quan sát thực tế, báo từng trạng thái độc lập. |

**Bằng chứng tại 27/11:** wake/OMP API PASS (run 45926363520); pairing runner PASS (45928387586); persisted pairing và library 19 hash PASS (45928931370); remote playback chưa thử vì phim được yêu cầu chưa có trong library (45929619469). Không lặp pairing chỉ vì thay phim. G2.1/G2.2 acquisition/add, G2.3-PREFETCH và G2.3-PLAY end-to-end chưa PASS. Không chờ G1 để kiểm chứng remote-play độc lập, nhưng prefetch/P4 và G3 vẫn cần G1 evidence đúng phạm vi.

## Research-aligned incremental backlog (historical, not dispatched)

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
- Auto-merge PR theo #42 và chính sách trên main; không publish, ký APK, thay đổi Windows/network hoặc điều khiển TV chỉ vì roadmap được duyệt.

## Legacy và trạng thái

`OMP-EVAL-001` vẫn là **planning alias nội bộ**; `TVAPP-001` Kotlin/Compose shell đã bị ADR-0002 supersede. Các nhánh P1/G0/G1 và Draft PR đang mở là công việc có lịch sử riêng, phải review/reconcile trước merge. Trạng thái runner/build/Redmi/TorrServer cần fresh evidence theo commit/run cụ thể; không suy PASS từ tên PR/workflow. Tham chiếu `PROJECT_CONTRACT.md`, `ARCHITECTURE.md` và ADR-0007.
