# Security, privacy and legal policy — OMP-based

**DECIDED (Human 2026-10-25):** giữ chức năng tìm torrent qua website của OMP; không tự tắt/xóa các source adapters khi tạo fork. Chỉ dùng nội dung được phép truy cập/chia sẻ, tuân thủ điều khoản nguồn. Không vận hành kho phim lậu, crawler trái phép, bypass login/captcha/DRM hoặc đánh cắp access tokens.

- Repository PRIVATE mặc định. Không lưu credential, tracker passkey/token, magnet cá nhân, IP LAN thật hoặc dữ liệu phim có quyền trong git/log/test report/ảnh chia sẻ.
- Website search theo thao tác người dùng, không khởi chạy truy tìm/scraping nền khi chưa được Human ủy quyền. Kiểm thử với nguồn/fixture hợp pháp; không suy một indexer có trong upstream là mọi nội dung của nó được phép.
- Giữ adapter website OMP, khả năng cấu hình nguồn user-owned hoặc hợp lệ (Jackett/Prowlarr/TorrServer); không kéo theo dịch vụ OMP billing/paid VPS/bot mặc định. Khi cô lập module phải bảo toàn source-search flow.
- TorrServer riêng Windows/NAS trong trusted LAN; không public WAN/UPnP/port-forward hoặc thay đổi router/firewall/service/startup mà chưa có Human approval.
- HTTP Basic trên HTTP LAN không mã hóa credentials. OMP `src/api/torrserver.ts:videoSrc()` đưa userinfo vào stream URL và native/VLC xử lý URL: audit logcat, traces, redirect, backup, screenshots, crash/log channels; không publish khi chưa có evidence phù hợp.
- Android permission/receivers: kiểm tra `REQUEST_INSTALL_PACKAGES`, `RECEIVE_BOOT_COMPLETED`, service nền, overlay; không tự bật autostart hoặc background monitor trong MVP.
- OMP GPL-3.0-only, 2160 Player và dependency third-party có nghĩa vụ riêng. Khi dùng/phân phối mã derivative, giữ notices/attribution/license và cung cấp source tương ứng khi được yêu cầu theo GPL. PRIVATE không làm mất nghĩa vụ khi phân phối APK.
- Không vendor TorrServer executable vào APK; pin dependency và xác minh upstream provenance/checksum trước khi chạy installer hoặc công bố build.
- Dùng video fixture tự tạo hoặc CC/open-license, kèm quyền sử dụng; redaction/negative tests cho auth, server offline, torrent no peers, stream errors, subtitle and search failures.
