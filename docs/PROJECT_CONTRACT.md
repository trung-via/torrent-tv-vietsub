# PROJECT CONTRACT v1.0 — Torrent TV Vietsub

**Repo:** `trung-via/torrent-tv-vietsub` (dự kiến PRIVATE)  
**Product:** Torrent TV Vietsub — AIOS  
**Ngày khởi tạo:** 2026-10-15  
**Trạng thái:** `INITIAL_BASELINE` — chốt mục tiêu/kiến trúc B từ Human; tính khả thi TV và các API thực tế còn `UNVERIFIED`.  
**Ranh giới:** contract sản phẩm của repo này; không thay thế Constitution, canonical task authority hay roadmap của `AIOS-renew`.

## C0 — North Star

Xây dựng ứng dụng xem video gia đình đáng tin cậy, dễ dùng bằng remote trên Redmi/Xiaomi A Pro 55 (2026) từ magnet/.torrent mà người dùng có quyền truy cập; có phụ đề tiếng Việt, phát/tạm dừng/tua và xử lý lỗi rõ ràng. Chất lượng nghiệm thu đo bằng video thực tế phát ổn định trên thiết bị hợp lệ, không đo bằng số lượng tính năng hoặc số TASK.

## C1 — Các quyết định không được tự ý đảo ngược (`DECIDED`)

1. **Mô hình client–server:** Windows PC streaming server mặc định, NAS thay thế; PC/NAS phải hoạt động khi xem. Không bắt TV chạy torrent engine.
2. **Server:** tái sử dụng TorrServer bên ngoài, truy cập qua LAN/HTTP API. Chỉ pin version và schema sau khi probe thực tế; không fork engine trong MVP.
3. **TV app:** Kotlin + Compose for TV + AndroidX Media3; thiết kế adapter `StreamEngine` để cách ly backend.
4. **Đầu vào P0:** user thêm magnet hoặc torrent qua TorrServer Web UI trên điện thoại/PC; TV app lấy danh sách và phát.
5. **Vietsub P0:** chọn track nhúng tương thích và sidecar UTF-8 SRT/VTT; ASS/SSA/PGS cần đo/khai báo hạn chế. Không hứa luôn có sẵn Vietsub.
6. **Điều khiển:** D-pad/remote trước touchscreen; UX TV rõ focus/Back, thông báo mất server, thiếu peers, codec lỗi.
7. **MVP tinh gọn:** không viết database/queue/orchestrator riêng, không companion smartphone app, không engine torrent bên trong APK, không tự động AI dịch ở P0.
8. **Phân tách AIOS:** AIOS là orchestration trong phát triển; app TV phải chạy độc lập, không nhúng Runtime/Brain/agent AIOS.
9. **GitHub repo độc lập:** source code và version của app trong repo riêng, không lẫn `AIOS-renew`; khi mới khởi tạo chọn PRIVATE.

## C2 — Những điều chưa được xác minh (`UNVERIFIED`)

- TV thực sự là Redmi A Pro 55 bản HyperOS hay Xiaomi TV A Pro 55 2026 bản Google TV; khả năng sideload APK, API/ABI, driver decoder/codec/audio.
- Phiên bản/API TorrServer trên Windows/NAS, auth, port, HTTP Range/seek, path stream, hành vi cache.
- Khả năng 4K/HEVC/AV1/HDR, audio passthrough, PGS và ASS trên phần cứng thực tế.
- Self-hosted AIOS có thể execute và publish đúng target repo mới qua canonical ingress hay không.

**Quy tắc:** không tự công bố `PASS` khi chưa có evidence của đúng môi trường. Thiếu server/TV thật không được giả lập bằng mock.

## C3 — Scope theo mốc

- **P0 / MVP:** TV installation gate, cấu hình LAN server, danh sách torrent/file video, Media3 playback pause/seek/resume, Vietsub UTF-8, remote navigation, typed errors, targeted tests.
- **P1:** độ ổn định LAN, pairing và handoff nếu thực sự cần, nâng cấp UX và release APK, hỗ trợ audio/subtitle tương thích tốt hơn.
- **P2 (opt-in):** máy Windows/NAS tạo transcript/dịch Vietsub có hậu kiểm, không tự chạy background khi chưa được cấp phép.
- **Out of scope:** bộ tìm phim lậu, DRM bypass, scraping nguồn không có quyền, tự mở server ra Internet, root TV/circumvent firmware, tự động transcode mọi codec, phát torrent mà không có server.

## C4 — Interface boundaries

`Phone/PC -> TorrServer Web UI/API -> HTTP media stream -> TV StreamEngine adapter -> Media3 Player -> Subtitle renderer`.

- TV UI không gọi thẳng chi tiết wire schema ở mọi nơi; thông qua adapter có test contract.
- Server xử lý metadata/pieces/cache; TV giải mã và render. Transcode là tính năng *sau* khi chứng minh cần/khả thi.
- Local configuration nhỏ do app lưu; API credential không hardcode/không đưa vào Git hoặc log.

## C5 — An toàn, riêng tư và bản quyền

- Chỉ phát nội dung mà người dùng được phép sử dụng hoặc phân phối; test fixture dùng video tự tạo, CC/open-license có bằng chứng.
- LAN trusted, không expose public/WAN/UPnP/port-forward; việc thay đổi firewall/service/startup/router cần phê duyệt Human riêng.
- Không lưu URL magnet cá nhân, tracker token/passkey, credential, IP thật hoặc nội dung phim trong artifact/repo/log chia sẻ.
- Xác nhận license TorrServer và nghĩa vụ phân phối trước khi bundle bất kỳ binary; mặc định sử dụng upstream riêng.

## C6 — Chất lượng, kiểm chứng và exit gates

- **AC-APP:** APK build tái lập; remote focus/Back; test Kotlin parser/adapter/mocked HTTP; có sha/build logs khi đã build.
- **AC-SERVER:** real TorrServer server health, file selection và stream/seek từ torrent test hợp pháp; nếu không có server thật báo `REAL_SERVER_UNVERIFIED`.
- **AC-TV:** APK được cài, mở, điều khiển và phát trên TV/box thật; nếu chưa có quyền hoặc firmware không hỗ trợ báo `REAL_TV_UNVERIFIED`/`DEVICE_BLOCKED`.
- **AC-SUB:** Vietsub Unicode có dấu, track/sidecar và sync hoạt động trên fixture; ASS/PGS không pass khi chưa thử.
- **AC-RELEASE:** được Human chấp thuận release, APK có metadata và rollback rõ; không tự công bố production.
- Unit/mock PASS không bằng E2E PASS; emulator PASS không bằng TV thật PASS.

## C7 — Governance và thay đổi contract

- **Authority sản phẩm:** quyết định Human rõ ràng > `docs/PROJECT_CONTRACT.md` > `docs/PRD.md` > `docs/DECISIONS/*.md` > `docs/ROADMAP.md` > các bản chat summary và nháp.
- **Authority thao tác AIOS:** canonical repo `AIOS-renew` tại thời điểm giao nhiệm vụ; phải fresh Brain Sync, kiểm tra unique NEXT/admission, scope cross-repo, executor và review. Contract này KHÔNG cấp quyền dispatch hoặc sửa AIOS.
- Mọi sửa đổi C1/out-of-scope/authority/security phải có Human phê duyệt, ghi ADR và diff contract trong một PR/commit có thể audit.
- Với tinh chỉnh kỹ thuật cục bộ trong C1: executor được đề xuất thiết kế + test trong TASK được phép; không tự thay đổi product intent.
- Mặc định AIOS two-pass review nếu canonical yêu cầu; không giả định cơ chế mới đã kích hoạt. Không nhập bộ test AIOS hoặc minimum-sufficient-v2 vào app nếu không có yêu cầu rõ.

## C8 — Điều kiện dừng và rollback

Dừng khi: workspace target không chứng minh độc lập, AIOS không có quyền cross-repo, cần bí mật trong repo, phải vượt firmware/DRM, cần mở Internet public trái scope, hoặc kết quả real environment đang bị báo là mock PASS. Không sửa phá `AIOS-renew` để chữa lỗi app. Giữ diff/commit có thể rollback.

## C9 — TASK đầu tiên

**Alias:** `TVAPP-001` (planning only; không phải ID TASK canon của AIOS).  
**Mục tiêu:** chứng minh ngoại repo + build Android TV skeleton + mock server + device compatibility checklist.  
**File:** `planning/TVAPP-001-DRAFT.md`.  
**Không dispatch, không coi repo contract là AIOS task admission.**
