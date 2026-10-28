# Torrent TV Vietsub — PRD v4.0 (independent, OMP-based)

**Ngày:** 2026-10-28  
**Status:** `DRAFT_FOR_PR_REVIEW`. Human đã chốt độc lập AIOS và hướng North Star AI Entertainment Agent; triển khai, hiệu năng và khả năng tương thích chưa tự động được xác minh.  
**Authority:** `PROJECT_CONTRACT.md` v2.0 (sau merge), ADR-0001/0002/0006/0007; ADR-0005 chỉ là lịch sử SMB-first.

## 1. Sản phẩm và đối tượng

Torrent TV Vietsub là ứng dụng xem video gia đình trên Android TV/Google TV/Redmi tương thích, sử dụng TorrServer ngoài TV trên Windows PC/NAS, giữ trải nghiệm OMP và ưu tiên tiếng Việt. Nguồn nội dung phải có quyền sử dụng, kể cả khi truy vấn bằng website adapter/indexer. Dự án có repo, backlog, workflow và runner riêng, **không phải sản phẩm con hoặc agent của AIOS**.

**North Star:** người dùng có thể yêu cầu “tìm video A chất lượng khoảng 2K, 8–12 GB, seeders báo >= 300, phát lên TV, ưu tiên audio/thuyết minh tiếng Việt”; hệ thống giải thích kết quả/độ tin cậy, xin xác nhận trước hành động, phát và báo trạng thái. Đây là **mục tiêu trải nghiệm**, không phải acceptance P0 hay lời khẳng định API/voice-over hiện đã hoạt động.

## 2. Những gì đã quyết định

- **Client/server:** OMP-derived Preact/Capacitor UI + Android Kotlin 2160 Player/Media3/VLC; TorrServer Windows (default) hoặc NAS (optional), LAN only, không nhúng torrent engine vào APK.
- **Nguồn:** giữ OMP website search adapters, nhập magnet/.torrent và nguồn người dùng cấu hình hợp lệ; không vận hành piracy index/scraper trái phép, không bypass DRM/ToS.
- **Player:** library, series, history, resume, remote D-pad, track audio/subtitle; Việt hóa UI, `vi/vie` và SRT/VTT UTF-8. Kiểm chứng Redmi thật trước PASS.
- **P1:** external subtitle source-agnostic, capability trước transport; SMB/USB/phone chưa chọn default.
- **Vận hành:** GitHub repo PRIVATE, dedicated runner/workspace/CI/release riêng. AIOS chỉ là nguồn tham khảo code/workflow sau audit; không có AIOS admission/dispatch/Brain/Runtime.
- **AI:** Windows/NAS optional opt-in; Vietsub trước voice-over; consent, quyền sử dụng, QA, sync và cost gate.

## 3. Hành trình người dùng theo giai đoạn

**Hành trình nền P0/P1:** cài APK tương thích → cấu hình TorrServer LAN → nhập magnet/.torrent hợp pháp hoặc chọn nguồn tìm website có quyền → chọn file/series → phát/tua/resume bằng D-pad → chọn track Việt hoặc external SRT/VTT → nhận lỗi có hướng xử lý.

**Hành trình North Star P2/P3 (PROPOSED):** mô tả nội dung bằng ngôn ngữ tự nhiên → search adapters trả candidates có nguồn và metadata → lọc dung lượng/độ phân giải/seeders/codec/audio → giải thích bất định (“2K”/seeds) → người dùng duyệt bản → gateway riêng Torrent TV yêu cầu TorrServer thêm torrent và điều khiển TV → báo kết quả/trạng thái hoặc rollback.

**Hành trình AI P4/P5 (PROPOSED):** người dùng opt-in cho media có quyền → xử lý ASR/dịch/QA tạo `.vi.srt` → kiểm tra thời gian và hiển thị → tùy chọn TTS/align/mix/mux audio Việt → xem trước và đo sync, seek, chi phí. Không bắt buộc real-time.

## 4. Yêu cầu theo phase

| Phase | Tính năng | Acceptance |
| --- | --- | --- |
| P0 Foundation | OMP provenance/build, runner riêng, Windows TorrServer, manual magnet, D-pad/player, Vietsub cơ bản | Build hash + legal fixture + real TV/server evidence độc lập |
| P1 Daily use | SRT/VTT ngoài torrent, track binding, reopen, lỗi, UX transport | G0 render ≠ G1 external import ≠ G2 hot-add ≠ G3 sync ≠ G4 release |
| P2 Search intelligence | Legal source adapters, metadata, filter/rank, manual confirmation | Candidate source proof, no unauthorized crawling, negative tests |
| P3 Agent control | Local gateway riêng, permission, TV pairing/play/status, ChatGPT integration optional | Real E2E source→confirmation→TorrServer→TV, auth/audit |
| P4 AI Vietsub | ASR/translation/QA offline opt-in, subtitle output | Chất lượng Việt, cue timing, provenance, consent, measured cost |
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

## 6. Ngoài phạm vi / giới hạn

Không tự vận hành kho phim lậu, bypass DRM/paywall/captcha, root TV, mở WAN/UPnP, viết BitTorrent engine, nhúng TorrServer binary, viết lại Compose UI trong P0, xây OMP paid billing/bot/VPS, tự động cài Windows service/firewall, đồng bộ AIOS runtime hoặc cho agent thực thi lệnh shell tùy ý. Release và thay đổi host cần Human phê duyệt.

## 7. Tech inventory / dependency

- OMP: `src/api/torrserver.ts`, `src/sources/*`, `src/i18n/*`, `src/lib/tracks.ts`, `src/player/*`, Android player Kotlin, `android/vendor/2160player`. Audit snapshot trước đó `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` không tự chứng minh build sản phẩm.
- TorrServer: upstream ngoài APK; wire schema và version deployed phải probe, xem `TORRSERVER_INTERFACE.md`.
- GitHub Actions và runner: thuộc repo Torrent TV; có thể kế thừa **mẫu** từ AIOS sau provenance/security/license review, không kế thừa AIOS authority.
- P2/P3 gateway/source-ranking, P4/P5 AI worker: thiết kế mới của Torrent TV, chưa phải modules đã có.

## 8. Rủi ro và quyết định còn mở

Firmware Redmi nội địa; API TorrServer; source terms; license GPL của OMP và dependencies; credential userinfo trong stream URL; seeders không chính xác; phụ đề rời/hot-add; TV pairing; chi phí/độ trễ voice-over. Tất cả cần proof, ADR và test riêng. Kết quả Deep Research khi hoàn tất sẽ được xem như **đầu vào review**, không tự ghi đè contract hoặc thay status UNVERIFIED.

## 9. Next

Audit các Draft PR hiện có, không tự rebase/merge; kiểm chứng workflow/runner hiện hành; thực hiện PoC hợp pháp P0–P1 rồi đánh giá P2/P3. Mọi task là backlog **Torrent TV**, không có TASK ID hay dispatch của AIOS.
