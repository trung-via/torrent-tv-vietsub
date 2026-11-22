# P3-TRIGGER — Khi nào tự động tìm/tải/dịch phụ đề?

**Status:** `SOURCE_POLICY_CANDIDATE` · **không** có event bridge đã cài trên Windows/TV, không có model/provider call.  
**Owner workstream:** [Issue #141](https://github.com/trung-via/torrent-tv-vietsub/issues/141), độc lập với [P3-MOBILE #138](https://github.com/trung-via/torrent-tv-vietsub/issues/138) và nhánh dịch [Draft #140](https://github.com/trung-via/torrent-tv-vietsub/pull/140).  
**Đối chiếu:** 2026-11-14, `main=a946720a39175113dbb149a8e28e4301afaec560` (PUBLIC).

## Nền tảng thực tế và chỗ thiếu

- **Đã có nghiệm thu thực tế do owner báo cáo:** Xiaomi 17 Pro OMP v0.30.0 → TorrServer Windows library/add torrent → Redmi A Pro 55 OMP Vietsub Debug, ghép và remote Pause/Resume/Seek. Đây là `HUMAN_REPORTED_PASS` M0–M3, không phải thiết bị được điều khiển bởi GitHub.
- **Đã có code chưa triển khai:** [PR #140](https://github.com/trung-via/torrent-tv-vietsub/pull/140) cung cấp `AutomaticVietsubFlow.selected_media(video_name)` và owner-process factory `build_owner_auto_flow(...)`, reuse `VI_FAST` / EN→Gemini **4 Hydrogen High** LEAN120 / D2 cache. Tự động sau khi chọn video, **không đòi hỏi Human gõ DOWNLOAD ONE hay chạy CLI cho mỗi phim**, khi user đã cấu hình chế độ tự động một lần.
- **Còn thiếu:** một sự kiện đáng tin cậy từ OMP/TorrServer gắn đúng **server/hash/fileIndex/session**, và tiến trình Windows chạy trong **phiên owner tương tác** (không phải GitHub self-hosted runner Session0 không có key/cache). Chưa có runtime listener hoặc chính thức đẩy VI đã tạo từ #140 sang P4 trên Redmi. Không tuyên bố E2E.
- **Đã có điểm neo mã nguồn OMP upstream pin** `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`: `NativePlayer.kt` định nghĩa `PlayRequest.queue/index/session`, `QueueItem.hash/fileIndex/title/subtitles`; `PlayerSession.load(r)` và `goTo(index)` khởi phát đúng mục media được phát. Một thao tác Play từ điện thoại đã ghép đi đến player trên TV, nên **không cần sửa APK phone upstream** chỉ để phát tín hiệu.

## Tín hiệu chuẩn: OMP_TV_SELECTED_MEDIA

```text
OMP phone Play → Redmi OMP PlayRequest accepted ───┐
OMP TV remote Play → Redmi OMP PlayRequest accepted ├──► AUTHENTICATED TV SELECTED FILE
Redmi đổi tập → PlayerSession.goTo(fileIndex) ──────┘                 │
                                        trusted/validated mapping:  │
                              server + torrent hash + exact file    │
                                                                   ▼
                                 P3-TRIGGER safe event policy gate
                                 ├─ OFF / OTHER: không chạy
                                 ├─ không quyền / media yếu: HOLD
                                 ├─ đã có VI phù hợp: dùng bản sẵn có
                                 ├─ VI track chưa kiểm tra: WAIT
                                 └─ owner AUTO ON + thiếu VI: DISPATCH
                                                                   │
                                               Owner Windows process (private)
                                                                   ▼
                                   existing #140 selected_media(video_name)
                                              VI_FAST → EN → LEAN120
                                                                   │
                                             D3 media/session verified binding
                                                                   ▼
                                          P4 signed revisions → OMP Redmi
```

**Không nhầm ngữ nghĩa event:**

| Event | Xử lý |
| --- | --- |
| Thêm torrent từ Xiaomi | Không tự gọi OpenSubtitles/Gemini; chỉ có thể mở rộng *preflight đọc metadata* sau này |
| Browse/search/catalog | Không làm gì |
| `PlayRequest` được TV tiếp nhận cho file thật | Đánh giá gate, có thể phát động source flow |
| Đổi tập `goTo` sang file khác | Đánh giá lại với `fileIndex` mới |
| Seek, pause, resume, buffering, UI redraw, G2/P4 refresh | Không phát động tìm/tải/dịch lại |
| OFF/OTHER hay người dùng tắt tự động | Không request provider, không tự bật lại trên TV |
| VI track hoặc VI phụ đề đã phù hợp | Không gửi Gemini |
| Thiếu thông tin hoặc không tự tin match release | `HOLD` / `REVIEW_REQUIRED` an toàn, không thanh toán nhầm |
| A→B→A, reconnect, restart | Dùng D2 cache/LEAN120 checkpoint của #140; không POST lại hay dịch trùng |

## Event schema tối thiểu khi nối vào runtime

`event_kind=PLAY_REQUEST_ACCEPTED|NEXT_QUEUE_ITEM_ACCEPTED`, định danh **server cụ thể**, TV session và queue generation, torrent infohash, `fileIndex` trong torrent, **video filename từ nguồn TorrServer đã kiểm tra**, `subtitle_choice=ON|OFF|OTHER`, owner auto setting, quyền xử lý nội dung, trạng thái track VI (PRESENT/ABSENT/UNKNOWN). Tất cả phải cùng thuộc **active TV PlayRequest**.

- **Quyền xác thực:** caller phải thực hiện xác thực thiết bị/phiên và server metadata trước khi tạo event. Trường `attested=True` trong `activation_gate.py` chỉ là assertion để test chính sách, **không chứng minh chữ ký hay TLS**, không bao giờ cho phép JSON gửi từ internet tự đặt trường này. Không dùng raw TorrServer admin, không xuất WAN.
- **Identity:** `hash + fileIndex + server` bảo đảm cùng một tên phim từ hai torrent/server không bị nhầm; `video_name` dùng để khớp release. Mã SHA-256 trong gate chỉ là fingerprint cục bộ cho phân biệt event; **không phải P4 mediaKey đã ký**, không thay D3/P4 validation.
- **Chế độ:** `owner_auto_enabled` là quyết định **một lần** của owner cho nguồn/model. `subtitle_choice=ON` là quyết định hiển thị của người xem trên TV; hai scope này **không đồng nghĩa**. Dù owner đã bật tự động, TV OFF/OTHER phải chặn các lần gọi không cần thiết và áp dụng subtitle; muốn auto ON mặc định cho mọi phim phải có quyết định phạm vi riêng, không tự giả định.
- **Chi phí và bí mật:** KEY của OpenSubtitles/Gemini chỉ ở tiến trình owner-Windows tương tác; nếu provider không có/hết quota thì báo trạng thái, không tự fallback model, không chạy GitHub Actions có media private.
- **Idempotency:** Gate giữ đúng một token phiên gần nhất chống duplicate UI event trong tiến trình; **persistent** retries, one-POST claim và model checkpoint vẫn thuộc #140. Không tạo queue/daemon/translator thứ hai.
- **Race:** A đang tìm/dịch, user đổi sang B thì event generation và P4 exact current identity ngăn bản A gán cho B. A có thể giữ cache riêng; việc hủy tác vụ provider nào thật sự khả thi cần kiểm nghiệm driver/worker, không khẳng định đã cancel.

## Bốn lớp nghiệm thu — giữ độc lập

1. `TRIGGER_POLICY_CI_PASS`: các event giả lập thành công, add/seek/resume/OFF không trigger, nhập sai hash/index bị chặn, A→B→A đúng và không lộ dữ liệu — có thể chạy CI hosted.
2. `TRIGGER_OMP_EVENT_REAL_PASS`: Android OMP Debug trên Redmi phát ra một event thật từ **đúng session + selected file**, đồng thời thao tác Play phát từ Xiaomi phải đi cùng path. Không dùng PlayRequested được tạo bằng mock làm proof.
3. `TRIGGER_OWNER_WINDOWS_LIVE_PASS`: cùng một event duy nhất đến được tiến trình owner Windows có quyền (không phải Session0), gọi **#140** đúng một lần, đọc đúng cache/local profile, không leak log. Synthetic providers trước, provider live theo owner's pre-approved settings sau.
4. `TRIGGER_END_TO_END_REDMi_AUTO_PASS`: đủ source quyền, VI/EN route thực, LEAN120 model thực khi cần, D3 exact media binding và P4 120→240 no-picker trên Redmi; OFF/OTHER, episode-switch, stale replay và cue131; khác G4 Release.

**Không triển khai ở PR này:** OMP Android source patch, Windows service/port/firewall, ADB, provider request, download phim/sub, quyền/cloud upload hoặc P4 TV receiver. Đây là **policy gate chuẩn bị cho một kết nối runtime xác thực**, không phải một auto-Vietsub worker mới.
