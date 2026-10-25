# ADR-0005 — P1 nạp phụ đề rời bằng remote TV

**Ngày:** 2026-10-25
**Trạng thái:** DECIDED_PRODUCT_SCOPE / PROPOSED_IMPLEMENTATION / REAL_TV_UNVERIFIED

## Quyết định Human
Human đồng ý P1 và yêu cầu có thể thêm file SRT bằng remote trên Redmi TV. P1 sẽ hỗ trợ SRT/VTT rời ngoài torrent; không cần điện thoại. File phải tồn tại trên USB hoặc bộ nhớ TV trước khi remote có thể chọn. Giữ OMP + VLC, không thay TorrServer hay mở cổng LAN mới.

## UX
1. Khi OMP VLC đang phát, remote Up > Subtitles > Thêm phụ đề từ file.
2. Chọn USB hoặc Downloads nếu được hệ thống cung cấp, D-pad/OK/Back để duyệt.
3. Chọn SRT/VTT UTF-8, validate file và sao chép vào app-private storage, bật track.
4. Bật/tắt/đổi phụ đề, chỉnh offset, nhớ theo local server profile + torrent infohash + file index.
5. Khi file mới nằm trên Windows, người dùng chép trước qua USB hoặc ADB; truyền file bằng điện thoại sẽ xây sau và tái dùng luồng import, không làm phụ thuộc P1.

## Phương án tối giản (PROPOSED)
- Dùng Android Storage Access Framework ACTION_OPEN_DOCUMENT, cấp quyền trên file do người dùng chọn, tránh MANAGE_EXTERNAL_STORAGE.
- Redmi HyperOS có thể không có DocumentsUI hoặc picker không tương thích remote: trước khi xây, chạy device probe; fallback giao diện duyệt trong vùng import app quản lý, với đường copy file được phép qua USB/ADB; không quét toàn bộ bộ nhớ.
- Tái dùng OMP VlcEngine với libVLC addSlave hiện có; song nạp SRT mới khi video đang phát và content/file URI là UNVERIFIED và phải thử PoC.
- Không thêm backend/DB/Windows service, không sửa firewall, không mở WAN/UPnP. Không tiết lộ torrent/private path/token vào log/Git.

## Acceptance
- AC-1: nhập SRT và VTT UTF-8 bằng remote (D-pad, OK, Back) trên Redmi HyperOS thật từ nguồn đã có sẵn.
- AC-2: giữ dấu tiếng Việt, bật/tắt, chuyển lại track nhúng, chỉnh offset, không sai mapping phim/tập.
- AC-3: video/audio VLC vẫn hoạt động, pause/seek/resume và đóng/mở lại đúng track đã chọn.
- AC-4: file lỗi, không tồn tại, USB tháo, picker không có, không đủ quyền: báo lỗi dễ hiểu; fallback không yêu cầu quyền đọc toàn bộ ổ.
- AC-5: không làm thay đổi TorrServer hoặc quy định AIOS; mock test không thay evidence trên TV thật.

**Stop:** Khi SAF không khả dụng và fallback app-managed không hoạt động trên TV thật, dừng và xin Human chọn đường chuyển file phù hợp. Trạng thái REMOTE_SRT_IMPORT_UNVERIFIED.

**Scope integration:** AI Vietsub tương lai tạo file .vi.srt để nạp qua cùng luồng, phone remote tương lai chọn/gửi file; thuyết minh phải dùng PoC audio riêng.
