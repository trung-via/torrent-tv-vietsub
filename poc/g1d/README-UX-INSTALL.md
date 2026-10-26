# G1d UX PR #29 — Cài đè APK ARM32 trên Redmi, giữ app-private data

**Trạng thái:** `HUMAN_INSTALL_AUTHORIZED / PROCEDURE_PREPARED / WINDOWS_PREFLIGHT_UNVERIFIED / APK_ON_TV_UNVERIFIED / UX_REAL_TV_UNVERIFIED`. Human phê duyệt ngày **2026-10-26**. Đây là **Draft** chỉ thêm script/quy trình, chưa có thao tác ADB của assistant, không tự cài, không merge code, không publish.

## Bản build đã xác thực

- GitHub Actions run [#40302153992](https://github.com/trung-via/torrent-tv-vietsub/actions/runs/40302153992) — SUCCESS, dedicated `torrent-tv-vietsub-win`, run attempt 1.
- Source PR #29 **`dc62b0aaebea2d6abf55e98a0e9b6d6171e36a92`**. PR #29 vẫn Draft, chưa merge.
- Artifact riêng tư `p1-g1d-ux-pr29-debug-apk`, expires **2026-11-02**. Tải qua trang run GitHub (đăng nhập) rồi giải nén. Chọn **duy nhất `app-armeabi-v7a-debug.apk`**.
- SHA256 của **APK ARM32**, KHÔNG phải ZIP: `8f4df47952d00d75bb6234a7620c4fc41e26995fab263d8d2db60292bc94fd85`.
- APK cũ SEL-01 debug có SHA256 `ae132b6ea76e68dddde5a4632ec2d75c5e94f26bee71e063936520a13af39617`. Kiểm tra **đúng APK cũ đang cài** trước khi thay, không chỉ so file tải về.
- Redmi thật `MiTV-ASTR0` / Android API30 / `armeabi-v7a`, package `com.spacesarmat.omp.test`. SRT gốc checksum `c96fe148c2bac63bc2bfc3768e4b3fc3d280cbbff52ad9cc03aae7679ff82f95`.

## Phạm vi script và các lớp STOP

Tải từ Draft PR chứa tài liệu này file `poc/g1d/G1D-UX-Redmi-Guarded-Install.ps1` vào Downloads trên **chính Windows PC có ADB**. Xem code trước khi chạy.

- `Preflight` **chỉ đọc trên TV**: kiểm duy nhất một ADB device, đúng model/API/ABI, local old/new SHA256, `aapt2` package name, `apksigner` chữ ký đồng nhất, đọc bản **APK đang cài** bằng `adb shell pm path` và `adb pull` về file tạm Windows rồi xác minh đúng **SHA SEL-01 cũ** và chữ ký. File tạm ngẫu nhiên chỉ nằm ở Windows và được xóa sau khi so.
- `run-as` kiểm tra saved registry và SRT gốc, đọc SHA256 registry làm baseline, đảm bảo G1c/G1b marker OFF và không còn backup/discard của 5 bài G1d. Không đọc/export nội dung registry, không hiện serial/url/infohash/credential.
- Nếu TV dùng `split APK` hay quyền ADB không thể `pull base.apk`, hoặc APK cũ không khớp SHA, **STOP**; không bypass, không `pm clear`, không uninstall.
- `InstallKeepData` chạy **lại toàn bộ preflight** và so checksum registry trước gate; yêu cầu Human nhập chính xác `INSTALL G1D UX KEEP DATA`, kiểm lần nữa, rồi **duy nhất `adb install -r`** với APK đã xác minh. Sau khi thấy `Success`, kéo **APK đang cài mới** về file tạm Windows, so SHA256/chữ ký và SRT/registry SHA256 **không đổi**. Không làm gì ngoài update app package.
- `VerifyInstalled` chỉ đọc: kiểm đúng APK mới đã cài, SRT gốc SHA256, registry hiện có, marker/backup OFF. Chạy được sau khi Install thành công mà không cần old APK local.
- **Quan trọng**: Nếu Android/ADB không cho pull APK đang cài, script sẽ chặn cài đặt thay vì đoán. Nếu lỗi sau `adb install -r`, **không chạy lại cài đặt mù**, không tự uninstall/rollback: giữ app data và gửi log STOP đã redacted để xử lý.

## Hotfix PowerShell parser — required before any Preflight (2026-10-26)

An earlier version of the Draft script was **invalid PowerShell source**: the `Read-InstalledApkSha` regular expression was truncated and the tail duplicated. A Human `ParserError` was reported before PowerShell executed the script; **no ADB command or APK installation occurred** in that invocation. The checked-in repaired script is **185 lines**, has exactly one `Read-InstalledApkSha` and one `switch ($Phase)` entry, and fixes the complete installed APK path regex. Source structure reviewed; **Windows PowerShell 5.1 runtime parse is still UNVERIFIED until the Human parser gate below succeeds**.

**Mandatory:** Delete/rename your locally cached **broken** script, download the repaired file from the latest commit on this Draft PR (do not reuse the old Downloads script), and **parse it without executing**:

```powershell
$uxInstall = "$env:USERPROFILE\Downloads\G1D-UX-Redmi-Guarded-Install.ps1"
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($uxInstall, [ref]$tokens, [ref]$parseErrors) | Out-Null
if ($parseErrors.Count -ne 0) {
  $parseErrors | Select-Object Message, Extent
  throw 'STOP: G1D UX script parse failed. No Preflight or install.'
}
'G1D_UX_PS_PARSE_PASS_NO_ADB_RUN'
```

Only after this exact parse gate prints `G1D_UX_PS_PARSE_PASS_NO_ADB_RUN`, run `-Phase Preflight` and send the complete sanitized output. **Do not run InstallKeepData just because parsing succeeds**. Source audit and parser PASS are separate from device baseline verification. Never use `Unblock-File` to suppress the warning instead of checking the source.

## WinPS5 ADB stderr hotfix (2026-10-26)

Human ran a parser-PASS script, reconnected to the Redmi after its IP changed, then ran read-only `Preflight`. It printed `G1D_UX_REDMI_ARM32_DEVICE_PASS`. ADB **pulled 64,780,933 bytes** of the installed package, but Windows PowerShell 5.1 treated normal `adb pull` progress on stderr as terminating `NativeCommandError` under global `ErrorActionPreference='Stop'`. The pull itself is read-only on TV. **No installed APK SHA or registry/SRT check completed; Preflight remains BLOCKED; no install was invoked.**

The patched script now uses `Invoke-AdbCaptured -Argv @( ... )` for **both** read-only `adb pull` and later consent-gated `adb install -r`. Only the native ADB invocation temporarily sets `ErrorActionPreference='Continue'` to collect stderr progress, restoring the original preference in `finally`. Exit code, installed APK path/package/cert/SHA256, checksum and registry guards remain mandatory; no debug setting, data clearing, root access or signature bypass has been added.

**Mandatory new-version gate:** download the script again from this PR's *current* head; give the new download a distinct filename so it cannot be confused with the previous `-FIXED.ps1`. A mere local rename does not update its contents. The new script must contain exactly one `function Invoke-AdbCaptured` and two `Invoke-AdbCaptured -Argv` calls. Run the PowerShell `ParseFile` gate on that **new path** and require `G1D_UX_PS_PARSE_PASS_NO_ADB_RUN`, then run **only** `-Phase Preflight`. Do not invoke `InstallKeepData` before all four Preflight markers have been reviewed. Windows parser and runtime remain **UNVERIFIED** until Human supplies new logs.

## Human-run commands — chạy Preflight trước

Sau khi tải artifact ZIP, giải nén rồi tự xác định đúng đường dẫn file APK ARM32 đã tải (ví dụ biến dưới đây; đổi path nếu vị trí khác):

```powershell
$uxApk = "$env:USERPROFILE\Downloads\p1-g1d-ux-pr29-debug-apk\app-armeabi-v7a-debug.apk"
$uxInstall = "$env:USERPROFILE\Downloads\G1D-UX-Redmi-Guarded-Install.ps1"

# $sel01Apk vẫn phải trỏ tới APK cũ đã audit, SHA256 ae132b6e...
& $uxInstall -Phase Preflight -NewApkPath $uxApk -OldApkPath $sel01Apk
```

Các marker bắt buộc:

```text
G1D_UX_REDMI_ARM32_DEVICE_PASS
G1D_UX_OLD_INSTALLED_SHA_CERT_PASS
G1D_UX_SRT_AND_REGISTRY_PREFLIGHT_PASS
G1D_UX_INSTALL_PREFLIGHT_READ_ONLY_TV_PASS
```

**Chỉ sau Preflight PASS**, đóng VLC/player trên TV và chạy:

```powershell
& $uxInstall -Phase InstallKeepData -NewApkPath $uxApk -OldApkPath $sel01Apk
```

Nhập chính xác `INSTALL G1D UX KEEP DATA`; yêu cầu thấy:

```text
G1D_UX_INSTALL_PINS_AND_DATA_PREFLIGHT_PASS
G1D_UX_ADB_INSTALL_R_SUCCESS_NOT_TV_UX_PASS
G1D_UX_INSTALLED_NEW_SHA_CERT_AND_DATA_PRESERVED_PASS_NOT_TV_UX_PASS
```

Cuối cùng:

```powershell
& $uxInstall -Phase VerifyInstalled -NewApkPath $uxApk
```

Yêu cầu `G1D_UX_VERIFY_NEW_INSTALLED_SHA_CERT_AND_SRT_REGISTRY_PASS_NOT_TV_UX_PASS`.

## Sau cài, thử SMOKE trên Redmi (chưa stage lỗi)

1. Mở tập **A** đã đăng ký trong VLC **phiên phát mới**, **không re-register**: track `P1 G1c - Saved SRT` có, Vietsub tiếng Việt + trạng thái ON đúng; không có thông báo lỗi giả; AV/seek/remote ổn định.
2. Mở tập **B** chưa đăng ký, VLC: không có G1c hay warning, không kế thừa ON của A.
3. Mở lại A: G1c/Vietsub quay lại; app không crash. Ghi **Human PASS/FAIL** cho từng mục, không chụp media private.
4. **Chưa chạy StageMissing/StageBadUtf8/StageChangedValid/StageUnreadable cũ:** các script đó đã khóa vào SHA APK SEL-01 **cũ**, không được bypass. Cần kiểm soát riêng fixture và chứng cứ installed-build trước UX negative tests trên APK **mới**.

**STOP** nếu mất file SRT/registry, signing mismatch, A thiếu track/Vietsub, B bị gán nhầm, crash/AV lỗi, hoặc thông báo giả. Không clear data, cài lại, đổi quyền/marker, cấu hình Windows service/firewall hoặc router để khắc phục mà chưa được phân tích.

**Không khẳng định:** `TV_INSTALL_PASS`, `AC06_UX_PASS`, `EXTERNAL_SRT_E2E_PASS`, `G4_RELEASE_PASS` cho tới khi nhận log cùng quan sát Human trên TV.
