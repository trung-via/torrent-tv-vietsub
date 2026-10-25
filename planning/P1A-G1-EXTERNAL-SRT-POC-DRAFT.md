# P1a-G1 — External SRT PoC handoff (docs-only)

**Status:** DECIDED_PRODUCT_GOAL / PROPOSED_IMPLEMENTATION / G1_E2E_UNVERIFIED / NOT_CANONICAL / NOT_DISPATCHED  
**Date:** 2026-10-26  
**Depends on:** PR #15 frozen P1a AC and ADR-0006 from merged PR #10; PR #11 G0 proof.  
**Scope:** một file SRT UTF-8 hợp pháp **không nằm trong torrent, không được đóng gói trong bất kỳ APK nào**. Chứng minh OMP/VLC trên Redmi thật đọc file, chọn/tắt, giữ hình/tiếng, seek/resume, đúng media binding và negative cases. Không cần SMB/phone/backend/AI/style.

## Snapshot được đối chiếu

- App main: 963f2773a2becfadcb8811b9a33f56c62eb20e00 (docs-first; chưa nhập toàn bộ OMP). PR #15 head tại khi tách nhánh: e152cea0d9d8a54082ce953ae715ad5020856bbb; cần recheck trước bất cứ thực thi nào.
- OMP pinned: 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f; 2160 Player gitlink: 6ba6edd39f5d986ddfae29b5425b8ac0b319844e.
- GitHub Actions G0 #40207544777: Gradle debug build và unit tests thành công; APK integrity được ghi trong PR #11. Không chứng minh G1.
- Human ADB evidence: MiTV-ASTR0, Android 11/API 30, ABI armeabi-v7a/armeabi; universal G0 APK SHA256 d201b2939a9216b0dd68514c6e1ab65d1e0b9877853a70d9114140fe65ea7b7c; ADB install thành công; debug fixture trong app-private có 383 bytes; Human xác nhận nhìn thấy Vietsub và kiểm G0. Chỉ đánh dấu HUMAN_REPORTED_LOCAL_SRT_RENDER_PASS, không lấy làm G1.
- Không ghi IP LAN, đường dẫn home/Windows, device serial, magnet, infohash cá nhân, stream URL hoặc credential vào GitHub.

## Ranh giới proof: không gộp G0 với G1

1. **G1a / external provenance:** tạo SRT bằng công cụ độc lập trên Windows/PC (fixture tự viết, khác rõ G0), ghi SHA256, kích cỡ và cue. Đưa file qua ADB hoặc kênh test đã được Human cho phép vào app-private trên Redmi. Chứng minh file không phải debug asset, không ở trong APK, không phải track torrent.
2. **G1b / external render:** đúng APK G1 riêng với SHA256 và ABI/firmware; VLC nhận file đó qua đường SubFile hiện có. Remote chọn G1/Off/embedded (nếu có), chữ Việt hiển thị; không mất hình/tiếng, pause/seek hai chiều và resume. G0 marker OFF, không để G0 asset đóng vai file G1.
3. **G1c / durable media association:** file được liên kết và lưu lựa chọn theo identity ổn định của phim/tập. Tắt mọi debug test injection, thoát mở lại **cùng phim** vẫn tải đúng file bằng cơ chế dữ liệu lựa chọn thông thường; đổi sang tập/phim khác không tự đính G1. Nếu chỉ re-attach từ hook mỗi lần mở thì báo TEST_INJECTION_ONLY, không được G1 PASS.
4. **G1d / negatives:** file không tồn tại, không đọc được, malformed/timestamp lỗi, encoding sai hoặc quá lớn; không crash, không gắn nhầm và không làm mất hình/tiếng. Lỗi hiển thị/được báo rõ trong PoC; không log secret hay file path nhạy cảm.
5. Chỉ ghi **EXTERNAL_SRT_E2E_PASS (SRT)** khi AC-01…06 trong PR #15 có bằng chứng trên Redmi thật, bao gồm tất cả G1a–G1d. VTT, G2 hot-add, G3 sync sâu và G4 release artifact inspection có nhãn riêng. Nếu thiếu một phần: PARTIAL hoặc UNVERIFIED.

## Candidate HOW tối giản (chưa code, chưa thực thi)

- Tái dùng OMP pinned: NativePlayer.kt có QueueItem(hash, fileIndex, subtitles), SubFile(url,label,ext,lang), PlayRequest(queue,index); PlayerActivity.load() gọi PlayerSession.load(); VlcEngine.refresh() thêm subtitle bằng libVLC addSlave cho các SubFile biết từ đầu. G0 hiện dùng debug helper tạo SRT từ asset rồi chèn vào đúng queue item.
- Thử G1 với **file nhận từ ADB, không có trong APK và không tự tạo từ assets**; app-private storage làm đích thử nghiệm, không yêu cầu quyền storage rộng, SAF, SMB, HTTP service hay phone channel.
- Phần chọn file của người dùng ở P1b. P1a chỉ cần một đường test nhập hợp pháp + lựa chọn track bằng remote. Nạp trước lúc mở phim hoặc reopen an toàn được phép; không biến hot-add thành điều kiện ẩn.
- Nên tách hook dùng để **đăng ký một lần file bên ngoài** khỏi đường runtime nạp lựa chọn đã lưu. Khi test reopen, tắt hook và xác nhận data association còn hiệu lực; nếu thiết kế này đòi cơ chế mới thì chỉ thêm lưu trữ cấu hình nhỏ của app, không lập DB/backend mới.
- Key đề xuất: (server profile ID, torrent hash, file index). Pinned QueueItem có hash và fileIndex; **server profile ID chưa được chứng minh có sẵn trong native PlayRequest**. Phải trace UI → native trước khi code. Nếu key thiếu hoặc không duy nhất, **BLOCKED_MEDIA_BINDING**; không fallback bằng title/filename/URL có thể chứa secret hoặc gán nhầm tập.
- Debug-only test hook mặc định OFF, scoped đúng engine VLC và current queue item. Release no-op; G4 phải kiểm APK release riêng. Không tự thay engine, sửa VlcEngine, luồng web-search, TorrServer hoặc các cấu hình hệ thống.
- G1 không thể thử bằng G0 APK đã có: G0 helper chỉ đọc asset p1-vietsub-utf8.srt. Cần một G1 APK riêng đã build/kiểm checksum và install có phép trước test.

## Đường chuyển file thử nghiệm — chỉ sau khi được phép thao tác ADB

Fixture nên có dòng rất dễ phân biệt, ví dụ: “G1 NGOÀI APK — Đường, Trường, Nguyễn — ă â ê ô ơ ư đ”, 2–3 cue với mốc rõ, video tự tạo/open-license. Ghi SHA256 tại PC và kích cỡ trước khi transfer; so nội dung/hash ở đích khi có thể.

**PROPOSED transfer:** adb push fixture tự tạo tới vị trí tạm của Android shell; copy qua đường ống dưới quyền run-as debug package vào filesDir; xác minh file có thật và byte count. Đây là phương án test trên Android 11 cần probe, **không phải TRANSFER_PASS** cho tới khi lệnh và byte equality đã được kiểm tra. Không sử dụng quyền root, public share, Windows port hoặc credentials.

Để tránh gọi nhầm G0 thành G1: phải ghi manifest asset list của APK G1, nguồn fixture Windows (hash), đích trên TV (hash), cờ G0 OFF và video cue G1 hiển thị sau chọn track.

## Ma trận kiểm thử tối thiểu

| Test | Kỳ vọng | Proof |
| --- | --- | --- |
| T01 Provenance | SRT tự tạo ngoài APK và torrent; PC/TV file hash match | G1a |
| T02 Device/build | Đúng Redmi model/API/ABI, APK variant/SHA256, VLC engine | AC-01 |
| T03 Render | SRT G1 hiện đúng dấu, riêng biệt với G0 | AC-02/03 |
| T04 Track | D-pad chuyển G1 ↔ OFF ↔ embedded nếu có; không có embedded ghi N/A | AC-04 |
| T05 Playback | Hình/tiếng không mất, pause, seek tiến/lùi, resume | AC-05 |
| T06 Reopen | Tắt injection, mở lại cùng phim vẫn đúng file lựa chọn | AC-05 |
| T07 Episode | Đổi sang media khác không gắn G1 sai | AC-05 |
| T08 Missing/unreadable | Không crash, lỗi rõ và không làm hỏng playback | AC-06 |
| T09 Invalid/encoding | Reject an toàn, không treo/giả subtitle | AC-06 |
| T10 Security | Không log token/IP/path nhạy cảm, không mở thêm Windows/TV network service | C5/security |

Mỗi test báo PASS/FAIL/NOT_APPLICABLE/UNVERIFIED, gắn Git SHA, APK hash, firmware, video/hình đã redacted, log chọn lọc (không full logcat chứa media URL). Clip cố định kiểm sync G3 và release artifact G4 lập chứng cứ riêng, không gộp T01–T10.

## File/code scope khi executor được ủy quyền riêng (PROPOSED)

- Chỉ thêm patch G1 cô lập ở poc/g1/ trên repo ứng dụng (không tự nhập OMP vào main). Pin commit/submodule/runner theo G0.
- Android seam dự kiến: PlayerActivity.load() trước PlayerSession.load(), helper Android debug/release variant, app-private file validation và association nhỏ nếu cần; VlcEngine.kt chỉ xem xét khi thực nghiệm cho thấy seam cũ không hoạt động.
- Unit/static checks: sai key/tập, marker OFF, file missing/malformed, filename traversal, file size cap, release no-op. Gradle build/test trên runner riêng khi có quyền; G1 APK + SHA256/manifest; E2E thử riêng trên Redmi.
- STOP nếu phải sửa AIOS-renew, dùng runner AIOS fallback, bypass firmware/DRM, sử dụng nội dung không có quyền, mở SMB/Firewall/WAN, hardcode credentials hoặc không chứng minh identity phim/tập. Rollback bằng bỏ branch/patch của worktree cô lập; không tự merge/release.

## Dependences / trạng thái

- PR #15 chốt AC/UX styling, vẫn Draft; PR #9 P2 cùng sửa Contract nên reconcile trước merge. G1 PR này phụ thuộc nội dung PR #15, nhưng chưa có quyền merge hoặc làm official AIOS TASK.
- **DECIDED:** SRT G1 ngoài APK là acceptance bắt buộc của P1a; style là UX backlog.
- **PROPOSED:** HOW dùng ADB + app-private + reuse SubFile/libVLC; media binding nhỏ. Không chọn nguồn P1b.
- **UNVERIFIED:** ADB external transfer thực, APK G1 build, SPU/runtime, media binding persistent, negatives, TV E2E, G4.
- **BLOCKED:** execution cần verified source/license, workspace/runner riêng và quyền chạy; nếu đi qua AIOS phải fresh canonical NEXT/admission/executor/review/route, không tự dispatch.
