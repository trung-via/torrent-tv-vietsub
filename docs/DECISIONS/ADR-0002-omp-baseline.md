# ADR-0002 — Chọn OMP làm nền tảng ứng dụng TV, giữ nguồn tìm torrent website

**Ngày:** 2026-10-25  
**Status:** ACCEPTED — Human-approved product direction; technical feasibility UNVERIFIED  
**Supersedes:** phần triển khai client Kotlin + Compose for TV mới của baseline v1; **không thay thế** ADR-0001 về Windows/NAS + TorrServer.

## Context

Audit read-only OMP tại upstream `spacesarmat/omp` commit `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` (snapshot khảo sát, không phải pin build đã xác minh). OMP đã có TypeScript/Preact + Capacitor UI; Android Kotlin native player, 2160 Player/Media3 và VLC; TorrServer API client, remote, library, audio/subtitle/series, tìm torrent qua website và các indexer. Dự án hiện docs-first, repo PRIVATE; chưa có APK/TV/server E2E.

## Decision (`DECIDED`)

1. Kế thừa OMP làm codebase sản phẩm; **không** khởi tạo Compose for TV mới ở P0.
2. Giữ Windows/NAS TorrServer qua LAN; không bundle server engine trong APK.
3. **Giữ website torrent search**: không mặc định gỡ/tắt các adapters nguồn website upstream; giữ tìm kiếm theo yêu cầu và khả năng cấu hình nguồn phù hợp (Jackett/Prowlarr/TorrServer). Chỉ sử dụng nội dung và nguồn có quyền; không xây kho phim vi phạm quyền, scraping trái phép, bypass DRM/giới hạn truy cập.
4. Ưu tiên tiếng Việt: UI `vi`, audio/subtitle `vi/vie`, UTF-8 SRT/VTT, fallback phụ đề phức tạp cần test.
5. Giữ OMP remote/library/resume/player. Billing/paid-service backend, VPS/bot, theo dõi chạy nền, phone-local TorrServer, autostart TV và quyền Android rộng không thuộc đường vận hành mặc định của MVP; chỉ tắt/tách sau dependency analysis, **không làm hỏng website search**.
6. AI Vietsub/thuyết minh là P2 opt-in; PoC sync/mux audio trên Windows/NAS trước khi tích hợp tính năng thật.
7. Giữ codebase PRIVATE tới khi Human quyết định phát hành; khi lấy mã OMP tuân thủ GPL-3.0-only và các license phụ thuộc.

## Consequences

- Mạnh: giữ được thư viện/remote/player/subtitle và giảm nhu cầu dựng player mới.
- Đổi chi phí kỹ thuật sang review upstream, đa stack TS/Kotlin/Gradle/Capacitor, submodule 2160 Player, license, loại bỏ dependency vận hành và bảo mật.
- Các website/indexer có thể yêu cầu login, bị chặn hoặc chứa nội dung không có quyền: không mặc định khẳng định hợp pháp/hoạt động; validation theo nguồn với media hợp pháp.
- OMP có đường URL chứa credentials cho stream native/VLC. Đây là rủi ro audit cần test/redact, chưa kết luận exploit.
- Dùng OMP không tự động giải quyết thuyết minh AI hoặc khả năng hỗ trợ firmware Redmi/Xiaomi thật.

## Acceptance / gates

- OMP commit và Git submodule pin, npm/Gradle build, APK SHA, tests.
- License/dependency/security assessment; website search adapters vẫn tồn tại và hoạt động trong bài test hợp lệ.
- Phát/tua/resume, tiếng Việt Unicode, D-pad trên TV thật; server thật tách evidence.
- Không tiếp tục import/publish nếu vi phạm stop conditions trong contract.

## Rollback

Chỉ thay docs trong PR thay đổi chính sách. Không tự clone, ghi đè source, kích hoạt workflow, dispatch AIOS hay merge. Nếu feasibility không đạt, Human quyết định rollback ADR-0002 hoặc chọn phương án thay thế bằng ADR tiếp theo.
