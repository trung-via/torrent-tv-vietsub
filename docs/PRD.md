# AIOS — Torrent TV Vietsub | PRD v2 (Windows/NAS client–server)

**Ngày:** 2026-10-15  
**Trạng thái:** DRAFT — Human đã chọn kiến trúc B; **chưa canonical, chưa tạo repo mới, chưa AUTHOR_TASK/dispatch**.  
**Đầu vào:** PRD v1 `AIOS_TORRENT_TV_VIETSUB_PRD_DRAFT_2026-10-15.md`.  
**Repo đề xuất:** `torrent-tv-vietsub`, độc lập với `AIOS-renew`.

## 0. Quyết định thiết kế đã chốt (thay đổi so với v1)

1. **Chỉ triển khai client–server** ở MVP. Windows PC là **mặc định**; NAS chạy container là tùy chọn triển khai tương đương. PC/NAS phải bật khi xem. Không nhúng BitTorrent engine vào APK.
2. **TorrServer** (dependency bên ngoài, ghim version sau khi smoke test) xử lý torrent, peers, piece cache và phát HTTP. Không fork/viết lại engine; không nhúng binary vào repo nếu chưa rà soát license/phân phối.
3. TV chạy app native Android TV bằng **Kotlin + Compose for TV + AndroidX Media3** nếu firmware hỗ trợ APK. Thiết bị Redmi A Pro 55 phiên bản nội địa chưa được xác nhận chính xác; không đồng nhất với Xiaomi TV A Pro 55 2026 bản Google TV Việt Nam.
4. **Điện thoại dùng giao diện web TorrServer có sẵn** để thêm magnet / `.torrent` trong MVP. Không xây companion app mới ở P0.
5. Vietsub P0: chọn track tiếng Việt có sẵn hoặc nạp `.srt`/`.vtt`; kiểm tra `.ass`/`.ssa` thực tế, không hứa giữ nguyên hiệu ứng karaoke/typesetting. AI speech-to-text/dịch trên server là P2, bật theo yêu cầu.
6. AIOS chỉ điều phối tạo và kiểm thử repo mới. **Không thêm runtime của AIOS, DB điều phối, router hay agent nền** vào media app.
7. TASK đầu tiên ưu tiên chứng minh chuỗi **AIOS → repo độc lập → APK build → TorrServer contract → device-gate**, không cố hoàn thành toàn bộ player.

## 1. Mục tiêu sản phẩm

Người dùng cung cấp magnet link hoặc `.torrent` của nội dung có quyền sử dụng trên điện thoại/PC; server đọc torrent và cung cấp luồng dữ liệu; TV xem bằng remote, phát/tạm dừng/tua/chọn tập, hiển thị phụ đề tiếng Việt và thông báo nguyên nhân khi không phát được. Sử dụng trong mạng gia đình; không tích hợp index phim lậu, bypass DRM, scraping nguồn vi phạm bản quyền.

### Ngoài phạm vi MVP

- TV không cần PC/NAS; torrent engine chạy độc lập trên TV.
- AI dịch phụ đề tự động; tìm phụ đề từ nguồn bên ngoài; chuyển mã mọi định dạng 4K; ứng dụng mobile riêng; phát ngoài mạng gia đình.
- Cam kết mọi MKV/HEVC/AV1/HDR/audio/ASS chạy được trước khi đo codec trên thiết bị.

## 2. Kiến trúc kỹ thuật

```text
[Điện thoại/PC]  --LAN--> [TorrServer Web UI / API trên Windows hoặc NAS]
    |                               |
    | thêm magnet/.torrent          +-- engine torrent, metadata, piece-cache
    |                               +-- HTTP media URLs (+ optional -gst HLS)
    |                               |
    +-------------------------------+------------------------- LAN ----------------+
                                                                          [TV app]
                                                                         TV UI / D-pad
                                                                         Server adapter
                                                                         Media3 player
                                                                         Vietsub manager
```

**Server (Windows mặc định):** binary TorrServer gốc; pin phiên bản được kiểm thử và đường tải chính thức; cache/config tách khỏi source repo; script `server/install-windows.ps1`, `server/test-server.ps1` chỉ được xây dựng và chạy khi người dùng cấp phép. Phải có cơ chế khởi động thuận tiện cho lúc xem (không ngầm thay đổi startup/Windows service trong TASK 1). Ưu tiên Ethernet hoặc Wi‑Fi ổn định; cấu hình IP cố định qua DHCP reservation được hướng dẫn, không tự sửa router.

**Server (NAS tùy chọn):** Docker Compose sử dụng image gốc có version/digest pin, persistent volume, giới hạn bộ nhớ/cache phù hợp NAS, policy restart có thể tắt và port nội bộ; không giả định NAS có khả năng transcode bằng CPU/GPU.

**TV client:** Kotlin app/Compose for TV; Media3 ExoPlayer; repository interface `StreamEngine` để không phụ thuộc API cụ thể ở UI. Mở URL media/seek chuẩn; phát HLS chỉ khi server hỗ trợ được xác minh. Thông tin đăng nhập và URL server không hardcode vào build hoặc log.

**Các API cần xác minh bằng phiên bản server được pin:** health (`/echo`), quản lý/list torrent (`/torrents`), URL media (`/stream`, `/play`) và hành vi HTTP Range/seek. Không coi bất cứ request/response schema chưa thử nghiệm nào là đã nghiệm thu; cung cấp mock fixtures tái lập ở integration tests. GStreamer `-gst` là optional, không nằm đường phát P0.

## 3. Ma trận tương thích và fallback

| Điều kiện | Đường xử lý |
|---|---|
| Firmware hỗ trợ APK Android TV | Install/launch native app; xác minh focus/D-pad/decoder thật |
| Firmware không hỗ trợ APK | Dừng nhánh APK trên firmware đó; báo blocker và đề xuất Android TV/Google TV box ngoài, không root TV |
| Server offline / khác mạng LAN | Không chờ vô hạn; chỉ rõ URL, network hoặc auth lỗi và cách khắc phục |
| Torrent không có peer/metadata | Trạng thái riêng, không gộp với lỗi codec hoặc server |
| Container/codec/audio được TV giải mã | Direct-play trên Media3 |
| Không giải mã được | Báo format cụ thể; khảo sát `-gst` HLS/transcode trên server ở pha sau, dựa trên đo đạc |
| Vietsub là track text tương thích | Cho chọn track qua remote |
| Vietsub sidecar SRT/VTT UTF-8 | Nạp thủ công/ghép tên; hỗ trợ tiếng Việt có dấu |
| ASS/SSA nâng cao / subtitle ảnh PGS | Probe; nếu không tương thích thì cảnh báo và chỉ chuyển đổi nếu có giải pháp được xác minh |

## 4. Các pha sản phẩm

### P0 (khả dụng cơ bản)

- Nhập địa chỉ server LAN, kiểm tra kết nối/auth và lưu cấu hình có giới hạn.
- Hiển thị torrent và file video đã thêm trên server; chọn tập/file.
- Phát video, tạm dừng, seek, resume, trạng thái buffer, thông báo lỗi có nguyên nhân.
- Remote navigation/touch-free: D-pad, Back, play/pause, focus hợp lý.
- Track phụ đề/audio; `.srt`/`.vtt` Việt Unicode.
- Có test mock offline + smoke trên server thật + test cuối trên TV thật.

### P1 (trải nghiệm hằng ngày)

- QR/local pairing hoặc gửi link từ điện thoại khi web UI sẵn có không đáp ứng.
- Auto reconnect server, recent/resume, map subtitle theo tập; điều chỉnh font/offset.
- Chọn chất lượng/phương án phát trên server khi có khả năng transcode đã được kiểm chứng.
- Chẩn đoán từ TV/log có che thông tin nhạy cảm; kịch bản Windows bật/tắt, LAN thay đổi.

### P2 (Vietsub thông minh, chỉ bật khi yêu cầu)

- Server PC tạo transcript tiếng gốc khi có quyền xử lý nội dung; dịch sang Việt và align timestamps; review chất lượng, cache hợp lệ và cho người dùng sửa.
- Không coi mô hình AI là nguồn phụ đề chính xác tuyệt đối; thiết kế opt-in và giới hạn tài nguyên.

## 5. Cấu trúc repository mục tiêu

```text
torrent-tv-vietsub/
  README.md
  LICENSES/                  # thông tin dependency/license
  docs/
    PRD.md
    ARCHITECTURE.md
    DEVICE_COMPATIBILITY.md
    TORRSERVER_CONTRACT.md
    SECURITY.md
    TEST_MATRIX.md
  android-tv/
    app/
    core/
      streaming/             # StreamEngine + API adapter
      subtitles/
    feature/
      server-connection/
      library/
      player/
  server/
    install-windows.ps1      # chỉ sau khi được authorize
    test-server.ps1
    docker-compose.example.yml
  tests/
    fixtures/                # media open-license hoặc tự tạo
    mock-server/
  scripts/
    build-debug.ps1
    adb-smoke.ps1
  .github/workflows/
    android-ci.yml
```

Không cần database tùy biến hoặc backend viết mới ở P0. Config app nhỏ, cục bộ và do app quản lý; không dùng DB của AIOS.

## 6. Lộ trình AIOS — chưa cấp TASK ID canonical

| Thứ tự | Task working title | Exit gate |
|---|---|---|
| **01** | **External Repo + Device/Server Feasibility Bootstrap** | Repo skeleton + APK build + contract mock + server health smoke; TV thật có evidence hoặc blocker được ghi rõ |
| 02 | TorrServer Adapter & Playback Core | List video/episode; stream/seek direct-play từ fixture được phép chia sẻ; lỗi phân loại rõ |
| 03 | Vietsub & Remote Playback UX | Subtitle UTF‑8 tiếng Việt, track selection, offset/size nếu khả thi, D-pad ổn |
| 04 | LAN Hardening, Phone Handoff & Release | Cài đặt server có tài liệu Windows/NAS; E2E TV thật, reproducible signed APK sau phê duyệt |
| Optional 05 | AI Vietsub trên Windows/NAS | Opt-in ASR + translation + transcript QA + chi phí đo đạc |

**Không tự đánh số TASK-359/360:** số TASK thật, trạng thái NEXT, đường AUTHOR_TASK và quyền sửa repo phải đến từ Brain Sync tại thời điểm author. Commit `main` ghi nhận khi khảo sát (không phải trạng thái bất biến) là `03a4681962b7a5740d73a1374bc30a413a876fe3` (2026-10-15, qua GitHub). README AIOS có `--repo` nhưng cần thử nghiệm đường self-host wake/dispatch đối với repo *khác* trước khi cam kết E2E.

## 7. Chi tiết TASK đầu tiên

Tham chiếu bản **`AIOS_TORRENT_TV_FIRST_TASK_DRAFT_2026-10-15.md`** đi kèm. Scope của TASK 01:

1. Fresh Brain Sync; read-only kiểm tra cơ chế repo ngoài, task admission, CI/self-host execution boundary; không sửa repo `AIOS-renew` để cưỡng ép routing.
2. Nếu được phép bởi canonical governance, tạo **repo skeleton cục bộ độc lập**; tuyệt đối không tạo repo GitHub public/private, secret hoặc workflow chạy thật nếu chưa có authorization cụ thể.
3. Tạo Android TV skeleton có launcher banner/TV manifest, server configuration screen, health indicator; tạo APK debug reproducible và Android build workflow chỉ khi quyền được cấp.
4. Adapter thử nghiệm với mock server; probe read-only tới TorrServer Windows có sẵn **nếu endpoint được cung cấp và có phép**. Nếu chưa có, ghi `NOT_EXECUTED_EXTERNAL_ENV`, không fake PASS.
5. Chuẩn bị script adb smoke và danh sách bằng chứng thực tế; cài/launch TV thật **chỉ khi người dùng cho phép ADB** và thiết bị truy cập được.
6. Tách kết quả **AUTO_PASS**, **PHYSICAL_DEVICE_UNVERIFIED**, **SERVER_NOT_AVAILABLE**, **BLOCKED_BY_CANONICAL_AUTHORITY**; không để thiếu TV chặn build/contract test.

## 8. Verification / Reliability / Security

- Build Gradle offline/cache hợp lý; CI không cần tải torrent hoặc server thật.
- Unit tests URL normalization, response parser, typed error; mock contract integration test; media demo sample có quyền; negative tests server offline, bad auth, timeout, thiếu stream.
- TV E2E phải có bằng chứng app launch/remote/server thật; không giả lập bằng unit tests.
- Không mở port public/WAN/UPnP. Windows Firewall giới hạn LAN trusted; NAS port không expose qua internet; secret không xuất hiện trong source, action log, screenshots.
- `HTTP Basic` trên HTTP thuần không mã hóa; dùng chỉ trong mạng gia đình tin cậy có kiểm soát, ưu tiên HTTPS + chứng chỉ tin cậy nếu triển khai lâu dài. Không chuyển credentials qua query string; cân nhắc reverse proxy nếu muốn tăng mức bảo vệ.
- Pin dependency version, checksum provenance; đánh giá giấy phép **GPL-3.0** của TorrServer và các nghĩa vụ liên quan nếu tích hợp/phân phối. Không vendor binary mặc định.
- Phân loại fail theo lớp: AIOS ingress/auth, cross-repo workspace, Gradle/SDK, server/network/auth, stream/peers, decoder/media, subtitles/device.
- Hai lượt review chuyên môn theo governance hiện hành, chỉ sau khi có bằng chứng; không đưa test suite nội bộ AIOS vào CI app nếu không liên quan.

## 9. Vấn đề chưa được xác minh — không chặn soạn draft

1. Chính xác mã TV/firmware: Redmi A Pro 55 bản nội địa hay Xiaomi TV A Pro 55 2026 bản Google TV; quyền sideload APK.
2. Windows PC đã cài TorrServer hay chưa, IP LAN và phiên bản thực; khả năng truy cập từ TV.
3. Codec/container/subtitle thực tế và băng thông mạng LAN; 4K cần benchmark với media hợp pháp.
4. Phạm vi quyền AIOS tạo repo GitHub mới và remote self-host cho repo khác; chỉ chốt sau fresh canonical sync và proof.

## 10. Nguồn kỹ thuật

- https://github.com/YouROK/TorrServer — server HTTP/API, flags auth/SSL/GStreamer và GPL-3.0.
- https://www.mi.com/vn/product/xiaomi-tv-a-pro-55-2026/specs/ — thông số bản Xiaomi Google TV tại VN (không mặc định là Redmi nội địa).
- https://developer.android.com/training/tv/get-started/create — xây ứng dụng Android TV.
- https://developer.android.com/media/media3/exoplayer/supported-formats — codec/container/subtitles Media3.
- https://github.com/trung-via/AIOS-renew/blob/main/README.md — tài liệu CLI, `--repo`, governance của AIOS.
