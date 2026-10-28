# ADR-0006 — P1 source-agnostic external subtitle trước khi chọn cách chuyển file

> **Current authority note (2026-10-28):** P1 source-agnostic/G0–G4 của ADR này vẫn giữ nguyên. Mọi tham chiếu bên dưới đến AIOS canonical admission/dispatch/runner chỉ là lịch sử và **được ADR-0007 supersede**. Torrent TV phát triển trên **OMP** (không viết lại Kotlin + Compose + Media3) và có workflow/runner riêng, độc lập AIOS.


**Ngày:** 2026-10-25  
**Trạng thái:** `ACCEPTED_PRODUCT_SCOPE / PROPOSED_IMPLEMENTATION / REAL_TV_E2E_UNVERIFIED`  
**Authority:** Human đồng ý kết luận architecture audit: P1 nhận/hiển thị/quản lý SRT/VTT rời trước; SMB chỉ còn phương án ứng viên.  
**Supersedes:** ADR-0005 ở phần **SMB-first, remote phải duyệt SMB từ laptop và mọi AC lấy SMB làm điều kiện PASS P1**. Giữ ADR-0005 nguyên bối cảnh lịch sử; không xóa quyết định cũ hoặc thay đổi dòng thời gian.

## Context / vấn đề

- OMP + TorrServer Windows/NAS + VLC là baseline; Human đã thử VLC có hình và tiếng trên Redmi HyperOS; chưa có bằng chứng SRT tiếng Việt rời phát thực trên OMP VLC.
- Source OMP upstream pinned đã có đường `VlcEngine.kt` gọi libVLC `addSlave(IMedia.Slave.Type.Subtitle,...)` cho external subtitles **đã biết từ đầu hàng đợi**; nạp file local mới giữa lúc phát, URI permission và state restore chưa nghiệm thu.
- TorrServer `/subs/{hash}/{id}` chỉ phục vụ phụ đề nội bộ torrent; không cho nhập SRT tùy ý từ Windows.
- ADR-0005 đưa SMB Android client, account Windows/ACL/firewall, D-pad folder browser thành yêu cầu P1 trước khi chứng minh player nạp SRT rời là thiết kế quá sớm.

## Quyết định được Human phê duyệt

1. **P1a capability-first:** OMP VLC phải nhận SRT/VTT UTF-8 **ngoài torrent**, hiển thị đúng dấu Việt, chọn/tắt/chuyển track, giữ video/audio khi seek/pause/resume và ghi nhớ đúng movie/episode. Không gắn P1a với giao thức lấy file.
2. **PoC nguồn tối thiểu:** ưu tiên fixture hợp pháp đã nằm trong bộ nhớ TV (chép qua ADB trong thử nghiệm nếu có quyền). Chỉ cần chứng minh live attach hoặc restart an toàn giữ vị trí và âm thanh; UI production và cơ chế chọn source là việc sau.
3. **P1b transport/UX:** chỉ sau khi có kết quả P1a, đánh giá **local/USB SAF picker, SMB read-only, phone file transfer hoặc lựa chọn tối giản khác**. So sánh thao tác, an toàn, Android HyperOS compatibility, phụ thuộc host và công triển khai. Không tự chọn SMB hoặc phone thành default; phải có quyết định Human mới.
4. **Remote:** tiếp tục điều khiển player và track bằng D-pad; việc dùng remote để duyệt file trong Windows SMB **không phải AC bắt buộc cho P1a**.
5. **Giữ AI Vietsub P2:** tách `source text/ASR → dịch/QA → .vi.srt` khỏi đường nạp vào player; PoC dịch SRT offline có thể song song, nhưng E2E phát AI Vietsub trên TV phụ thuộc capability P1a. Thuyết minh TTS/audio riêng sau.
6. **Hạ tầng:** giữ OMP, VLC, TorrServer Windows/NAS, website search hợp pháp, repo và runner riêng; không tự tạo Python HTTP server, SMB share, tài khoản, Firewall service/router/WAN hoặc tự dispatch AIOS.

## Acceptance và kiểm chứng

- `AC1-LOCAL`: một fixture `.vi.srt` SRT UTF-8 rời ngoài torrent được OMP-derived VLC nạp và hiển thị đúng dấu trên Redmi HyperOS thật. Có bằng chứng thao tác và phiên bản APK/firmware.
- `AC2-STATE`: đổi được track rời/track nhúng/tắt; pause/seek/resume/mở lại đúng phim/tập, không lẫn episode khác và không làm mất âm thanh VLC.
- `AC3-ERROR`: không crash và có lỗi rõ cho file không đọc được/malformed/encoding sai/mất quyền; không gây leak secret/đường dẫn nhạy cảm.
- `AC4-PROOF`: source audit, unit/build, thực TorrServer, thực Redmi TV là bốn lớp khác nhau. Mock, mã nguồn `addSlave` hoặc build upstream không được coi là `EXTERNAL_SRT_E2E_PASS`.
- `AC5-CHOICE`: P1b có decision matrix từ kết quả thực và explicit Human choice; trước đó **không có SMB_FIRST_DEFAULT**.

## Thực thi (chưa được dispatch hoặc code)

1. Read-only verify source/submodule/license và baseline build evidence; importer/release thay đổi chỉ qua repo app riêng, branch/PR cô lập.
2. Test `addSlave` local URI ở runtime với mẫu hợp pháp; đưa 1 track vào VLC, test options, seek và audio. Nếu hot-load fail, đánh giá reload preserving state; không viết SMB adapter.
3. PoC acceptance trên Redmi thật; `EXTERNAL_SRT_E2E_UNVERIFIED` tới khi đủ log/screenshot/video không lộ dữ liệu.
4. Chỉ sau đó so sánh nguồn nhập, xin Human quyết định & phê duyệt vận hành riêng nếu cần Windows share/Firewall.

## Risk / Stop / rollback

- Không import source upstream hoặc thay đổi runner/AIOS khi thiếu giấy phép hoặc quyền authoring; alias PoC chỉ là planning label, không phải official canonical TASK.
- Nếu Android URI access/libVLC không thể nạp file rời mà không phá audio/seek, báo `P1A_BLOCKED` và trình Human phương án thay thế, không tự lách bằng backend.
- Không tự mở Windows ports, SMB1/guest hoặc lấy credential, không dùng nội dung chưa có quyền xử lý. Không auto merge/publish.
- Rollback là không merge Draft PR; phần thay đổi docs cô lập trên branch của PR #10.

## Trạng thái khi tạo ADR này

`DECIDED`: mục tiêu P1 source-agnostic, SMB trở lại phương án.  
`PROPOSED`: thứ tự PoC/chi tiết tích hợp VLC, mặc định source vẫn mở.  
`UNVERIFIED`: P1a thực Redmi, transport, phone control E2E, AI output E2E.  
`BLOCKED`: official AIOS author/dispatch cho tới khi có admission và exact repo/runner route evidence.

**PR #9** về AI Vietsub tiếp tục Draft; cùng sửa Contract/PRD/Roadmap nên phải reconcile trước merge.
## Human approval + V1-method findings follow-up — 2026-10-25

Human đồng ý hướng PR #10 với điều kiện không bỏ qua **F-01…F-04** của V1-method desk audit. Phạm vi sản phẩm P1a source-agnostic và P1b chưa chọn transport vẫn giữ nguyên. Xem `planning/P1-V1-AUDIT-FINDINGS.md` và `planning/P1-EXTERNAL-SRT-POC-DRAFT.md`.

- **F-01:** Debug APK fixture render chỉ kiểm G0 `LOCAL_SRT_RENDER`; G1 external file thật độc lập, G2 hot-add có evidence riêng. Không gộp thành `EXTERNAL_SRT_E2E_PASS`.
- **F-02:** Bốn cue Unicode tự tạo không chứng minh hội thoại đúng thời gian. G3 sync dùng clip/mốc riêng; thử media key, đổi tập và reopen khi không còn test injection để tránh false persistence PASS.
- **F-03:** Debug-only source set/asset, default OFF, kiểm bản release không có fixture/hook; rollback rõ, không thêm behavior production mặc định.
- **F-04:** Repo target `main` còn docs-first, upstream build và runner smoke chỉ là historical proofs; source/license/import, runner/AIOS authority, build và TV thật phải qua gate riêng.

Đây là **desk audit V1-method**, không phải V1 authenticated AIOS canonical RESULT, không là Reviewer PASS; phê duyệt PR không cấp quyền tự dispatch/merge bỏ review hoặc sửa Windows/TV.
