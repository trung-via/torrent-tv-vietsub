# P3-MOBILE — Thiết lập OMP trên điện thoại Android (owner-only)

**Status:** `SOURCE_SETUP_PREPARED / PHONE_INSTALL_NOT_RUN / WINDOWS_SERVER_CONNECT_NOT_RUN / REDMI_PAIR_NOT_RUN`  
**Issue:** [#138](https://github.com/trung-via/torrent-tv-vietsub/issues/138)  
**Ngày đối chiếu:** 2026-11-14. **Repo công khai** — tuyệt đối không đăng địa chỉ IP LAN, mật khẩu, link private tracker, tên media cá nhân, log màn hình pairing hoặc mã 6 chữ số lên GitHub.

## Mục đích và ranh giới

Thiết lập **điện thoại Android như một OMP client/remote**. Windows PC vẫn chạy TorrServer hiện có; Redmi A Pro 55 chạy **OMP Vietsub Debug hiện tại**. Không cài thêm TorrServer trên điện thoại, không thay thế ứng dụng TV, không tạo app Kotlin/Compose riêng, không mở WAN/UPnP/ADB/firewall, không kết nối AIOS và không gọi API Gemini.

Upstream chính thức: [OMP README.en.md](https://github.com/spacesarmat/omp/blob/main/README.en.md). Upstream công bố Android 8+, thư viện TorrServer, search, remote phone→TV, kết nối Android TV bằng mã 6 chữ số. Tại thời điểm đối chiếu, release là [OMP v0.30.0](https://github.com/spacesarmat/omp/releases/tag/v0.30.0), phát hành **2026-11-11**:
- `OMP-0.30.0-arm64.apk` cho **Android OS 64-bit (arm64-v8a)**;
- `OMP-0.30.0-armv7.apk` cho OS 32-bit;
- `OMP-0.30.0.apk` universal khi chưa chắc ABI.

### APK SHA-256 đối chiếu từ GitHub Release API (v0.30.0)

Dùng đúng file trong [release chính thức](https://github.com/spacesarmat/omp/releases/tag/v0.30.0). Mã SHA-256 bên dưới được đọc từ trường `assets[].digest` của GitHub Releases API ngày 2026-11-14; chỉ chứng minh tệp tải về khớp *asset được đăng trên release đó*, không phải kiểm toán độc lập khóa ký APK hoặc tương thích với Redmi.

| APK | SHA-256 |
| --- | --- |
| `OMP-0.30.0-arm64.apk` | `aaf241dc759ca2e361ade2bc978362c1598c02533600e677150b5f33ede24c84` |
| `OMP-0.30.0-armv7.apk` | `c52af8f3aadc7985c35c4de9da122edc3b2b404bb2d045f3fac6c4b2584e2f02` |
| `OMP-0.30.0.apk` | `a7b8cc1c1df3b76bb3aedd783f198484b9cd4de5ff7c69a588a0fb0887bac3a4` |

Nếu APK được tải về Windows để chuyển thủ công sang điện thoại, tính checksum tại laptop bằng `Get-FileHash -Algorithm SHA256 -LiteralPath '<file.apk>'`. Không ghi lại đường dẫn cá nhân/checksum trong GitHub issue; so sánh **cục bộ** với bảng. Nếu checksum khác, dừng cài và xác minh lại release/filename; không tắt kiểm tra chữ ký.

**Không suy ABI chỉ từ tên CPU hoặc dòng điện thoại.** Người dùng kiểm tra Android version/ABI trong Settings hoặc qua hệ thống thông tin đáng tin cậy trước khi chọn APK. Không cài file APK phát tán lại từ nguồn không rõ. Những bản phát hành mới hơn phải xác minh lại tên asset, chữ ký và compatibility; phiên bản số trong tài liệu này là *pin kiểm toán*, không phải lệnh cấm cập nhật.

**Cảnh báo tương thích:** các overlay G1/G2/P4 trên Redmi được xây từ OMP upstream pin `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, trong khi APK điện thoại từ upstream v0.30.0. Tài liệu upstream có chức năng phone pairing, **nhưng ghép phone v0.30.0 với TV Debug đã tùy biến chưa được thử thật**. Không thay APK TV để “sửa” lỗi pairing.

## M0. Cài trên điện thoại (thực hiện trên máy của owner)

1. Kiểm tra hệ điều hành Android **8 trở lên** và ABI của hệ điều hành; bảo đảm có chỗ trống, Wi-Fi.
2. Từ trình duyệt điện thoại, mở [GitHub Releases chính thức](https://github.com/spacesarmat/omp/releases/tag/v0.30.0) và tải APK đúng ABI. Chọn universal nếu không xác định chắc chắn kiến trúc OS.
3. Xác nhận trang tải thuộc `github.com/spacesarmat/omp`, tên file/phiên bản hiển thị khớp. Chỉ cấp quyền “cài ứng dụng không rõ nguồn gốc” cho đúng ứng dụng mở APK trong lúc cài, và tắt quyền đó lại sau cài. **Không bật USB/Wi-Fi debugging chỉ để cài điện thoại.**
4. Cài và mở OMP trên điện thoại. Không chọn chức năng khởi chạy TorrServer trực tiếp **trên điện thoại** vì đã có TorrServer Windows.
5. Ghi bằng chứng riêng tư: Android version, OS ABI, OMP version, tên APK, checksum SHA256 của file nguồn nếu có; không chia sẻ log gắn tên phim/mạng cá nhân trên repo public.

**Gate:** `G-MOBILE-INSTALL`. Chỉ PASS khi owner quan sát app thật trên Android phone; README/CI hoặc việc xuất hiện một link tải không phải bằng chứng đã cài.

## M1. Kết nối đúng TorrServer Windows sẵn có

1. Trên Windows, xác nhận TorrServer hiện có **đang chạy** mà không restart service hay đổi cấu hình; nếu chưa biết TCP port hiện tại, xem trong UI/local config server (không đoán từ tài liệu). Chạy kiểm tra chỉ đọc **trên chính laptop** nếu muốn:
   `pwsh -NoProfile -File .\tools\mobile-companion\Inspect-TorrServerMobileReadiness.ps1 -Port 8090`
   Trong ví dụ, **8090 chỉ là giá trị ví dụ**, thay bằng port thực tế. Script không chạy shell ngoài, không thay firewall, không thực hiện HTTP và không in IP mặc định. Khi có listener, nó **không thể xác nhận** kết nối từ điện thoại.
2. Kết nối điện thoại vào **cùng mạng LAN/Wi-Fi tin cậy** với laptop (và Redmi nếu thử điều khiển). Tránh guest Wi-Fi / client isolation, VPN làm mất LAN. Không tắt firewall để vượt lỗi.
3. Trên OMP điện thoại, vào phần cấu hình TorrServer, chọn **Find in network / Tìm trong mạng** hoặc nhập địa chỉ LAN/port hiện có của Windows **trong UI ứng dụng**. Không nhập thông tin server vào GitHub/ChatGPT.
4. Khi có xác thực TorrServer, nhập bí mật chỉ tại UI được tin cậy; không gắn user:pass vào URL/lời nhắn. **Không cài hoặc bật server trên điện thoại**.
5. Mở thư viện TorrServer từ điện thoại và kiểm tra nội dung đã có được liệt kê (không phát sinh tải mới). Nếu tìm thấy nhiều server, kiểm tra tên/host của Windows trước khi chọn.

**Gate:** `G-MOBILE-SERVER` chỉ khi kết nối **từ điện thoại** thành công + đọc thư viện thật. `LISTENER_FOUND` trong preflight Windows chỉ là bước phụ.

## M2. Quản lý và thêm nội dung — nghiệm thu riêng, không tự chạy

1. Dùng catalog đã có trước tiên, kiểm tra category/series/resume nếu chức năng có sẵn.
2. Sau khi M1 PASS, chỉ thử thêm **một torrent/magnet của nội dung có quyền sử dụng** từ giao diện OMP điện thoại (nếu tính năng này hoạt động và API/version cho phép), với thao tác xác nhận **trên điện thoại**.
3. Đối chiếu file đã được thêm ở thư viện TorrServer Windows/OMP Redmi và không tạo bản trùng lặp. Đừng suy một kết quả tìm kiếm nghĩa là đã thêm torrent thành công.
4. Nếu app chỉ hỗ trợ tìm/hiển thị mà không có thao tác thêm đúng với bản đang cài, đặt `G-MOBILE-ADD=BLOCKED` và kiểm tra mã nguồn/API trước; không thay bằng API admin hoặc gọi POST tự động.

**Gate:** `G-MOBILE-ADD` chỉ PASS sau một thao tác được owner xác nhận và chứng kiến trạng thái server thật. Không chạy tải bất kỳ media nào trong unit/CI.

## M3. Ghép Redmi OMP Vietsub như remote (sau M1; có thể độc lập M2)

1. Trên **OMP Vietsub Debug hiện tại ở Redmi**, kiểm tra Settings → `Connect phone` / `Kết nối điện thoại`. Nếu có, TV tạo **mã 6 chữ số**; mã này chỉ nhập trên điện thoại, không gửi vào chat hoặc issue.
2. Trong OMP điện thoại, tìm TV cùng LAN từ mục Catalog/Remote/Settings. Chọn đúng Redmi → nhập mã 6 chữ số **trên điện thoại**. Chỉ chấp nhận chứng chỉ TV thay đổi nếu đã xác minh đó thực sự là thiết bị đã ghép, không tự bỏ qua xác thực.
3. Thử một phim nguồn được phép **đã có trong thư viện**: remote play/pause, seek, đổi tập/track nếu được hỗ trợ; ghi sự khác biệt giữa thao tác điều khiển TV và thao tác chỉ điều khiển player điện thoại.
4. Khi TV Debug không hiện mã, không tìm thấy TV hoặc báo incompatibility, gắn `G-MOBILE-TV=COMPATIBILITY_BLOCKED`, ghi **tên loại lỗi đã làm sạch**, không root, không mở wireless ADB, không replace APK trên Redmi. Mobile→Windows TorrServer vẫn là mục tiêu có thể nghiệm thu độc lập.

**Gate:** `G-MOBILE-TV` chỉ PASS sau ghép và remote thật trên Redmi; không suy từ README upstream.

## M4. Evidence matrix và rollback

| Gate | Evidence chấp nhận | Trạng thái ban đầu |
| --- | --- | --- |
| G-MOBILE-INSTALL | Version/ABI/tên APK/hash + owner thấy app chạy trên điện thoại | NOT_RUN |
| G-MOBILE-SERVER | OMP phone mở được thư viện Windows TorrServer thật | NOT_RUN |
| G-MOBILE-ADD | Owner chủ động thêm một media hợp lệ, xác minh trên Windows | NOT_RUN |
| G-MOBILE-TV | TV hiện pairing, code được nhập cục bộ, remote phát/pause/seek | NOT_RUN |

Nếu có lỗi: không đổi cấu hình TV/Windows. Trước tiên bỏ lựa chọn server sai trong app điện thoại hoặc ngắt kết nối phone→TV trong OMP; nếu cần, gỡ **chỉ OMP trên điện thoại** sau khi chủ thiết bị đồng ý. Không xóa cache/user data của Redmi, không xóa torrent trong TorrServer, không ảnh hưởng P2/P4.

**Chia lane:** P3-MOBILE làm ở nhánh này. P2-SUB-DISCOVERY/OpenSubtitles→Gemini LEAN120 và P4 TV tiếp tục ở chat/PR khác. Tương lai tích hợp với Gateway/ChatGPT chỉ sau khi phone/server/TV gates có bằng chứng thật; không đồng nhất luồng remote OMP với giao thức P4 Vietsub.
