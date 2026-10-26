# G1d / AC-06 — SRT không có quyền đọc (read-permission negative test)

**Trạng thái:** `PROPOSED / SOURCE_AUDITED / WINDOWS_UNVERIFIED / REAL_TV_UNVERIFIED`. Script mới **chưa được chạy**. Đây là case thứ 5, tách biệt các case G1d đã Human PASS: file không tồn tại, UTF-8 lỗi, cú pháp SRT lỗi, SRT hợp lệ nhưng SHA256 thay đổi.

## Mục tiêu và căn cứ

Mã `poc/g1c/P1G1CSubtitleRegistry.debug.kt` từ SEL-01 kiểm tra `file.isFile` / `file.canRead()` trong `checkedFileDigest()` **trước** khi tính SHA256 và thêm `P1 G1c - Saved SRT`. Dự kiến khi SRT tại đường dẫn gốc tồn tại nhưng app UID không có quyền đọc, G1c **không xuất hiện**, VLC vẫn phát video/âm thanh ổn định, không crash; dữ liệu đăng ký trong SharedPreferences không bị xóa. Đây chỉ là kỳ vọng từ source.

## Cách bảo vệ dữ liệu

**Không chmod file gốc.** Chỉ sau xác nhận riêng:

1. Kiểm tra 1 Redmi `MiTV-ASTR0`/API30/`armeabi-v7a`; `C:\TOOL\Android-SDK\platform-tools\adb.exe`; registry/markers, original SRT digest đúng `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`; không backup/discard G1d cũ còn tồn tại.
2. Move file SRT gốc **giữ nguyên bytes và Unix mode** sang `files/p1-g1-external.vi.srt.g1d-perm-backup`. Không `chmod` hoặc xóa backup này.
3. Copy backup thành bản thử tại đường dẫn SRT gốc, xác minh SHA256 vẫn khớp, **chỉ chmod bản copy thành mode `000`**.
4. Script kiểm tra bằng UID app qua `run-as`: bản thử vẫn là regular file, mode `000`, `test -r` báo không đọc được, backup còn nguyên và đúng hash. Không đọc SHA từ bản thử khi `000` vì đó chính là trạng thái lỗi đang kiểm tra.
5. Sau thử VLC, `Restore` cần xác nhận riêng: nếu bản thử `000`, đổi quyền của **bản thử** về `600` để kiểm tra checksum, chuyển bản thử sang discard, chuyển **chính file backup gốc** trở lại vị trí ban đầu, kiểm tra SHA256 và **đúng mode lưu trong backup** rồi mới xóa discard có checksum chính xác.
6. `VerifyRestored` chỉ đọc; xác nhận gốc readable/hash đúng, không còn backup/discard được script quản lý.

Nếu lỗi sau bước move/chmod, phải ưu tiên Restore, **không xóa/chmod backup** hoặc tự thao tác tay. Restore được thiết kế cho cả trường hợp Stage dừng giữa chừng khi gốc tạm vắng mặt, sau copy nhưng trước chmod, và sau chmod `000`. Nếu Restore cũng STOP, giữ nguyên backup và gửi thông báo lỗi đã loại bỏ thông tin định danh; không `pm clear`, uninstall, cài APK hoặc ghi lại registration marker.

## Human-run protocol (Windows PowerShell)

Tải đúng script của **Draft PR #27** về đường dẫn `Downloads\G1D-Redmi-Unreadable-SRT-Test.ps1`, xem nội dung và chỉ thực hiện Preflight trước.

**Gate 0 — Chỉ đọc:**

```powershell
$g1dPerm = "$env:USERPROFILE\Downloads\G1D-Redmi-Unreadable-SRT-Test.ps1"; & $g1dPerm -Phase Preflight
```

Cần xuất hiện đủ:
```text
G1D_PERM_REDMI_MATCH
G1D_PERM_BASELINE_PASS
G1D_PERM_PREFLIGHT_READ_ONLY_PASS
```

**Gate 1 — Stage, chỉ sau Preflight PASS và khi đã đóng VLC:**

Biến `$sel01Apk` phải trỏ đến file APK ARM32 SEL-01 đã kiểm tra SHA256 `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`; script sẽ kiểm lại checksum, không cài APK mới.

```powershell
& $g1dPerm -Phase StageUnreadable -ApkPath $sel01Apk
```

Khi được hỏi, nhập **chính xác** `STAGE G1D DENY READ`. Chỉ thử trên TV khi có:
```text
G1D_PERM_STAGED_NO_READ_PASS_NOT_TV_PASS
G1D_PERM_FIXTURE_STAGED
```

**Gate 2 — Trên Redmi thật:** mở video **A đã đăng ký** trong phiên **VLC mới** (không dùng lại player session). Xác nhận `P1 G1c - Saved SRT` biến mất; video/audio và điều khiển bình thường, không crash. Không đăng ký lại G1c; video B có thể có track nhúng không liên quan.

**Gate 3 — Restore ngay cả khi case FAIL:** Đóng VLC, chạy:
```powershell
& $g1dPerm -Phase Restore
```

Nhập **chính xác** `RESTORE G1D PERM`. Mong đợi `G1D_PERM_ORIGINAL_SRT_RESTORED_HASH_AND_MODE_PASS`. Tiếp theo:
```powershell
& $g1dPerm -Phase VerifyRestored
```

Mong đợi `G1D_PERM_RESTORED_BASELINE_READ_ONLY_PASS_NOT_TV_PASS`. Mở lại **A bằng VLC**, G1c và hai dòng Vietsub hoạt động như cũ. A→B→A có thể kiểm thêm.

**Không chạy `Restore` khi Preflight/Stage dừng trước xác nhận mà chưa tạo backup.** Nếu Stage đã được xác nhận và script bắt đầu sửa, ưu tiên Restore. Nếu không chắc, báo trạng thái/log trước; không tự sửa quyền file.

## Acceptance / stop conditions

| Case | Điều kiện |
|---|---|
| Preflight | Read-only script checks PASS, không thay đổi data |
| Stage | Backup nguyên bytes + mode; probe copy cùng hash nhưng `000` và thực sự không thể đọc bằng app UID |
| Negative real TV | VLC bỏ G1c, AV/remote ổn định, không crash, không đăng ký lại |
| Restore | Hash gốc + mode đúng, VerifyRestored PASS, G1c/Vietsub trở lại |
| Phân biệt UX | Việc G1c im lặng biến mất **không** chứng minh user-facing lỗi/khôi phục UX; kiểm riêng |
| G4 | Release binary debug isolation vẫn `UNVERIFIED` |

**Không thay đổi** mã Kotlin, manifest, preferences, TorrServer, TV app data ngoài đường thử SRT có bảo vệ, Windows startup/firewall/SMB/WAN, không tạo AIOS TASK/Brain Sync giả, không CI/merge/release. Draft PR không auto merge.
