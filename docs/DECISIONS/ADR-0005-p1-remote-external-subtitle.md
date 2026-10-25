# ADR-0005 — P1 chọn phụ đề rời bằng remote, ưu tiên Windows SMB

**Ngày:** 2026-10-25
**Trạng thái:** DECIDED_PRODUCT_SCOPE / PROPOSED_IMPLEMENTATION / REAL_SMB_TV_UNVERIFIED

## Authority: quyết định Human mới nhất

- Ban đầu Human phê duyệt P1 thêm SRT/VTT ngoài torrent bằng remote, nguồn USB hoặc bộ nhớ TV.
- Human sau đó đồng ý **ưu tiên thư mục SMB chỉ đọc trên laptop Windows TorrServer**, thay USB thành fallback. Quyết định mới supersede thứ tự nguồn, không hủy đường USB/TV.
- Phê duyệt chức năng SMB **không** tự động phê duyệt bật Windows File Sharing, port 445, thay đổi Windows Firewall, Windows services hoặc tài khoản/credential. Các cấu hình trên host Windows cần Human phê duyệt cụ thể trước.

## UX mong muốn

1. Phát bằng OMP VLC -> remote D-pad Up -> Subtitles -> Thêm phụ đề -> Laptop Windows.
2. TV hiển thị danh sách thư mục/file từ một share đã cấu hình, giới hạn đuôi SRT/VTT; D-pad/OK/Back chọn file movie.vi.srt.
3. OMP sao chép file vào app-private storage, kiểm tra UTF-8/định dạng/dung lượng, gắn đúng media hiện tại qua libVLC và chọn track.
4. Nhớ lựa chọn theo local server profile + torrent infohash + file index, có offset và bật/tắt track; không gắn nhầm tập.
5. Khi SMB không khả dụng, người dùng chuyển sang nguồn USB/TV local (SAF hoặc app-managed fallback).
6. Phụ đề AI ở giai đoạn sau xuất ra cùng thư mục Windows; điện thoại tương lai có thể dùng chung luồng chọn file.

## Phương án tối giản (PROPOSED, chưa code)

- Tích hợp SMB client Android trong OMP và trình duyệt bằng remote; ưu tiên SMB2/3, cấm SMB1/guest. Không giả định Android SAF tự hỗ trợ mạng SMB. Chọn thư viện sau khi kiểm tra license, APK size và khả năng chạy trên Redmi HyperOS.
- Chỉ cấp quyền vào một thư mục riêng (ví dụ: TorrentTV-Subtitles) qua account Windows chuyên dụng read-only; giới hạn cả share permissions và NTFS permissions, không chia sẻ cả ổ đĩa/Administrator.
- Android lưu secrets trong secure storage/Keystore, không hardcode trong APK/repo/URL hoặc ghi vào log, có chức năng xóa/cập nhật credential; tên/địa chỉ share có thể thay đổi.
- Dùng đường nạp SRT nội bộ của OMP; source pinned có libVLC addSlave cho phụ đề trong queue khi khởi động. Bổ sung tệp ngay trong lúc phát phải PoC thực tế, không coi là PASS từ source audit.
- Không dựng HTTP backend/router/DB mới, không thay TorrServer, không mở WAN/UPnP, không chạy quét SMB nền.

## Acceptance criteria

- AC-1: Redmi TV thật dùng remote duyệt đúng share SMB2/3 và chọn SRT/VTT; không guest và không SMB1; cấu hình Windows đã được Human đồng ý trước.
- AC-2: Vietnamese Unicode hiển thị đúng bằng VLC, tiếng còn hoạt động, pause/seek/resume và mở lại đúng track cho đúng phim/tập.
- AC-3: Không thể ghi/xóa file trên laptop từ SMB account read-only; không lộ secrets; path traversal và file hỏng được xử lý.
- AC-4: Các trường hợp sai mật khẩu, thiếu quyền, laptop offline, mạng rớt, file bị xóa, sai encoding, quá dung lượng có lỗi dễ hiểu; fallback USB/TV.
- AC-5: Test source/unit/mock tách riêng E2E trên Redmi thật; không được báo REAL_SMB_TV_PASS trước khi có evidence.

## Stop / status

SMB client thiếu hỗ trợ an toàn/đụng license, hoặc cần SMB1/guest/port WAN hay sửa firewall chưa phê duyệt => STOP/BLOCKED, xin Human quyết định. Trạng thái hiện tại: SMB_SRT_UNVERIFIED.

PR này là docs-only và Draft, không thực thi trên laptop/TV, không liên quan AIOS dispatch/runner. PR #9 AI Vietsub thay đổi cùng docs nên cần reconcile trước khi merge.
