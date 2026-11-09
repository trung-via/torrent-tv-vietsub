# Torrent TV — GitHub Repository → Windows HostOps → Redmi (v2, PUBLIC)

## Quyết định người dùng — 2026-11-09
Dùng **chính** repository `trung-via/torrent-tv-vietsub` và công khai file subtitle trong repo. Không cần tạo repository PRIVATE, GitHub token bổ sung hoặc đăng nhập `gh auth` trên Windows. Quyết định này thay thế PR #91 (private-inbox).

**Lưu ý:** repository hiện PUBLIC. Mọi SRT commit vào `subtitle-artifacts/` có thể được mọi người xem và vẫn nằm trong lịch sử Git kể cả khi xóa sau này. Chỉ dùng nội dung mà người dùng có quyền phân phối công khai; không đưa phim, credential hoặc magnet/passkey vào repo.

## Dữ liệu đầu tiên
- `subtitle-artifacts/thor-v035.srt` — 1.761 cue, UTF-8 BOM, 123.768 bytes.
- Exact SHA-256: `3d9d4bf37fe31eb5de8a7af32d68c21fb5a342b87778f6f7925a7b43ad26c15b`.
- SHA phải được kiểm tra bằng `Get-FileHash` ngay trên self-host runner trước khi truyền.

## Quy trình sử dụng
1. Brain ghi `subtitle-artifacts/<slug>.srt` vào repository đang có; xác minh cue/timecode, SHA và source commit. Cho file vào `main` qua nhánh/PR được chấp thuận.
2. Brain gửi comment **chủ repo** trong Issue #82:
   `/tv-subtitle deliver <slug> <64-character-lowercase-sha256>`
3. Workflow `.github/workflows/torrent-tv-repo-subtitle-handoff.yml` chạy trên runner Windows `torrent-tv-vietsub-win`, checkout đúng SHA của sự kiện.
4. `hostops/jobs/repo-subtitle-handoff.ps1` đọc SRT từ checkout, so SHA-256, xác minh đúng một thiết bị ADB được phép và model `MiTV-ASTR0`.
5. Chuyển bằng ADB tới `/sdcard/Download/TTV-<slug>-<first-12-sha>.srt`; đối chiếu SHA trên Redmi. Trả `TTV_HANDOFF_REPO_TO_REDMITV_SHA_PASS` hoặc `TTV_HANDOFF_ALREADY_ON_REDMITV_SHA_PASS`. Không ghi đè file khác cùng tên/hashes.
6. Bot ghi `TTV_REPO_SUBTITLE_HANDOFF_V1` (source comment, run ID, Windows result) lên Issue #82; đối chiếu log Windows để biết thao tác ADB thực sự PASS.
7. Nhập file vào OMP bằng Android picker rồi quan sát hiển thị, tự hiện khi mở lại, seek/resume và tiếng Việt trên TV. Đây là **gate G1/G3 riêng**, không tự suy từ ADB push.

## Phạm vi
- Không thay APK/TV firmware, không đổi TorrServer, không gọi AIOS, không mở cổng mạng.
- Không dùng GitHub PRIVATE token/secret; native `GITHUB_TOKEN` mặc định của workflow chỉ phục vụ checkout repository này.
- V1 chỉ SRT; WebVTT và OMP auto-import có thể là các công việc tiếp theo nếu cần.

## Trạng thái nghiệm thu
- `SOURCE_PATCH`: chỉ khi review đầy đủ và PR merge.
- `RUNNER_TRANSFER_PASS`: chỉ khi Actions log có SHA source + remote TV SHA đúng; Actions job success một mình không đủ.
- `REAL_TV_RENDER_PASS`: chỉ sau test trực tiếp bằng media hợp lệ tại đúng timestamp.
