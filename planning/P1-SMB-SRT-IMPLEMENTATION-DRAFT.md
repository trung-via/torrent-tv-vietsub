# P1-SMB-SRT — Kế hoạch triển khai phụ đề rời qua Windows SMB

**Ngày:** 2026-10-25  
**Loại:** Planning alias only; không phải AIOS canonical TASK.  
**Authority:** Quyết định Human P1 remote SRT, SMB Windows read-only ưu tiên, USB/TV fallback; ADR-0005 trong PR #10.  
**Tình trạng:** `DECIDED_FEATURE / IMPLEMENTATION_PROPOSED / SMB_TV_UNVERIFIED`.

## Mục tiêu người dùng

TV đang phát video TorrServer bằng OMP VLC, dùng remote **Up → Subtitles → Thêm phụ đề → Laptop Windows → chọn *.vi.srt/*.vi.vtt → OK**, file được nạp từ SMB qua LAN, app lưu riêng và nhớ theo phim/tập. Không cần điện thoại hoặc USB. Không bật SMB/Windows Firewall/tài khoản tự động.

## Bằng chứng phân biệt rõ

- Real TV: Human đã xác nhận VLC có hình và tiếng; Built-in không có tiếng. SRT ngoài torrent trên VLC/Redmi: **UNVERIFIED**.
- OMP upstream pinned `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`: `VlcEngine.kt` dùng `mp.addSlave(IMedia.Slave.Type.Subtitle, ...)` cho subtitle trong queue. Live import khi đang phát: **UNVERIFIED**.
- GitHub Actions trên target repo: dedicated runner smoke run `40128964785` **PASS tại thời điểm chạy**; pinned upstream debug build + Android unit tests run `40159082083` **PASS tại thời điểm chạy**. Repo `main` **chưa chứa OMP app source**. Runner online hiện thời và AIOS cross-repo dispatch: **UNVERIFIED**.
- TorrServer `MatriX.147.1` `/subs/{hash}/{id}` chỉ phục vụ phụ đề **nằm trong torrent**; không thể dùng API này để duyệt SRT tùy ý của Windows share.

## Phương án tối giản và lựa chọn thư viện

1. **Gate source/import:** audit/pin upstream + `2160player` submodule, GPL/third-party provenance và kế hoạch nhập OMP vào target repo qua PR độc lập; chưa nhập vào main hay dispatch AIOS.
2. **SMB adapter:** thử riêng `hierynomus/smbj` (SMB2/3, Apache-2.0 theo LICENSE_HEADER + Gradle POM), Kotlin/Android API/ABI, transitive deps, memory/size, signing và credential handling. Android compatibility **chưa được chứng minh**. `jcifs-ng` (LGPL-2.1) chỉ là phương án so sánh; kiểm tra min dialect vì mặc định có thể chấp nhận SMB1, không dùng SMB1/guest. Pin version/checksum sau license and device gate.
3. **Settings SMB:** cấu hình tên/IP máy, tên share, username/secret riêng; lưu credentials qua Android Keystore-backed storage, không hardcode/ghi log. Không dựa vào mạng SMB discovery hoặc quyền đọc toàn bộ TV.
4. **Browser D-pad:** thư mục/breadcrumb/folder/file filter `.srt`/`.vtt`, loading/error/cancel, back; gọi SMB trên worker/thread nền của app, không chặn UI.
5. **Import:** đọc đúng một file được chọn với read-only SMB account; giới hạn size, validate UTF-8/SRT/VTT, không path traversal, copy atomic vào app-private storage; liên kết `serverProfile+infohash+fileIndex`, đảm bảo không gắn nhầm phim/tập. Giới hạn cache, thao tác xóa/đổi lựa chọn.
6. **VLC player:** nạp phụ đề bằng đường `addSlave` đang có; PoC file URI và attach khi player đang chạy (có thể phải giữ position rồi reload source nếu libVLC không hot-add ổn định). Không làm hỏng audio VLC. Hỗ trợ bật/tắt, track nhúng, offset và seek/resume.
7. **Fallback:** Android SAF file picker nếu được HyperOS cung cấp (USB/Downloads); nếu SAF không có, dùng vùng import app-managed qua ADB/test. Không yêu cầu `MANAGE_EXTERNAL_STORAGE`.

## File/phạm vi được sửa khi source được nhập (PROPOSED)

- `android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt`: menu Subtitles + remote-first source picker, state/lifecycle.
- `android/app/src/main/java/com/spacesarmat/omp/player/VlcEngine.kt`, `PlayerEngine.kt`: import/attach subtitle source và regression audio/seek.
- `android/app/src/main/java/com/spacesarmat/omp/smb/*` (new): SMB client adapter/credential service/browser model; không chạm TorrServer.
- `src/player/nativePlayer.ts`, track preferences/storage **chỉ nếu cần** truyền metadata và nhớ lựa chọn.
- `android/app/src/test/**` và TypeScript tests: fixture parser/security, remote state, per-video mapping, negative cases.
- `docs/DECISIONS/ADR-0005*`, `docs/VERIFICATION.md`: ghi evidence/giới hạn.
- Không sửa AIOS-renew, Windows services/Firewall/router/UPnP hay GitHub runner config trong P1.

## Acceptance criteria

- **AC-SMB-1:** Người dùng đã cấu hình Windows share **sau approval vận hành riêng**, account chỉ đọc cả share permissions + NTFS; từ Redmi thật duyệt/list/chọn SRT bằng D-pad qua SMB2/3, không guest/SMB1.
- **AC-SMB-2:** SRT/VTT UTF-8 tiếng Việt hiện đúng dấu; switch embedded↔external↔off, offset; Play/Pause/Seek/Resume/reopen và audio VLC PASS, không nhầm series episode.
- **AC-SMB-3:** sai password, share không tồn tại, PC off, Wi-Fi rớt, file quá lớn/malformed, path escape, quyền bị thu hồi: lỗi có phân loại, không crash, không lộ secret.
- **AC-SMB-4:** TV chọn từ USB/TV local khi SMB offline; không xin quyền bộ nhớ rộng.
- **AC-SMB-5:** unit/build result và real hardware result báo riêng; APK debug hash/CI log (nếu build), ảnh/video TV hợp pháp có timestamps; no auto merge/release.

## Stop conditions và bảo mật

- Cần Windows Firewall/port 445, share creation, users/ACL: **dừng trước khi thao tác** và xin Human authorization cụ thể; không dùng điều kiện đồng ý P1 làm authorization hệ thống.
- Không SMB1/guest, không LAN-to-WAN/UPnP, không lưu mật khẩu vào file settings thường/log/APK/Git, không chia sẻ toàn ổ.
- SMBJ không chạy trên Android hoặc third-party license/security blocker: STOP, đề xuất alternate client/protocol và Human quyết định, không tự dùng custom HTTP backend.
- Repo app chưa nhập source/licensing gate không đạt, dedicated runner evidence không đủ cho phiên thực thi, hoặc AIOS canonical dispatch chưa được xác minh khi gọi AIOS: STOP; không mượn runner/workspace AIOS.
- Không báo P1 PASS chỉ từ source audit, mocks hoặc từ việc VLC phát video.

## Bước kế tiếp

(1) P1 feasibility review trên upstream pinned (SMB client Android + live `addSlave`) → (2) PR nhập mã OMP theo hợp đồng và license → (3) patch UI/adapter nhỏ trên runner riêng → (4) Human duyệt hướng dẫn tạo Windows share read-only, rồi kiểm thử Redmi thật. **Không chủ động tự tạo share, mở firewall, hay dispatch.**
