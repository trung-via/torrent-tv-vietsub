# P1a — Acceptance criteria chốt bởi Human (2026-10-25)

**DECIDED_PRODUCT_AC / EVIDENCE_PARTIAL / IMPLEMENTATION_UNVERIFIED**

Authority: Human quyết định ngày 2026-10-25 sau khi xem hai ảnh TV tiếng Việt: **nghiệm thu đúng chức năng trước, tinh chỉnh độ đậm/font/viền/shadow để sau**. Bổ sung ADR-0006 và contract; không thay F-01..F-04 hoặc G0..G4 của [PoC plan](P1-EXTERNAL-SRT-POC-DRAFT.md). Đây không phải AIOS canonical TASK, không cấp quyền tự dispatch/merge/release.

## Scope và quy tắc PASS

P1a xác nhận OMP-derived VLC đọc được **SRT rời ngoài torrent và ngoài APK**, hiển thị tiếng Việt, người dùng thao tác bằng remote, có audio/video và state đúng. Trước khi đủ proof thực, **không công bố `EXTERNAL_SRT_E2E_PASS`**.

| Mã | Acceptance quan sát được | Gate / trạng thái ban đầu |
| --- | --- | --- |
| AC-01 | Redmi TV thật chạy đúng APK PoC; ghi APK SHA256, Git/upstream commit, Android firmware/API/ABI, engine VLC, fixture hợp pháp | Preflight; UNVERIFIED |
| AC-02 | File `.vi.srt` **không nằm trong torrent và không đóng gói trong APK**; import từ local TV/ADB test hợp lệ, libVLC nhận file và hiện đúng dòng | **G1 bắt buộc**; UNVERIFIED |
| AC-03 | Tiếng Việt UTF-8 đúng các dấu/Unicode đại diện: `ă â ê ô ơ ư đ Đ`, từ có dấu và nhiều dòng; không mất ký tự, ký tự thay thế hoặc cắt chữ gây khó đọc | G0 có thể hỗ trợ kiểm glyph; G1 phải ghi proof trên file ngoài APK |
| AC-04 | D-pad/Back chọn được subtitle ngoài, tắt phụ đề và quay lại track nhúng **nếu fixture có track nhúng**; nếu không có, ghi `NOT_APPLICABLE` riêng | G1; UNVERIFIED |
| AC-05 | VLC vẫn có hình/tiếng, Play/Pause, tua tiến/lùi, resume và mở lại cùng phim đúng track; đổi phim/tập không gán nhầm subtitle; thử persistence **khi debug injection OFF** | G1; UNVERIFIED |
| AC-06 | File bị thiếu/hỏng, sai encoding, sai cú pháp, thiếu quyền không làm app crash hoặc lộ magnet/passkey/credential; lỗi có phản hồi phù hợp | G1 negative; UNVERIFIED |
| AC-07 | Dùng video/fixture có quyền và cue có mốc kiểm soát để thử thời điểm hiện chữ sau tua; **G3 sync sâu báo riêng**, 4 cue thử glyph không đủ để tuyên bố đồng bộ lời thoại | G3 riêng; UNVERIFIED |
| AC-08 | Hook/fixture PoC chỉ ở debug, default OFF, không thể kích hoạt trong release; xác minh artifact trước bất kỳ release | **G4 release gate**; UNVERIFIED |

**G0**: SRT đóng gói debug rồi chép vào app-private được VLC render trên TV thật ⇒ chỉ `LOCAL_SRT_RENDER_PASS`, không chứng minh import G1.

**G1**: Sau khi toàn bộ AC-01..06 áp dụng (bao gồm ngoại lệ track nhúng nếu không có) được kiểm chứng trên Redmi thật bằng file **ngoài APK**, mới có thể ghi `EXTERNAL_SRT_E2E_PASS` cho **SRT**. `.vtt` là định dạng trong mục tiêu sản phẩm nhưng phải ghi kết quả riêng; SRT PASS không suy ra VTT PASS.

**G2** hot-add lúc đang phát không phải điều kiện bắt buộc của lần nghiệm thu nạp trước khi mở phim; ghi `LIVE_ADD_UNVERIFIED` đến khi có test riêng. **G3** đồng bộ cue kiểm soát và **G4** cô lập debug/release có kết quả riêng, không tự chuyển PASS từ G0/G1. Không coi app release-ready chỉ vì G1 đạt.

## Bằng chứng hai ảnh được Human cung cấp

- **VISUAL_UNICODE_OBSERVED (chỉ mức ảnh tĩnh):** ảnh TV thể hiện các chuỗi tiếng Việt có dấu như `Tạm dừng, tua tới, tua lùi và tiếp tục phát.` và `Đường, Trường, Nguyễn — ă, â, ê, ô, ơ, ư, đ.`. Nhìn thấy dấu; chữ có cảm nhận hơi mỏng.
- Ảnh **không tự chứng minh** ứng dụng/build nào phát, engine VLC, file SRT nằm ở đâu, G0/G1, playback audio, D-pad, seek/resume, cue sync, subtitle source hoặc firmware/API/ABI. Không chép ảnh nhà/TV có phản chiếu hay metadata nhạy cảm vào repository. Nếu muốn dùng làm proof chính thức, cần xác lập provenance/test case và redact phù hợp.
- **UX_STYLE_DEFERRED:** không yêu cầu tăng font-weight, chọn font mới, outline/shadow/background hay tinh chỉnh kích cỡ để tính P1a PASS. Chỉ giữ tiêu chí tối thiểu: text rõ glyph và đủ đọc, không mất/cắt nội dung. Nếu phát hiện chữ thực tế không thể đọc được thì ghi UX defect; lỗi kiểu chữ mỏng đơn thuần **không chặn chức năng**.

## Điều kiện dừng và bàn giao

Không thêm SMB client/phone transport, backend, Windows share, firewall, WAN, AI auto-run trong P1a; không sửa AIOS. Mọi code thay đổi qua repo/runner riêng, sau gate source/license và quyền; nếu dùng AIOS thì fresh canonical admission/dispatch. Thu nhận proof theo **G0, G1, G2, G3, G4** tách nhau; báo `PASS/FAIL/BLOCKED/UNVERIFIED` theo test case và lớp thử (upstream build ≠ target build ≠ Redmi thật).

**Bước kế tiếp:** triển khai PoC nhỏ G0 → G1 theo kế hoạch được phê duyệt thực thi riêng; style là backlog UX sau P1a, không nằm trong acceptance bắt buộc.
