# Torrent TV — Private Subtitle Inbox → Self-host → Redmi (v1)

## Mục tiêu
Dùng GitHub làm điểm trung chuyển cho SRT/VTT **không công khai**, tránh thao tác tải file về laptop từng lần. Dự án vẫn độc lập AIOS; không cần MCP, máy chủ HTTP, mã hóa thủ công hoặc thay APK.

## Cài đặt một lần

1. Trên GitHub của `trung-via`, tạo repository `torrent-tv-subtitle-inbox` với **Visibility: PRIVATE**. Không đưa phim/subtitle vào repository `torrent-tv-vietsub` hiện đang PUBLIC.
2. Cấp quyền cho kết nối GitHub của ChatGPT thấy kho PRIVATE mới, để Brain có thể upload file `inbox/<slug>.srt` trực tiếp từ file đã tạo trong cuộc trò chuyện.
3. Tạo fine-grained token chỉ cho PRIVATE repository đó, repository permission **Contents: Read-only**. Lưu token dưới Actions secret `TTV_SUBTITLE_INBOX_READ` trong `trung-via/torrent-tv-vietsub`. Không đặt token vào Issue, script hay file.
4. Merge PR triển khai sau review/check; GitHub Actions workflow trên default branch mới nghe lệnh Issue #82.

## Sử dụng hằng ngày

- Brain xuất file subtitle và tính SHA-256 trên file SRT UTF-8.
- Brain dùng GitHub connector để tạo `inbox/<slug>.srt` trong repository PRIVATE. Xác minh byte/hash; nếu kết nối không thể upload chính xác thì STOP, không giả là đã upload.
- Brain ghi một owner comment vào Issue #82:
  `/tv-subtitle deliver <slug> <64-char-lowercase-sha256>`
- Job riêng chạy trên `torrent-tv-vietsub-win`: dùng token đọc đúng `inbox/<slug>.srt`, kiểm tra hash, tìm đúng 1 Redmi `MiTV-ASTR0`, ADB push vào `/sdcard/Download/TTV-<slug>-<sha12>.srt`, tính SHA trên TV và xác nhận trùng.
- GitHub bot trả run ID + trạng thái job về Issue #82. Xem log `TTV_HANDOFF_PRIVATE_GITHUB_TO_REDMITV_SHA_PASS` trước khi gọi chuyển file thành công.
- Import SRT bằng OMP document picker, phát phim hợp pháp, quan sát glyph/reopen/seek/resume là **gate riêng**, không được tự nhận PASS chỉ vì ADB push thành công.

## Giới hạn
- Kho chứa SRT phải là PRIVATE; repository mã nguồn hiện là PUBLIC và không phải chỗ cho full movie subtitle.
- `GITHUB_TOKEN` của workflow mã nguồn không tự đọc được repository PRIVATE khác; phải cấp fine-grained token read-only hoặc GitHub App tương đương (GitHub official docs).
- Token, nội dung subtitle, serial, đường dẫn máy, IP không được đưa vào log công khai.
- Đây là source-only cho tới khi PRIVATE repo + secret thực sự được thiết lập, workflow đã merge và lệnh thử thật chứng minh đủ chuỗi. Không thay thế nghiệm thu phát phụ đề trên TV.
- Có thể xóa file trong PRIVATE inbox sau khi hoàn tất; Git giữ lịch sử, nên chỉ đưa tài liệu được phép lưu trữ.
- WebVTT có thể được hỗ trợ bởi vòng nâng cấp riêng; v1 chỉ chuyển SRT.

## Hoàn tác
Revert workflow và script, thu hồi token hoặc xóa Actions secret. Không động vào APK/OMP/TorrServer, không xóa dữ liệu trên TV.
