# Roadmap Torrent TV Vietsub — cập nhật 3 giai đoạn 2026-11-23

**Nguồn đề xuất:** `phase_1_2_3_implementation_guide.md` (Ngài yêu cầu ghi vào roadmap ngày 2026-11-23).  
**Mức hiệu lực:** định hướng sản phẩm đã được Ngài chấp thuận để lập kế hoạch triển khai; các thay đổi mã nguồn, cấu hình máy tính, dịch qua provider và cài đặt TV phải có bằng chứng riêng.  
**Trạng thái:** `ROADMAP_APPROVED / SOURCE_AND_DEVICE_ACCEPTANCE_PENDING`.

## Nguyên tắc xuyên suốt

1. **Một luồng phẳng:** TV Redmi A Pro 55 (OMP) → sự kiện phim/file đang phát → một Windows Owner → AGY chọn/tải phụ đề tiếng Anh **đúng bản phát** từ OpenSubtitles bằng phương pháp AGY tự quyết → dịch EN→VI theo từng phần → P4 LAN có xác thực → VLC/G2 hiển thị không cần chọn file. Tái sử dụng mã nguồn P2/P3/P4; không tạo worker, hàng đợi, receiver hay ứng dụng TV thứ hai.
2. **Vietsub AI duy nhất.** Theo ADR-0011, nhánh chính chỉ dùng AGY tìm/tải EN rồi dịch AI; Vietsub tải sẵn và các nguồn cũ chỉ giữ tương thích/rollback, không xuất hiện thành nhánh kích hoạt `Bật Vietsub AI` thứ hai. Cache chỉ tái sử dụng khi có cùng định danh phim/file/bản phát; bản dịch cũ không được giả làm lần dịch mới.
3. **Đa phim không mất tiến trình:** chuyển A→B không hủy dịch phim A; B có thể chạy riêng; lúc mở lại A gắn vào checkpoint đã lưu. Chỉ P4 được phát cho phiên TV/phim đang hiện hành. `OFF/OTHER` ngắt phát vào phiên cũ nhưng không xóa công việc đã xác nhận hoặc chi tiêu chưa chắc chắn.
4. **Không tái đưa GStreamer vào hệ thống.** Giữ OMP hiện có, TorrServer trên LAN, OwnerBridge và các module Python/Kotlin chuyên trách. Không mở TorrServer ra WAN, không đưa mật khẩu/khóa, magnet cá nhân hay phụ đề phim lên GitHub công khai. Không thiết lập trực tiếp Gemini Developer API trả phí làm đường mặc định; giữ gateway AGY CLI đang xây dựng.
5. Mọi con số latency, quota hoặc năng lực model được nêu trong tài liệu đầu vào là **mục tiêu/giả thuyết cần đo**, không phải PASS. Không hard-code quota OpenSubtitles `5/20/1000` hay mặc định đổi model khi chưa kiểm tra quyền truy cập, tốc độ và chất lượng thực tế.

## Giai đoạn 1 — Phụ đề AI cuốn chiếu trước tiên (Ưu tiên P0)

**Kết quả mong muốn:** sau một lần nhấn `Bật Vietsub AI`, trong **≤120 giây** TV hiển thị đoạn phụ đề tiếng Việt đầu tiên cho phim đang phát; tiếp tục cập nhật tự động đến cuối phim, không đóng/mở lại video. Mốc 30–60 giây trong tài liệu là stretch target, không cam kết.

| Mã | Việc triển khai | Kiểm chứng/đầu ra |
| --- | --- | --- |
| G1.1 | Kiểm tra/sửa lỗi rule đường dẫn tương đối trong `agy --sandbox` trên Windows Owner; sửa cấu hình đúng phạm vi, lưu backup trước khi áp dụng | AGY khởi chạy được trong đúng tài khoản Windows Owner; không mở quyền vượt nhu cầu |
| G1.2 | Từ sự kiện P3 của đúng session/hash/fileIndex, yêu cầu **một AGY job** tìm và tải EN khớp phim trên OpenSubtitles; AGY tự chọn cách tra cứu, đối chiếu release/fps/timeline/độ phủ. Chấp nhận cache EN đã kiểm chứng trước đó | Một yêu cầu hợp lệ → một công việc; EN khớp nội dung và thời gian; không nhầm phim/tập, không gọi tải lặp cùng phim |
| G1.3 | Kiểm toán `automatic_vietsub_flow.py` và Owner wiring; loại bỏ nhánh rẽ sớm làm mất nguồn hợp lệ; tránh cascade API/JWT/AGY nhiều đường độc lập. Có thể tận dụng EN nhúng/sidecar như dữ liệu sẵn có nhưng không làm thành một orchestrator thứ hai | Luồng ưu tiên thống nhất, có log phân loại lý do thất bại, không kẹt vì giới hạn tải/provider |
| G1.4 | Rút cửa sổ dịch đầu xuống **50 cues** bằng tùy chọn `first_window_cues=50`, các cửa sổ sau **120 cues**; vẫn giữ LEAN120/checkpoint/timeline/schema QA và khả năng phục hồi. Benchmark profile AGY nhanh, không tự cố định `gemini-3.8-flash-low` | Gói đầu xuất sớm; các revision tiếp theo tích lũy 50→170→290… hoặc kích thước hợp lệ tương ứng; không trùng/mất cue |
| G1.5 | Kết nối kết quả từng cửa sổ vào P4→OMP G2/VLC hot reload; lưu checkpoint theo phim, bảo toàn A→B→A; phân biệt P2 ready, P4 ACK và cue thực hiển thị | Real Redmi: phụ đề đầu ≤120 giây, nối tiếp liên tục, chuyển phim an toàn, không cần picker |

**Thứ tự triển khai:** G1.1 → G1.2/G1.3 → G1.4 → G1.5. Chỉ bắt đầu kiểm thử G2 sau khi mạch G1 có bằng chứng thật; không chạy lại toàn bộ bộ test khi bằng chứng exact-head còn giá trị. Đo `t_TV_tap`, `t_EN_matched`, `t_VI_first_checkpoint`, `t_P4_ACK`, `t_VLC_visible` và độ phủ 5–10 phút đầu phim. `PASS` chỉ khi quan sát trên Redmi thật, không suy từ unit tests.

## Giai đoạn 2 — ChatGPT chọn nguồn phim theo mạng và prefetch (Ưu tiên P1)

**Kết quả mong muốn:** người dùng yêu cầu phim có quyền truy cập → ChatGPT đề xuất nguồn/phát hành phù hợp → người dùng xác nhận → GitHub Actions runner riêng gọi TorrServer **loopback** trên laptop → Owner khởi động tìm/dịch EN sớm; khi bật TV, phụ đề đã được chuẩn bị một phần.

| Mã | Việc triển khai | Kiểm chứng/đầu ra |
| --- | --- | --- |
| G2.1 | Tạo bộ đánh giá nguồn hợp pháp theo độ phân giải, size, seed, codec, release và bitrate ước tính; các preset `fast-1080p`, `quality-1080p`, `4k-hdr` chỉ là cấu hình khởi đầu, phải đo tốc độ mạng và buffer thực tế | Gợi ý 1–3 bản với giải thích chất lượng, tốc độ và độ chắc chắn; không gắn seed count vào cam kết tốc độ |
| G2.2 | ChatGPT nhận yêu cầu rõ ràng và xác nhận nguồn trước khi thêm; workflow_dispatch/HostOps trên `TorrentTV-Runner` phải kiểm tra đúng chủ tài khoản và tham số; không có kênh điều khiển WAN trực tiếp đến TorrServer | Bản được xác nhận xuất hiện trong TorrServer Library đúng phim/tập, không add trùng |
| G2.3 | Đọc metadata `POST /torrents` thật, xác nhận fileIndex/hash/video chính thay vì chỉ chọn file lớn nhất không kiểm tra; phát một `TTV-OWNER-VIDEO-EVENT-V4` idempotent để prefetch EN + checkpoint dịch trước | Event hợp lệ tạo đúng một prefetch, không giả mạo nút bấm TV; không kéo theo P4 sang session khác |
| G2.4 | Đo thời gian ChatGPT→Library và thời gian tạo checkpoint; bước mở ứng dụng TV bằng ADB chỉ là lựa chọn về sau, không tự chạy | Mục tiêu phim có trong Library ≤30 giây trong môi trường đã sẵn sàng; thời gian prefetch đo độc lập |

**Giải quyết xung đột kích hoạt:** lệnh ChatGPT **đã được người dùng xác nhận** là yêu cầu riêng cho prefetch; không phát Vietsub lên TV và không tự bật phim. Nút `Bật Vietsub AI` trên TV vẫn là tín hiệu ràng buộc phiên phát P4.

## Giai đoạn 3 — Thuyết minh AI tiếng Việt cuốn chiếu (Ưu tiên P2, sau G1 real-TV PASS)

**Kết quả mong muốn:** sau khi có các `SubtitleRevision` tiếng Việt hợp lệ, sinh giọng đọc và gắn vào timeline từng đoạn, mục tiêu nghe được đoạn đầu trong **≤5 phút**; không remux cả phim và không chuyển TV sang app khác.

| Mã | Việc triển khai | Kiểm chứng/đầu ra |
| --- | --- | --- |
| G3.1 | Prototype TTS giọng Việt với Edge-TTS, Gemini TTS hoặc giọng offline, benchmark tốc độ/chi phí/độ tự nhiên/quyền sử dụng trước khi chọn mặc định | Sinh lời đọc từ revision 1 có transcript, chất lượng nghe chấp nhận được |
| G3.2 | Time-align từng cue; nén tốc độ nhẹ khi thoại dài (giới hạn thử nghiệm xấp xỉ 1.25x) và xử lý chồng tiếng; trộn âm ducking mức thử nghiệm 25–30% khi đọc và hồi 100% khi im lặng, tùy chỉnh theo nghe thực tế | Không lệch lời khi pause/seek/chuyển phim, không méo giọng/âm nền đột ngột |
| G3.3 | Thử **A: LAN local streaming proxy/HLS** dùng `ffmpeg -c:v copy` và audio segment, **B: external audio track** chỉ khi player OMP hỗ trợ hot attach; chọn theo kết quả Redmi thật | Bảo toàn video/âm gốc/seek, không cần GStreamer, không phải tải/remux toàn bộ phim |
| G3.4 | Tích hợp chế độ bật/tắt thuyết minh với đúng phiên phát; đo từ TV tap tới âm thanh đầu tiên, thời gian tạo mỗi segment, drift và CPU/RAM | Real Redmi nghe segment đầu ≤5 phút sau yêu cầu trong điều kiện được đo; fallback về âm gốc nếu chưa sẵn sàng |

## Phụ thuộc, ưu tiên triển khai và bằng chứng

1. **Ngay:** gắn G1 vào một candidate source duy nhất, rà soát AGY/Owner hiện có và sửa lỗi không nhận event, chỉ thêm bước cần thiết. Đặc biệt không đánh đồng local mock/test với live provider/TV.
2. **Sau G1 PASS trên Redmi:** bắt đầu G2 ChatGPT→runner→TorrServer→prefetch; G3 chỉ bắt đầu khi phụ đề cuốn chiếu G1 có bằng chứng ổn định. G2 và G3 có thể nghiên cứu song song nhưng không được che lỗi G1.
3. **Trước deploy:** kiểm tra source đang chạy, P2 in-flight/unknown-effect, APK hash và cache người dùng; không restart Owner, xóa cache hoặc cài đè TV khi một dịch vụ đang chạy/đang trả phí.
4. **Báo cáo theo cổng riêng:** `SOURCE_IMPLEMENTED`, `CI_PASS`, `LIVE_AGY_PASS`, `LIVE_TORRSERVER_PASS`, `P4_ACK_PASS`, `REAL_REDMi_PASS`, `RELEASE_PASS`. Mỗi cổng phải có timestamp/ref/source SHA; mục tiêu latency không tự trở thành PASS.

## Đối chiếu quyết định và hiện trạng lúc ghi roadmap

- Repo `trung-via/torrent-tv-vietsub` PUBLIC, `main` `25f4112b3e537d6cc9d5ab8e249e2725ec5c4b0e` khi đọc ngày 2026-11-23.
- [Issue #170](https://github.com/trung-via/torrent-tv-vietsub/issues/170): kiến trúc FLAT được chấp thuận 17/11; [Draft #173](https://github.com/trung-via/torrent-tv-vietsub/pull/173): gateway AGY CLI thay direct-billed Gemini API; [Draft #179](https://github.com/trung-via/torrent-tv-vietsub/pull/179) và [ADR-0011](https://github.com/trung-via/torrent-tv-vietsub/blob/fix/p2-dual-candidates-20261122/docs/DECISIONS/ADR-0011-agy-english-one-path.md): đường hiện hành chỉ AGY→EN→AI, còn downloaded VI/dual source là tương thích không kích hoạt; bảo toàn A→B→A. Các Draft này là mã nguồn ứng viên, **không phải bằng chứng đã cài đủ trên Owner/Redmi**.
- Quyết định bổ sung 22/11: yêu cầu AGY tự tìm đúng EN trên OpenSubtitles, tải và dịch, chỉ ràng buộc kết quả khớp phim; không áp đặt phương pháp search. Tài liệu 3 giai đoạn đề xuất cascade API/JWT và đổi mặc định model nhanh nhưng **không tự động thay thế quyết định mới hơn**.
- Cổng sát nhất: `G1.1–G1.3` vào current flat candidate, nghiệm thu phim thật → `G1.4–G1.5`, sau đó mới mở G2/G3.

---

## Lộ trình v3.1 cũ (lưu đối chiếu — đã được ưu tiên mới thay thế)

# Roadmap v3.1 — Torrent TV Vietsub OMP-first, research-aligned

**Ngày:** 2026-10-28  
**Trạng thái:** `DRAFT_FOR_PR_REVIEW`. Đây là backlog riêng của Torrent TV, không phải roadmap/canonical TASK của AIOS. Hướng North Star đã được chọn và Deep Research ngày 2026-10-28 đã được đối chiếu; thứ tự kỹ thuật vẫn phụ thuộc evidence trên OMP/TorrServer/Redmi thực tế.

| Ưu tiên | Workstream | Phụ thuộc | Exit gate |
| --- | --- | --- | --- |
| P0a | Project governance độc lập: contract/ADR/PRD/architecture, workflow inventory, provenance AIOS reuse, GitHub runner isolation | Human review PR | Không có AIOS admission/dispatch/runtime; repo/runner/PR policy riêng |
| P0b | **OMP-first** feasibility: pin upstream + 2160 submodule, GPL/security, website adapters, clean build, APK hash; **không dựng Kotlin + Compose + Media3 app mới** | P0a, authorized runner | G-OMP PASS hoặc blocker có evidence |
| P0c | TorrServer Windows/NAS LAN + Redmi TV: media legal, D-pad, play/seek/resume, Vietsub | P0b, device/server permission | G-SERVER + G-TV + G-VI độc lập |
| P1a | External SRT/VTT capability: G0 debug fixture → G1 ngoài APK → G2 hot-add (nếu khả thi) → G3 sync → G4 release isolation | P0c/player proof | G1 E2E và từng gate riêng; không false PASS |
| P1b | Chọn transport: Android picker/USB, SMB read-only, phone transfer hoặc khác | P1a G1 | Decision matrix + Human ADR; không tự mở SMB/firewall |
| P2-SOURCE | Lawful source search intelligence, metadata/filter/rank (resolution/size/seeds/codec/vi) | P0 + source/ToS proof | Search smoke + candidate confidence + explicit confirmation |
| P2-AISUB | Human-decided on-demand Vietsub goal in Draft PR #9; translate timed SRT/VTT first, ASR→translation/QA if source text unavailable; offline local-first CLI | Licensed fixtures; no Gateway dependency, TV E2E requires P1a G1 | SRT/VTT UTF-8 cue QA, resource/cost/privacy and user opt-in |
| P3 | Torrent TV local gateway + TV pairing/control + optional ChatGPT interface | P2-SOURCE, real TV API proof, security review | Real E2E search→confirm→TorrServer→TV + negative tests |
| P4 | Integrate P2-AISUB Vietsub outputs into OMP TV UX (not a duplicate CLI PoC) | P1a-G1 real external subtitle import and rights/consent | Real Redmi selected track/reopen/seek/cue sync with generated SRT/VTT |
| P5 | Opt-in AI voice-over: TTS/align/mix/mux; real-time feasibility separate | P4 + player/audio proof | Sync/seek/quality/latency/cost measured; no real-time claim without proof |

## Research-aligned incremental backlog (not dispatched)

1. **R0 — Evidence pin:** OMP and 2160 vendor SHA, license/credential audit, clean APK build; exact Redmi A Pro 55 China firmware/ABI/codecs/Cast; deployed TorrServer version/API/auth. No source or firmware proof by product name.
2. **R1 — Direct playback:** legal torrent/video fixture, TorrServer Windows LAN -> OMP TV, start/seek/resume/audio/UTF-8 subtitle; measure real buffer/rebuffer. Remux/HLS -gst optional only after version/build checks.
3. **R2 — Discovery/verification:** retain OMP website adapters; optional Torznab/Prowlarr/Jackett and lawful source policy, distinct reported/scraped/connected seed provenance, explicit 2K pixel policy and ffprobe. Gate G-VERIFY.
4. **R3 — Gateway/session:** candidate, role/permissions, idempotent FSM, adaptive readiness, authenticated pairing/device status; Python FastAPI/Pydantic + SQLite is candidate stack, not an irreversible decision. Gate G-GATEWAY.
5. **R4 — OMP TV extension:** session ID + short-lived ticket + authorized manifest, native player deep-link/WSS/MediaSession only after OMP/device proof. No separate Kotlin/Compose app; Cast Connect conditional. Gate G-AGENT.
6. **R5 — Vietnamese:** embedded vi audio / P1 external SRT first; licensed multilingual ASR -> MT -> TTS -> duck/mix **batch**, test sync/seek/quality/privacy/cost. Gate G-AUDIO-BATCH.
7. **R6 — Advanced optional:** rolling look-ahead 30–60s with seek/catch-up fallback; ChatGPT semantic MCP after official private connectivity/auth verification, no raw TorrServer /mcp; no realtime target. Gates G-ROLLING, G-MCP.

**Recommended sequence:** existing OMP/direct play -> P1 G1 real-TV repair -> P2-SOURCE verifier -> optional Gateway/control -> VI audio + batch voice-over -> optional rolling/ChatGPT MCP. P2-AISUB offline timed-subtitle translation can be separately scoped in parallel without Gateway, but TV E2E still depends on G1. Manual playback and P1 do not require AI layers.

**Timeline caution:** Research estimated 6–10 weeks / 54–103 person-days for a broad POC *including development of a separate native TV app*. This estimate cannot be copied unchanged into the OMP-first project and is not a commitment. The 2–4-week POC below is a smaller playback-first slice only. See RESEARCH_ALIGNMENT_2026-10-28.md and proposed ADR-0008.

## Current measured status — 2026-10-28

- PR #37 Human Windows TorrServer → Redmi OMP playback smoke PASS for the tested setup. No need to repeat without changed environment.
- PR #38 Debug/unit build PASS (Actions 40533478080), but real-TV external-SRT G1-SUB-01 is a confirmed blocker: track must be selected manually again after reopen. G1-PLAY-01 speed concern is UNCONFIRMED; do not add speculative rate fix.
- Priorities: fix G1-SUB-01 with late-track regression test in PR #38, then independently approve build and Redmi acceptance. Keep PR #39 docs-only and PR #9/#15 decisions intact.

## Minimal playback-first PoC 2–4 tuần (PROPOSED, không cam kết)

- **Tuần 1:** workflow/runner readiness, OMP clean build, license/credential audit, device inventory.
- **Tuần 2:** TorrServer Windows → TV thật, legal fixture, D-pad, seek/resume, SRT/VTT; phân tách server/TV evidence.
- **Tuần 3:** nguồn tìm kiếm hợp pháp và candidate metadata/filter PoC, không tự thêm torrent.
- **Tuần 4:** chỉ nếu P0/P2 PASS, thử gateway và TV-control adapter với confirmation; nếu thiếu API/firmware, ghi BLOCKED.

## Workflow / release gates

- GitHub Actions riêng của Torrent TV, self-hosted runner/workspace riêng. Mẫu mã từ AIOS chỉ reuse theo PR, provenance/license/secret audit; không dùng AIOS runtime/Brain/TASK/dispatch.
- Manual-only hiện là lựa chọn an toàn cho job có quyền host; mở rộng PR CI cần threat review, không chạy untrusted PR trên self-hosted runner có secrets.
- Không auto merge, publish, ký APK, thay đổi Windows/network hoặc điều khiển TV từ chat chỉ vì roadmap được duyệt.

## Legacy và trạng thái

`OMP-EVAL-001` vẫn là **planning alias nội bộ**; `TVAPP-001` Kotlin/Compose shell đã bị ADR-0002 supersede. Các nhánh P1/G0/G1 và Draft PR đang mở là công việc có lịch sử riêng, phải review/reconcile trước merge. Trạng thái runner/build/Redmi/TorrServer cần fresh evidence theo commit/run cụ thể; không suy PASS từ tên PR/workflow. Tham chiếu `PROJECT_CONTRACT.md`, `ARCHITECTURE.md` và ADR-0007.
