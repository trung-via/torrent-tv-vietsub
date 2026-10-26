# ADR-0004 — AI Vietsub theo yêu cầu, tách biệt thuyết minh

**Date:** 2026-10-25  
**Status:** `DECIDED_FEATURE_REQUEST / PROPOSED_IMPLEMENTATION / E2E_UNVERIFIED`  
**Authority:** Human yêu cầu bổ sung “Tạo phụ đề tiếng việt AI tự động nữa” sau khi đã thảo luận phone remote, external subtitle và thuyết minh. **Đây là phê duyệt mục tiêu tính năng**, không mặc định phê duyệt cloud, backend mới, chạy AI nền, merge hoặc release.

## Context

- Kiến trúc đã chốt: OMP TV + Windows/NAS TorrServer qua trusted LAN; VLC là engine có âm thanh trên Redmi HyperOS theo phiên thử thực tế đã được Human xác nhận; không biến TV thành máy chạy model.
- OMP upstream có phone remote/pairing, track selection; nhưng **chưa có luồng nhập một tệp SRT bất kỳ từ laptop/điện thoại tới OMP VLC đã kiểm chứng**.
- Mục tiêu là dùng AI khi phim thiếu Vietsub, lưu kết quả để không xử lý lặp và cho phép người dùng chỉnh/đổi track.

## Decision — product

1. **AI Vietsub tự động là tính năng cần có trong roadmap**; thực thi chủ động `Generate Vietsub` (opt-in), không tự quét hay chạy theo torrent nền.
2. Trình tự ưu tiên: `vi/vie` sẵn có → dịch subtitle source nếu có → ASR từ audio khi thiếu text → dịch tiếng Việt → hậu xử lý → SRT/VTT UTF-8.
3. **Giai đoạn thực thi:** PoC xử lý local trên Windows/NAS ở P2, không làm thay đổi hoạt động phát phim P0. UI nút trên TV/điện thoại đến sau khi import external SRT có E2E và kênh điều khiển được kiểm thử.
4. **Thuyết minh là một capability khác**, chỉ làm sau Vietsub: TTS, timing, audio replacement/mix, sync seek/pause cần PoC riêng.

## Proposed implementation seams (chưa quyết định thư viện cuối cùng)

```text
OMP TV / phone remote (future user action)
         | control metadata only; paired & authorized
         v
Windows/NAS on-demand tool (PoC: CLI, no background daemon)
  (a) source .srt/.vtt -> translate per cue -> QA/time validation
  (b) legal video/audio -> extract audio -> ASR/transcript timestamps
                             -> translate vi -> QA/time validation
         |
         v
  Local .vi.srt / .vi.vtt UTF-8 + metadata manifest
         |
         v
  Verified external subtitle import -> OMP VLC on Redmi TV
```

- **Input identity:** server profile (local ID), torrent infohash + video file index và fingerprint nguồn (khi có) để ngăn nhầm tập; chỉ lưu trong local metadata, không đưa magnet/tracker token vào log/repo.
- **Output:** transcript/source subtitle và bản `.vi.srt`/VTT; người dùng có thể chỉnh text, offset, ngắt dòng, chọn/bỏ track. Cache theo source fingerprint/model/version; có nút tạo lại khi dịch sai.
- **ASR:** đánh giá `faster-whisper`/model đa ngôn ngữ local trên máy Windows hiện có, đo CPU/GPU trước khi chốt. Whisper `translate` nhắm đến tiếng Anh; **dịch sang vi là giai đoạn model khác**. Có thể dùng MT/LLM local, hoặc cloud **chỉ sau opt-in riêng**.
- **Subtitle source:** nếu đã có timed SRT/VTT nguồn thì không chạy ASR; ưu tiên giữ timestamp của từng cue, không dịch toàn bộ rồi phân bổ thời gian tùy tiện.
- **Data path:** không gửi media/file lớn qua control server OMP JSON hiện tại; companion chỉ hiển thị/chọn track và yêu cầu công việc qua đường được xác thực sau khi thiết kế riêng được Human phê duyệt. Không tự thêm router/DB/service vào MVP.
- **TV:** tận dụng VLC; xác thực MIME/file URI, quyền đọc file, các codec/sub formats và seek/resume trên đúng Redmi thật. Không tuyên bố TV có tính năng nhập SRT ngoài torrent trước khi test.

## Risks / guardrails

- **Content rights:** chỉ nhận đầu vào có quyền xử lý và tạo bản dịch; không vận hành công cụ vượt DRM hay phụ đề từ nguồn không có quyền.
- **Accuracy:** tiếng nền, nhiều nhân vật, ngôn ngữ trộn và tên riêng gây sai ASR/MT. Đánh dấu bản tạo tự động; cho phép review và sửa, không tuyên bố 100% chính xác.
- **Performance:** model weights, VRAM/RAM/CPU/GPU, thời gian đọc stream và các torrent ít seed có thể khiến pipeline chậm. Không tải toàn bộ phim về máy mặc định; đánh giá mức I/O hợp pháp tối thiểu trong PoC.
- **Privacy/security:** mặc định local; không upload audio/sub lên cloud hoặc lưu bí mật trong log/Git; cloud có disclosure/consent riêng. Không mở WAN/UPnP, router, firewall, autorun hoặc background service.
- **License:** rà soát model, package, binary và dependency trước khi phân phối; tuân thủ GPL-3.0 upstream OMP.
- **Rollback:** PoC isolated and opt-in; xóa generated artifacts/config khi người dùng yêu cầu; fallback sang track gốc và VLC playback.

## Verification / acceptance

- `AC-AISUB-SOURCE`: fixture hợp pháp có SRT tiếng Anh → bản tiếng Việt UTF-8, cue count/timing được kiểm tra, ngôn ngữ và tên riêng review thủ công.
- `AC-AISUB-ASR`: fixture hợp pháp không phụ đề, có lời thoại → ASR → dịch → SRT có mốc thời gian hợp lệ, cue không âm/đảo thời gian, ngắt câu có thể đọc.
- `AC-AISUB-TV`: trên Redmi TV thật, OMP VLC đọc bản generated SRT rời, cho bật/tắt, seek/resume, dấu tiếng Việt chính xác. Nếu thiếu external import, báo `BLOCKED`; không suy từ VLC độc lập.
- `AC-AISUB-ISOLATION`: chạy một lần bằng lệnh người dùng, không hoạt động khi chưa opt-in; CPU/RAM/GPU/time measured; không upload dữ liệu, không expose WAN, không thay TorrServer/AIOS.
- `AC-AISUB-PHONE` (sau): paired phone chọn film/generate/status/select subtitle bằng control plane được bảo vệ; command không mang media bytes và không tác động ngoài media đang chọn.

## Status / next steps

- `DECIDED`: mục tiêu AI Vietsub tự động, tách thuyết minh ra sau.
- `PROPOSED`: local-first pipeline, model/tool choices, flow phone/TV, UI, metadata format và AC.
- `UNVERIFIED`: Windows model performance, bản dịch, imports SRT rời, phone TV E2E.
- **Next:** có thể thử dịch timed SRT offline khi được phê duyệt riêng và song song với PoC P1a; **TV E2E chỉ sau P1a-G1** nhập phụ đề ngoài APK thực Redmi. Sau đó mới ASR PoC và UI phone/TV, thuyết minh PoC tách riêng. Human review PR trước merge; không tạo AIOS canonical TASK hay dispatch từ ADR này.

## Compatibility with P1a source-agnostic audit (reconciliation 2026-10-25)

ADR-0006 và `planning/P1-V1-AUDIT-FINDINGS.md` quyết định kiểm chứng P1a theo gate G0..G4. Mục tiêu **AI Vietsub P2** trong ADR-0004 vẫn giữ nguyên, nhưng **không** suy tính năng phát file `.vi.srt` người dùng/AI tạo từ G0: G0 chỉ render SRT fixture trong debug APK; **P1a-G1** phải chứng minh nhập file **ngoài APK**, đúng media và resume trên Redmi thật. PoC dịch timed SRT offline có thể chạy độc lập khi được ủy quyền; full TV E2E cần P1a-G1. Kênh chuyển file (SMB, picker/USB, phone) chưa chốt và phải theo Human decision ở P1b; ADR-0004 không cấp quyền chọn/triển khai giao thức, mở Windows Firewall hoặc chạy AI nền.
