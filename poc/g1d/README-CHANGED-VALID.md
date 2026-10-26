# G1d / AC-06: SRT hợp lệ nhưng nội dung đã thay đổi (SHA256 mismatch)

**Trạng thái:** `PREPARED / NOT_EXECUTED / REAL_TV_UNVERIFIED`. Bài thử riêng sau `missing-file`, `bad UTF-8`, và `bad-syntax` đã được Human nghiệm thu trên Redmi thật. Chỉ thay fixture SRT tạm thời, không sửa mã Android/OMP, TorrServer, Windows network, APK hay registry.

## Mục tiêu

Kiểm tra một file SRT **hoàn toàn hợp lệ** (strict UTF-8, cue số 1, timestamp `00:00:00,000 --> 00:00:02,000`) nhưng có nội dung `G1D_VALID_CHANGED_DO_NOT_REGISTER` và SHA256 **khác SRT đã lưu**. Mã debug `P1G1CSubtitleRegistry.prepare()` đang so sánh SHA256 hiện tại với giá trị đã đăng ký cho từng identity `SavedServer.id + v1 infohash + fileIndex`; nếu không khớp, nó không được thêm track G1c. Đây là **kỳ vọng từ source**, không phải PASS trên TV cho đến khi Human thử.

SRT gốc ngoài APK vẫn ở `files/p1-g1-external.vi.srt`, SHA256 `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`. APK SEL-01 ARM32 đã xác minh trên Windows có SHA256 `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`.

## Phạm vi và bảo vệ

Dùng duy nhất thiết bị `MiTV-ASTR0`, API 30, `armeabi-v7a`, ADB đã được Human cho phép. Bảo vệ `shared_prefs/p1-g1c-subtitles.xml`, không tạo `files/p1-g1c.register` hoặc marker G1b, không viết log torrent hash/magnet/credential.

Script có năm pha:
- `Preflight`: chỉ đọc; kiểm tra Redmi, registry, marker, SHA256 gốc, backup/discard của lần thử hiện tại và các bài thử trước đều không tồn tại.
- `StageChangedValid`: yêu cầu đường dẫn APK có SHA256 chính xác, xác nhận chữ `STAGE G1D VALID CHANGED`. Tạo fixture hoàn toàn hợp lệ, kiểm tra hash rồi đổi tên file SRT gốc sang backup **khác biệt**: `files/p1-g1-external.vi.srt.g1d-changed-backup`; đưa fixture vào đường dẫn gốc và kiểm tra hash cả hai.
- `InspectChangedValid`: chỉ đọc để xác nhận trạng thái staged; **không chứng minh playback**.
- `Restore`: yêu cầu xác nhận `RESTORE G1D CHANGED`; chỉ chấp nhận fixture hiện tại nếu hash đúng; chuyển fixture sang discard riêng, khôi phục đúng backup **trước khi** xóa fixture và kiểm tra SHA256 gốc.
- `VerifyRestored`: chỉ đọc; kiểm tra file SRT gốc, các đường dẫn backup/fixture và registry/marker.

Không uninstall, `pm clear`, xóa registry, cài APK mới, chỉnh router/firewall/service, mở WAN/SMB, chạy AIOS TASK, dispatch workflow hay merge PR. STOP nếu hash sai, có nhiều ADB device, có đường dẫn backup bị chiếm, marker đang chờ hoặc copy `run-as` thất bại. **Nếu Stage đã đi qua xác nhận mà lỗi, giữ nguyên backup và ưu tiên Restore**, không tự xóa/đổi tên thủ công.

## Trình tự Human trên Windows + VLC Redmi

Tải file script từ đúng commit/PR Draft vào `Downloads\G1D-Redmi-ChangedValid-SRT-Test.ps1` và xem mã trước khi chạy. Dán **nguyên từng dòng** trong PowerShell, không chạy riêng các tham số.

**1. Chỉ chạy preflight trước:**

```powershell
$g1dChanged = "$env:USERPROFILE\Downloads\G1D-Redmi-ChangedValid-SRT-Test.ps1"; & $g1dChanged -Phase Preflight
```

Cần đủ ba dòng: `G1D_CHANGED_REDMI_MATCH`, `G1D_CHANGED_BASELINE_PASS`, `G1D_CHANGED_PREFLIGHT_READ_ONLY_PASS`. Nếu thiếu, dừng và báo log.

**2. Sau khi Preflight PASS và đóng VLC:** đảm bảo `$sel01Apk` vẫn là đường dẫn APK SEL-01 ARM32 đã đối chiếu SHA256 ở phiên PowerShell trước; nếu không, xác minh lại đường dẫn/hash trước khi Stage.

```powershell
& $g1dChanged -Phase StageChangedValid -ApkPath $sel01Apk
```

Nhập chính xác **`STAGE G1D VALID CHANGED`**. Chỉ thử TV nếu xuất hiện `G1D_CHANGED_STAGED_HASH_PASS_NOT_TV_PASS` và `G1D_CHANGED_FIXTURE_STAGED`.

**3. Trong lúc fixture đang staged:** từ thư viện, mở tập **A đã đăng ký** bằng engine **VLC** trong phiên phát mới; kiểm tra track `P1 G1c - Saved SRT` **không xuất hiện**, hình/tiếng/remote bình thường, không crash. Không đăng ký lại file bị thay đổi; các track nhúng không liên quan có thể vẫn hiện.

**4. Restore NGAY sau thử nghiệm, dù PASS hay FAIL:** đóng player, chạy:

```powershell
& $g1dChanged -Phase Restore
```

Nhập chính xác **`RESTORE G1D CHANGED`**. Mong đợi `G1D_CHANGED_ORIGINAL_SRT_RESTORED_HASH_PASS`. Sau đó:

```powershell
& $g1dChanged -Phase VerifyRestored
```

Mong đợi `G1D_CHANGED_RESTORED_BASELINE_READ_ONLY_PASS_NOT_TV_PASS`.

**5. Mở lại tập A bằng VLC** mà không tạo marker, kiểm tra track G1c và hai dòng phụ đề tiếng Việt đặc trưng xuất hiện như ban đầu. Có thể thử lại A→B→A nếu cần đánh giá hồi quy.

## Acceptance matrix

| Tiêu chí | Kết quả trước khi Human kiểm tra |
| --- | --- |
| `G1D_CHANGED_PREFLIGHT`: TV, SRT gốc SHA256, registry, markers, backup/fixture | UNVERIFIED |
| `G1D_CHANGED_STAGE`: valid UTF-8 + valid cue + checksum khác, backup đúng hash | UNVERIFIED |
| `G1D_CHANGED_NEGATIVE`: VLC từ chối track G1c trên A, không crash, audio/video bình thường | UNVERIFIED |
| `G1D_CHANGED_RESTORE`: restore hash, VerifyRestored, G1c và Vietsub trở lại | UNVERIFIED |
| `AC06_OVERALL`: còn lỗi quyền đọc và phản hồi lỗi người dùng | UNVERIFIED |
| `G4_RELEASE_ARTIFACT`: binary release không có cơ chế debug | UNVERIFIED |

**Trách nhiệm kiểm chứng:** các dòng script chỉ chứng minh điều kiện dữ liệu; **Human trực tiếp nhìn Redmi** mới có quyền gắn nhãn `REAL_TV_HUMAN_PASS`. Script chưa được chạy trên Windows, TV thật hay CI trong bước chuẩn bị này; audit GitHub nguồn/diff không thay thế test runtime.
