# P3 — Xác định đúng file phát để dùng phụ đề EN cục bộ

**Human action:** "ok tiếp tục", 2026-11-14. **SOURCE-ONLY — chưa gắn vào thiết bị.**
Nối tiếp [LOCAL_EN_DIRECT #145](https://github.com/trung-via/torrent-tv-vietsub/pull/145) / [Issue #144](https://github.com/trung-via/torrent-tv-vietsub/issues/144), không thay translator #140, owner agent #143, P3 event policy #142 hay receiver #120.

## Tại sao cần resolver?

Upstream OMP `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` cho thấy:
- `NativePlayer.kt`: `PlayRequest(queue,index,session)`; `QueueItem.hash/fileIndex/title`.
- `src/api/torrserver.ts`: `TorrServerClient.get(hash)`, `files(t)` từ `file_stats` hoặc `data.TorrServer.Files`; `src/lib/episodes.ts`: mỗi `TorrentFile` có **`id`, `path`, `length`**. `/ffp/{hash}/{index}` cung cấp danh sách track, không phải bytes nguồn phụ đề.
- Torrent đã thêm hoặc nhãn EN trong OMP không đảm bảo video đã có **file hoàn chỉnh trên laptop**; TorrServer có thể chỉ stream/đệm dữ liệu. Không đoán local file dựa trên title; không gọi `ffmpeg` bằng stream URL.

## Hợp đồng mới: exact binding

`owner_selected_file_resolver.py` nhận qua **ba hàm của adapter owner đáng tin cậy** (injected, không có HTTP client):
1. `read_verified_current_playback()`: snapshot **mới và đã được xác thực từ TV**: session, server, torrent hash, index, tên file, viewer ON, VI ABSENT, owner auto enabled và content rights approved.
2. `read_verified_torrserver_file(server, hash, index)`: đúng **một file** từ một lượt đọc metadata TorrServer có xác thực; `id` trùng `fileIndex`, `path` có basename trùng tên file đang chọn, `length` hợp lệ. Không gọi trực tiếp endpoint bằng module này.
3. `locate_owner_pinned_files(server, hash, index, torrent_path)`: map **đã được owner quản lý trong profile riêng** sang đường dẫn video/sidecar cục bộ cụ thể, hoặc `None` nếu không có file.

Input tiêu thụ còn cần `expected_tv_session_id` và `source_fingerprint` từ event được xác thực. Source fingerprint dùng **đúng công thức của P3-TRIGGER #142**: SHA-256 chuỗi `server_id + NUL + infohash + NUL + fileIndex`. Fingerprint không chứa session nên **cả session ID phải khớp riêng**; thay đổi TV session với cùng một phim cũng phải HOLD.

Nếu có video cục bộ, kiểm tra path nằm trong thư mục owner cho phép, không symlink, filename đúng và **khi công bố đã tải đủ**, kích thước phải khớp `TorrServerFile.length`. Nếu không chỉ định sidecar, xét đúng **6 tên dự đoán hữu hạn** `<video-stem>.en|eng|english.srt|vtt` trong **cùng thư mục**; nhiều hơn một file hợp lệ → `HOLD`, không chọn ngẫu nhiên. Nếu có file EN riêng dù không có video cục bộ, owner phải pin sidecar đích danh. Sau khi khớp mới trả `LocalMediaSelection` cho extractor #145; không gọi provider từ resolver.

**Giới hạn quan trọng:** một snapshot `attested=True` hay một callback Python không tự xác thực mạng. Module chỉ là **cross-check** sau authentication, tuyệt đối không xem là security proof. Kích thước file và filename không chứng minh cryptographic hash nội dung movie. Không gửi JSON thô từ GitHub, URL công khai hay runner NETWORK_SERVICE vào resolver.

## Kết quả và fallback

- `LocalMediaSelection` → #145 `find_local_english` → SRT/VTT hoặc English text track → cache D2/LEAN120, với nguồn VI ưu tiên trước đó.
- `None` → chưa có nguồn local; adapter đã xác thực có thể gọi D2 VI_FAST/EN, **nhưng phải giữ identity fingerprint để chống lẫn cache cùng tên**.
- `SelectedFileResolveError` → session/identity/quyền/path bất thường; HOLD và **không** tự kích hoạt OpenSubtitles/Gemini. Chỉ ghi error code tổng quát, không in path, IP, tên phim hoặc hash.

## Còn phải làm trước khi nghiệm thu thật

**Không tích hợp trực tiếp vào PR #143** khi chưa compose rõ hai nhánh: owner inbox V2 hiện mang `source_fingerprint` và tên phim **nhưng chưa mang TV session ID**; PR #145 bổ sung `local_source` vào `selected_media()`, trong khi #143 hiện bổ sung `source_fingerprint` ở cùng phương thức. Đây là **hai chữ ký song song chưa được compose**. Phải làm một PR tích hợp sau review, giữ cả session+fingerprint+local_source, không tự động gán `attested=True` từ dữ liệu inbox.

Khi sở hữu quyền thiết bị thực tế: xác minh TV event / server metadata bằng đầu đọc đáng tin cậy, kiểm tra file readable hoàn chỉnh trên laptop, triển khai một lần owner-agent trong phiên Windows tương tác (owner, không chạy trong runner Session0), kiểm tra true EN→LEAN120 API theo chính sách đã cho phép, và D3/P4 không chọn thủ công trên TV. **Không tự cài service/ADB/firewall, không copy movie, API key hoặc SRT vào GitHub PUBLIC.**

## Acceptance gates

| Gate | Loại | Trạng thái |
| --- | --- | --- |
| Resolver unit: đúng id/hash/index, session, stale A/B/A, sidecar, path và privacy | Offline CI | PENDING exact-head |
| FFmpeg SRT/VTT/embedded và P2 regression | #145 | CI PASS 653/653 (synthetic) |
| Runtime composition #145 + #143 + #142 (TV event V3 session) | Source | NOT_RUN |
| Real owner file read / server hash+index proof | Owner device | NOT_RUN |
| Real Gemini LEAN120 / P4 Redmi no-picker | Provider / TV | NOT_RUN |
