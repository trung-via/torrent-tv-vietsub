# Roadmap v3.2 (proposed) — Torrent TV Vietsub OMP-first, research-aligned

**Ngày:** 2026-10-28 · **Bổ sung P3-MOBILE:** 2026-11-14 (Human-directed, Draft PR review only)  
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
| P3-MOBILE | **Android Mobile Companion**: dùng OMP upstream trên điện thoại để quản lý thư viện/tìm kiếm và gửi yêu cầu thêm torrent hợp lệ vào **TorrServer Windows sẵn có**, tùy chọn ghép Redmi OMP Vietsub làm remote; không viết app Kotlin mới hoặc chạy TorrServer không mật khẩu trên điện thoại | P0 Windows TorrServer LAN, OMP upstream Android APK có provenance; TV remote phụ thuộc compatibility với bản OMP Debug tùy biến | G-MOBILE-INSTALL (APK/ABI/signature), G-MOBILE-SERVER (discovery/library), G-MOBILE-ADD (một lệnh owner-confirmed), G-MOBILE-TV (mã ghép đôi/remote thật) **độc lập** |
| P4 | Integrate P2-AISUB Vietsub outputs into OMP TV UX (not a duplicate CLI PoC) | P1a-G1 real external subtitle import and rights/consent | Real Redmi selected track/reopen/seek/cue sync with generated SRT/VTT |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## P3-MOBILE — OMP Android Phone Companion (bổ sung ngày 2026-11-14)

**Quyết định Human:** xây dựng nhánh cấu hình điện thoại Android độc lập với P2 OpenSubtitles/Gemini và P4 auto Vietsub. Tận dụng OMP upstream thay vì tạo app điện thoại mới, dùng TorrServer trên Windows PC làm server duy nhất; điện thoại là client, Redmi A Pro 55 là TV client. Trạng thái nhánh đầu tiên: `SOURCE_SETUP_CANDIDATE`, không mặc nhiên đã cài hay kết nối thành công.

**Lý do tái sử dụng:** Upstream OMP `spacesarmat/omp` tài liệu chính thức hỗ trợ Android 8+, cùng dòng APK Android TV/phone, library/search và remote TV; Android TV hiển thị mã ghép đôi 6 chữ số trong phần kết nối điện thoại. Bản phát hành được xác minh khi lập kế hoạch là `v0.30.0` (2026-11-11); các phiên bản sau phải xác minh lại khi cài. Source-pin OMP trong các PR G1/G2/P4 trước đó khác release upstream mới, vì vậy **không coi ghép đôi với OMP Debug Vietsub là đã PASS**.

**Đường triển khai và gates:**
1. **M0 / Phone Install:** kiểm tra Android API/ABI, lấy APK từ GitHub Releases chính thức, xác nhận nguồn/phiên bản và checksum tại thiết bị owner; không download hoặc ký lại APK trong repo public. Android 8+ và arm64 nếu thiết bị thật hỗ trợ. Gate `G-MOBILE-INSTALL`.
2. **M1 / Windows TorrServer:** điện thoại và laptop trong cùng mạng riêng LAN/Wi-Fi; nhập thủ công host Windows hiện hữu hoặc chọn `Find in network`, kiểm tra **chỉ đọc** library. Công cụ tiền kiểm Windows không mở firewall/port/service hoặc ghi bí mật. Gate `G-MOBILE-SERVER`.
3. **M2 / Library & authorized add:** thử duy nhất một nguồn có quyền sử dụng, owner xác nhận trước khi gửi thêm torrent; xác nhận nó xuất hiện trên TorrServer và TV. Không tự chạy search/crawler hay tải nội dung trong CI. Gate `G-MOBILE-ADD`.
4. **M3 / Phone↔TV remote:** TV OMP Debug hiện tại phải thực sự có `Connect phone`/mã 6 chữ số; ghép trong cùng LAN và thử start/play/pause/seek/track. Nếu TV build tùy biến không tương thích protocol, đặt `COMPATIBILITY_BLOCKED`; **không ghi đè** TV APK G1/G2/P4 bằng OMP upstream hoặc bật ADB để sửa tắt. Gate `G-MOBILE-TV`.
5. **M4 / Future Gateway integration:** sử dụng mobile client như một điểm vào `P3` đã xác thực; chỉ khi có bằng chứng schema/permissions/consumer. Không nối riêng qua AIOS, không dựng app mới hay nhập private credentials vào GitHub.

**Handoff:** [Issue #138](https://github.com/trung-via/torrent-tv-vietsub/issues/138); hướng dẫn [Mobile Companion Android setup](mobile-companion/ANDROID_PHONE_SETUP.md). Các gate `G-MOBILE-*` phải ghi evidence theo phiên bản APK/observer/server/TV và không được suy từ unit test, README hoặc build artifact.

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
