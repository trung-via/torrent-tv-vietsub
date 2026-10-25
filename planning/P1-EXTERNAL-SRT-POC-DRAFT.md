# P1-EXT-SRT-POC — PoC Vietsub rời độc lập nguồn (planning only)

**Ngày:** 2026-10-25  
**Status:** `DRAFT_ONLY / NOT_CANONICAL / NOT_DISPATCHED / E2E_UNVERIFIED`  
**Authority:** Human approved ADR-0006, Contract/PRD in Draft PR #10; chưa được quyền merge hoặc thay đổi Windows/TV/AIOS tự động.

## Mục tiêu

Chứng minh app OMP-derived chạy VLC trên Redmi HyperOS có thể nạp **một phụ đề SRT UTF-8 rời ngoài torrent** mà không mất âm thanh, đúng dấu tiếng Việt, chọn/tắt track và giữ position/tracks qua seek/resume. Không cài SMB hoặc thêm Python agent/service để tạo/dẫn phụ đề trong PoC.

## Gate / Evidence (read-only trước khi sửa mã)

- Kiểm tra SHA của `trung-via/torrent-tv-vietsub/main`, nhánh PR, upstream OMP pin `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, `2160player` submodule, GPL/license/dependencies.
- Target repo đang docs-first; có workflow build upstream thành công `40159082083`, runner smoke `40128964785`, **không phải fork đã nhập source, cũng không phải bằng chứng P1 E2E**. Đánh giá quyền repo/runner/workspace hiện thời trước mutation.
- Nếu đi qua AIOS: fresh canonical Brain Sync, verified NEXT/admission, quyền cross-repo và tuyến dispatch đúng runner app; không tạo official TASK từ alias này.
- Có quyền thử trên TV thật, fixture có bản quyền hợp lệ, không log torrent token/magnet, secrets.

## Scope file tối thiểu (PROPOSED, chỉ sau source import & authorization)

- `android/app/src/main/java/com/spacesarmat/omp/player/VlcEngine.kt`: PoC libVLC `addSlave` với URI an toàn local, không hỏng audio.
- `android/app/src/main/java/com/spacesarmat/omp/player/PlayerEngine.kt` và `PlayerActivity.kt`: bridge tối thiểu và lựa chọn track nếu cần; không xây file browser production.
- `src/player/nativePlayer.ts`/track preferences **chỉ khi bắt buộc** cho bridge/state.
- Android/unit fixtures + report kiểm thử app; không thêm `android/.../smb/*`, service/router/DB, không chỉnh TorrServer, Windows Firewall hoặc AIOS.
- Thiết kế storage mapping `serverProfile+infohash+fileIndex` nếu cần; không lưu credential/media vào repo.

## PoC / Verification theo thứ tự

1. Chọn một fixture video được phép và SRT tiếng Việt UTF-8 do người dùng cung cấp/tự tạo. Copy SRT tới bộ nhớ TV bằng ADB trong phiên test có quyền; nếu unavailable, ghi blocker và trình cách thay thế.
2. Trong OMP VLC, gọi đường import ở runtime hoặc nạp external subtitle lúc mở media, ghi rõ biến thể đã PASS; nếu cần reload bảo toàn time/track.
3. Thử hiện Unicode, off / embedded / external, D-pad, audio, play/pause, seek tiến/lùi, resume/reopen, chuyển episode khác.
4. Negative tests: file missing, corrupt/invalid timestamps, permissions denied, file too large, wrong encoding. Không crash hoặc lộ tên/secret.
5. Thu evidence: Git SHA, APK SHA256, Gradle/test result, firmware/API/ABI, ảnh/video remote & text có dấu, test-case matrix. Mock PASS ≠ Redmi PASS.

## AC và Stop

- AC-1: SRT rời được OMP VLC dùng trên Redmi thật với tiếng Việt đúng dấu và audio nghe được.
- AC-2: D-pad track choice, seek, pause/resume, đúng media key; fallback gốc khi tắt.
- AC-3: file lỗi/permission đều báo lỗi rõ; regression source search/player không phá.
- AC-4: report `EXTERNAL_SRT_E2E_PASS` hoặc `EXTERNAL_SRT_E2E_UNVERIFIED/BLOCKED` trung thực theo evidence.
- STOP: không có source/import/license approval, thiếu runner verification khi cần, AIOS authority unresolved, hoặc phải mở hệ thống/network/SMB để làm test. Không auto-dispatch/merge/release.

## Sau PoC

P1b đo và so sánh local picker/USB, SMB read-only, phone file transfer, phương án ít hạ tầng hơn; Human quyết định nguồn nhập ưu tiên sau. AI Vietsub P2 tạo `.vi.srt` tái dùng importer; TTS audio là PoC khác.