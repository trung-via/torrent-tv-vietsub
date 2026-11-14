# Torrent TV Vietsub — PRD v4.1 (independent, OMP-based, research-aligned)

**Ngày:** 2026-10-28  
**Status:** `DRAFT_FOR_PR_REVIEW`. Human đã chốt độc lập AIOS và hướng North Star AI Entertainment Agent; triển khai, hiệu năng và khả năng tương thích chưa tự động được xác minh.  
**Authority:** `PROJECT_CONTRACT.md` v2.0 (sau merge), ADR-0001/0002/0006/0007; ADR-0005 chỉ là lịch sử SMB-first.

## 1. Sản phẩm và đối tượng

Torrent TV Vietsub là ứng dụng xem video gia đình trên Android TV/Google TV/Redmi tương thích, sử dụng TorrServer ngoài TV trên Windows PC/NAS, giữ trải nghiệm OMP và ưu tiên tiếng Việt. Nguồn nội dung phải có quyền sử dụng, kể cả khi truy vấn bằng website adapter/indexer. Dự án có repo, backlog, workflow và runner riêng, **không phải sản phẩm con hoặc agent của AIOS**.

**North Star:** người dùng có thể yêu cầu “tìm video A chất lượng khoảng 2K, 8–12 GB, seeders báo >= 300, phát lên TV, ưu tiên audio/thuyết minh tiếng Việt”; hệ thống giải thích kết quả/độ tin cậy, xin xác nhận trước hành động, phát và báo trạng thái. Đây là **mục tiêu trải nghiệm**, không phải acceptance P0 hay lời khẳng định API/voice-over hiện đã hoạt động.

## 2. Những gì đã quyết định

- **Client/server (OMP FIRST):** dùng **OMP upstream làm codebase chính**, tùy biến Preact/Capacitor UI và native player **có sẵn bên trong OMP** (Kotlin/2160 Player/Media3/VLC); **không viết lại app mới bằng Kotlin + Jetpack Compose + Media3**. TorrServer Windows (default) hoặc NAS (optional), LAN only, không nhúng torrent engine vào APK.
- **Nguồn:** giữ OMP website search adapters, nhập magnet/.torrent và nguồn người dùng cấu hình hợp lệ; không vận hành piracy index/scraper trái phép, không bypass DRM/ToS.
- **Player:** library, series, history, resume, remote D-pad, track audio/subtitle; Việt hóa UI, `vi/vie` và SRT/VTT UTF-8. Kiểm chứng Redmi thật trước PASS.
- **P1:** external subtitle source-agnostic, capability trước transport; SMB/USB/phone chưa chọn default.
- **Vận hành:** GitHub repo PUBLIC theo GitHub 2026-11-14 (PRIVATE/PUBLIC đều hợp lệ; kiểm tra live), dedicated runner/workspace/CI/release riêng. AIOS chỉ là nguồn tham khảo code/workflow sau audit; không có AIOS admission/dispatch/Brain/Runtime.
- **AI:** Windows/NAS optional opt-in; Vietsub trước voice-over; consent, quyền sử dụng, QA, sync và cost gate.

## 3. Hành trình người dùng theo giai đoạn

**Hành trình nền P0/P1:** cài APK tương thích → cấu hình TorrServer LAN → nhập magnet/.torrent hợp pháp hoặc chọn nguồn tìm website có quyền → chọn file/series → phát/tua/resume bằng D-pad → chọn track Việt hoặc external SRT/VTT → nhận lỗi có hướng xử lý.

**Hành trình North Star P2/P3 (PROPOSED):** mô tả nội dung bằng ngôn ngữ tự nhiên → search adapters trả candidates có nguồn và metadata → lọc dung lượng/độ phân giải/seeders/codec/audio → giải thích bất định (“2K”/seeds) → người dùng duyệt bản → gateway riêng Torrent TV yêu cầu TorrServer thêm torrent và điều khiển TV → báo kết quả/trạng thái hoặc rollback.

**Hành trình AI P2-AISUB/P4/P5:** mục tiêu Human là tạo Vietsub theo yêu cầu, ưu tiên dịch timed SRT/VTT theo cue, rồi mới ASR→dịch/QA khi thiếu text. P2-AISUB PoC CLI có thể làm độc lập Gateway; P4 kết nối bản đã tạo với OMP sau G1, P5 mới là TTS/voice-over. Không bắt buộc real-time.

## 4. Yêu cầu theo phase

| Phase | Tính năng | Acceptance |
| --- | --- | --- |
| P0 Foundation | OMP provenance/build, runner riêng, Windows TorrServer, manual magnet, D-pad/player, Vietsub cơ bản | Build hash + legal fixture + real TV/server evidence độc lập |
| P1 Daily use | SRT/VTT ngoài torrent, track binding, reopen, lỗi, UX transport | G0 render ≠ G1 external import ≠ G2 hot-add ≠ G3 sync ≠ G4 release |
| P2-SOURCE Search intelligence | Legal source adapters, metadata, filter/rank, manual confirmation | Candidate source proof, no unauthorized crawling, negative tests |
| P2-AISUB AI Vietsub (Human goal; PR #9 still Draft) | Offline timed SRT/VTT cue translation first; ASR→MT/QA if missing text, opt-in Windows/NAS CLI | Two lawful fixtures; cue timing/QA and resource proof; TV E2E depends on G1 |
| P3 Agent control | Local gateway riêng, permission, TV pairing/play/status, ChatGPT integration optional | Real E2E source→confirmation→TorrServer→TV, auth/audit |
| P4 AI Vietsub integration | Bind the P2-AISUB generated SRT/VTT to correct OMP TV media via verified P1a-G1 | Real Redmi import, selected track auto-render, persistence/seek and cue timing |
| P5 AI voice-over | TTS/align/ducking/mix/mux, optional external audio | Audio sync, pause/seek, resource/latency/cost PoC; real-time riêng |

## 5. Acceptance chi tiết

### P0: không làm giả evidence

- OMP upstream và submodule `2160player` được pin SHA, license/dependencies audit, build clean TypeScript/Android, APK checksum.
- Website source adapters vẫn truy cập được từ UI với test source/fixture hợp pháp; không buộc OMP billing để dùng core search.
- TorrServer Windows/NAS thật: version, API/auth, stream/seek/Range, offline/timeout/no peers.
- Redmi/TV thật: firmware/API/ABI, sideload/launch, remote D-pad/Back, codec, audio, subtitle Unicode, resume.
- Runner workflow: exact repo/branch/runner/isolated workspace; test manual có ủy quyền. YAML tồn tại ≠ job PASS.

### P1: external subtitle

- G0 debug-only local fixture chứng minh VLC render tiếng Việt; không suy ra file ngoài APK.
- G1 file SRT/VTT **ngoài APK**, đúng phim/tập, off/on, pause/seek/reopen, lỗi và persistence không có debug re-injection.
- G2 hot-add, G3 sync với clip/cue chuẩn, G4 release không có debug fixture/hook: các gate riêng.
- Chỉ sau capability chọn transport qua Android picker/USB, SMB read-only, phone transfer hoặc phương án khác; Human duyệt, không tự mở SMB/firewall.

### P2/P3: search/agent

- “2K” phải định nghĩa rõ (ví dụ 2560×1440 hoặc DCI 2048×1080); candidate seeders do indexer báo có timestamp, không bảo đảm peers thật. Size/codec/resolution cần kiểm tra metadata thực.
- Không có hành động add torrent, mở stream hoặc điều khiển thiết bị có side effect nếu thiếu xác nhận/permission; error typed và audit không lộ secret.
- ChatGPT có thể là giao diện intent tùy chọn; gateway của Torrent TV là runtime độc lập. Không giả định ChatGPT có LAN access, không triển khai remote shell.

### P4/P5: media AI

- Chỉ media có quyền dịch/xử lý; consent và chi phí rõ; lưu/xóa file đầu ra có kiểm soát.
- QA translation, timing, subtitle display; voice-over thử mux hoặc external audio với seek/pause và mixing. Không tuyên bố hỗ trợ thuyết minh thời gian thực trước benchmark.

## 5a. Yêu cầu chức năng từ báo cáo (DRAFT, chưa có feature E2E)

| ID | Capability | Acceptance evidence |
| --- | --- | --- |
| FR-INTENT | Structured PlaybackIntent với source, pixel-level resolution, size, seed metric, hard/preference, device, audio policy | 2K ambiguity được xử lý công khai; hard constraints không bị hạ |
| FR-DISCOVERY | OMP website search giữ nguyên; Prowlarr/Torznab option, Jackett fallback | Lawful source allowlist và metadata provenance |
| FR-VERIFY | Reported/scraped/connected seeder metrics, actual media file probe và observed buffer/rate | Không suy độ phân giải/codec từ release name; không gọi seed >=300 là guaranteed speed |
| FR-SESSION | Gateway owned state machine, authorization, idempotency, confirmation, audit, typed errors | Test fail/retry/recover và stop/cleanup |
| FR-READY | Direct-play first, readiness before play, remux/transcode only when needed | Legal fixture actual bitrate/rate/buffer/first frame measured |
| FR-OMP-TV | OMP-based TV device pairing/token/session manifest and play/pause/seek/status | Real Redmi firmware and OMP native player evidence; ADB dev-only |
| FR-AUDIO | Existing VI track first; external Vietsub; batch AI voice-over opt-in; rolling later | Licensed source, alignment/seek/quality/cost/privacy proof |
| FR-MCP | Semantic ChatGPT→Gateway only, not TorrServer native /mcp | Official support/permission verification, auth, consent, no raw admin API |

**Proposed REST sketch, not shipped:** POST /v1/media/search; POST /v1/candidates/{id}/verify; POST /v1/playback/sessions; POST /v1/playback/sessions/{id}/prepare; POST /v1/playback/sessions/{id}/play; POST /v1/playback/sessions/{id}/control; GET /v1/playback/sessions/{id}. Details and negative tests in the research alignment document.

**SLO benchmarks only:** 30–60s buffer, >=1.5× average bitrate sustained rate, <15–30s first frame on healthy swarm, 0 rebuffer / 30min controlled fixture, <1s local command; not measured, not product promises.

## 6. Ngoài phạm vi / giới hạn

Không tự vận hành kho phim lậu, bypass DRM/paywall/captcha, root TV, mở WAN/UPnP, viết BitTorrent engine, nhúng TorrServer binary, viết lại Compose UI trong P0, xây OMP paid billing/bot/VPS, tự động cài Windows service/firewall, đồng bộ AIOS runtime hoặc cho agent thực thi lệnh shell tùy ý. Release và thay đổi host cần Human phê duyệt.

## 7. Tech inventory / dependency

- OMP: `src/api/torrserver.ts`, `src/sources/*`, `src/i18n/*`, `src/lib/tracks.ts`, `src/player/*`, Android player Kotlin, `android/vendor/2160player`. Audit snapshot trước đó `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` không tự chứng minh build sản phẩm.
- TorrServer: upstream ngoài APK; wire schema và version deployed phải probe, xem `TORRSERVER_INTERFACE.md`.
- GitHub Actions và runner: thuộc repo Torrent TV; có thể kế thừa **mẫu** từ AIOS sau provenance/security/license review, không kế thừa AIOS authority.
- P2/P3 gateway/source-ranking, P4/P5 AI worker: thiết kế mới của Torrent TV, chưa phải modules đã có.

## 7a. Bằng chứng đối chiếu với Draft PR hiện có

- PR #37: Human-reported P0 OMP/TorrServer Windows→Redmi video/audio/remote/seek/reopen smoke PASS, scope hẹp, không phủ toàn bộ G-TV/G-SERVER.
- PR #38: Debug/unit Actions run 40533478080 SUCCESS, Human thử import SRT trên Redmi nhưng G1-SUB-01 (saved track không auto-render khi reopen) vẫn FAIL; tốc độ 2–3x G1-PLAY-01 là UNCONFIRMED, không sửa bằng giả định.
- PR #9 giữ mục tiêu AI Vietsub on-demand P2 qua ADR-0004 chưa merge; PR #15 giữ P1 AC-01..08 và style deferred. Roadmap không được xóa các quyết định này.

## 8. Rủi ro và quyết định còn mở

Firmware Redmi nội địa; API TorrServer; source terms; license GPL của OMP và dependencies; credential userinfo trong stream URL; seeders không chính xác; phụ đề rời/hot-add; TV pairing; chi phí/độ trễ voice-over. Tất cả cần proof, ADR và test riêng. Báo cáo Deep Research ngày 2026-10-28 đã hoàn thành và được đối chiếu tại RESEARCH_ALIGNMENT_2026-10-28.md. Định hướng ứng dụng native Kotlin mới trong báo cáo không thay thế quyết định OMP-first. Các tuyên bố upstream/vendor/firmware/chi phí và E2E vẫn UNVERIFIED.

## 9. Next

Audit các Draft PR hiện có, không tự rebase/merge; kiểm chứng workflow/runner hiện hành; thực hiện PoC hợp pháp P0–P1 rồi đánh giá P2/P3. Mọi task là backlog **Torrent TV**, không có TASK ID hay dispatch của AIOS.
