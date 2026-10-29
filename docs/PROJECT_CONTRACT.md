# PROJECT CONTRACT v2.1 — Torrent TV Vietsub (independent, OMP-first, research-aligned)

**Ngày cập nhật:** 2026-10-28  
**Trạng thái:** `DRAFT_FOR_PR_REVIEW` — Human đã quyết định tách hoàn toàn khỏi AIOS; nội dung tài liệu này chỉ trở thành baseline trên `main` sau khi PR được review/merge.  
**Repo sản phẩm:** `trung-via/torrent-tv-vietsub` (PRIVATE).  
**Tên sản phẩm:** **Torrent TV Vietsub**; bỏ hậu tố “— AIOS”.  
**Quyết định liên quan:** ADR-0001 (Windows/NAS + TV client), ADR-0002 (OMP baseline), ADR-0003 (runner riêng, phần AIOS được ADR-0007 thay thế), ADR-0006 (P1 SRT/VTT source-agnostic), ADR-0007 (độc lập hoàn toàn với AIOS). ADR-0005 là lịch sử SMB-first, không phải mặc định hiện hành.

## C0 — Sứ mệnh, North Star và trạng thái bằng chứng

Xây dựng ứng dụng giải trí gia đình trên Android TV/Google TV tương thích, phát media từ magnet/.torrent và các nguồn người dùng **có quyền truy cập/sử dụng**, ưu tiên tiếng Việt, D-pad, resume và trải nghiệm ổn định. Windows PC chạy TorrServer là host mặc định; NAS là lựa chọn khác. TV là client, không phải torrent engine.

**North Star được Human chấp thuận làm hướng nghiên cứu/phát triển, chưa phải tính năng đã nghiệm thu:** người dùng yêu cầu bằng ngôn ngữ tự nhiên, ví dụ “tìm video A khoảng 2K, 8–12 GB, seeders >= 300, phát trên TV, ưu tiên audio/thuyết minh tiếng Việt”; hệ thống chỉ tìm trong nguồn được phép, giải thích chất lượng dữ liệu và xin xác nhận trước khi thêm torrent hoặc chạy xử lý AI. Không cam kết tìm được bản phù hợp, số peer thực, điều khiển TV, hay thuyết minh thời gian thực trước PoC.

**Báo cáo Deep Research ngày 2026-10-28 đã hoàn thành và được đối chiếu** tại RESEARCH_ALIGNMENT_2026-10-28.md, ADR-0008. Các module Gateway/Verifier/AI voice là kiến trúc được đề xuất, không phải code hay E2E đã hoàn tất. Báo cáo đề xuất app Kotlin/Media3 mới nhưng đề xuất ấy **không áp dụng**: Human đã chốt OMP-first.

## C1 — Quyết định đã chốt (DECIDED)

1. **Độc lập AIOS tuyệt đối ở mức dự án:** Torrent TV có repository, backlog, quy trình phê duyệt, CI/CD, runner, workspace, credentials, artifact và release riêng. Không có quan hệ parent/child với AIOS; không gọi AIOS Brain Sync, NEXT, TASK admission, executor, reviewer, dispatch, Runtime journal, router hay canonical authority. Không cần AIOS hoạt động để build, test, release hoặc chạy sản phẩm.
2. **Chỉ tái sử dụng có chọn lọc từ AIOS:** mã nguồn, script, GitHub Actions, tài liệu kỹ thuật hoặc cách cấu hình self-hosted runner có thể được tham khảo/copy **theo từng thành phần**, sau kiểm tra license, provenance, secret, permission, tính tương thích và review PR. Không import nguyên AIOS runtime, không dùng workflow gọi cross-repo AIOS, không sao chép token/secret/runner registration, không tạo runtime dependency. Các workflow hiện có trong repo là tài sản của Torrent TV và phải audit riêng.
3. **Hạ tầng phát:** TorrServer upstream chạy độc lập trên Windows PC (mặc định) hoặc NAS (tùy chọn), qua mạng LAN tin cậy; host phải bật khi xem. Không nhúng binary TorrServer/BitTorrent engine vào APK; không tự viết torrent engine mới.
4. **Nền tảng TV — OMP FIRST:** **sử dụng và phát triển trực tiếp từ OMP upstream**, không xây ứng dụng mới bằng **Kotlin + Jetpack Compose + Media3**. Giữ kiến trúc TypeScript/Preact + Capacitor/WebView của OMP; Kotlin, 2160 Player/AndroidX Media3 và VLC chỉ là các thành phần native **đã có trong OMP**, được bảo trì/tùy biến khi cần. Không thay thế OMP bằng client tự viết trong P0–P1. Mã upstream chưa mặc nhiên được import/đạt build vì đã audit.
5. **Nguồn và tìm kiếm:** giữ khả năng tìm torrent qua website/source adapters của OMP, nhập magnet/.torrent thủ công và cấu hình indexer hợp lệ (ví dụ Jackett/Prowlarr nếu phù hợp). Chỉ thực hiện theo thao tác người dùng và quyền sử dụng/điều khoản từng nguồn. Không vận hành kho phim vi phạm bản quyền, crawler trái phép, vượt DRM, captcha, paywall hoặc hạn chế truy cập.
6. **Trải nghiệm Việt:** giữ player, library, series, history, resume, remote D-pad/Back và chọn audio/subtitle; thêm UI tiếng Việt, nhận diện track `vi/vie/vietnamese` và SRT/VTT UTF-8. Track Việt phải có thật; không giả lập track.
7. **P1 phụ đề ngoài torrent:** theo ADR-0006, chứng minh capability SRT/VTT ngoài APK và gắn đúng media trước khi chọn phương thức chuyển file. SMB, Android picker/USB và phone transfer đều là ứng viên, không có SMB-first mặc định.
8. **AI Vietsub theo yêu cầu là mục tiêu Human đã chọn:** Draft PR #9/ADR-0004 định nghĩa P2 offline local-first timed SRT/VTT translation → ASR fallback → QA → file tiếng Việt. Voice-over/TTS là capability riêng sau Vietsub, opt-in; không tự chạy nền, không cam kết real-time hay cloud upload.
9. **Tách biệt quyền vận hành:** không tự bật GitHub workflow, cài/đổi runner service, sửa Windows Firewall/router/UPnP, mở WAN, root TV, ký/publish APK hoặc merge vào `main` khi chưa có phê duyệt tương ứng.
10. **Release:** APK, tài liệu cài đặt, mã nguồn tương ứng, giấy phép và rollback do chính dự án quản lý; Human là người phê duyệt cuối cùng.

## C2 — Chưa chốt hoặc chưa xác minh

- **PROPOSED:** lớp điều phối bằng ngôn ngữ tự nhiên/ChatGPT và local gateway của Torrent TV; agent chỉ được gửi hành động theo schema và permission đã cho phép, không điều khiển shell tùy ý. Không đồng nhất ChatGPT với AIOS.
- **PROPOSED:** bộ lọc candidate theo độ phân giải, dung lượng, seeders, codec, audio/subtitle và provenance. “2K” mơ hồ (1440p hay DCI 2048×1080); seeders do indexer báo là snapshot, không phải peer thực hay bảo đảm stream.
- **PROPOSED:** chọn nguồn hợp pháp, xếp hạng, xác nhận người dùng, đưa magnet vào TorrServer, điều khiển playback trên TV; chưa có E2E API/TV-control được nghiệm thu.
- **UNVERIFIED:** commit/submodule OMP và GPL/dependency inventory khi nhập vào repo, Android build trên nhánh sản phẩm, bản firmware/API/ABI thực tế của Redmi, tương thích codec/seek, TorrServer deployed version/API/auth, kết nối LAN và external subtitle E2E.
- **UNVERIFIED:** runner hiện tại có online/isolated đúng phiên làm việc hay không; file workflow chứa runner name/labels chỉ là cấu hình kỳ vọng. Đánh giá lại bằng run evidence theo từng đợt.
- **RESEARCH_REVIEWED / IMPLEMENTATION_UNVERIFIED:** nghiên cứu đã có nhưng upstream TorrServer -gst/native /mcp, private MCP tunnel, Redmi firmware, AI Vietsub/voice-over, vendor price, latency/cost và ChatGPT→Gateway vẫn cần evidence chính thức và/hoặc kiểm thực trên hệ thống.

Không dùng trạng thái source-audit, mock, emulator hoặc workflow file tồn tại để tuyên bố `REAL_TV_PASS`, `REAL_SERVER_PASS`, `RUNNER_READY` hay `AGENT_E2E_PASS`.

## C2a — Định hướng kỹ thuật áp dụng từ Deep Research

1. **Control plane:** Optional Home Media Gateway riêng Torrent TV là owner của PlaybackIntent, verification, authorized source policy, confirmation, device/session identity, state machine, telemetry và audit. ChatGPT chỉ được gọi semantic actions; không kết nối raw TorrServer MCP/admin.
2. **Discovery:** Giữ nguyên website/source adapters OMP và manual magnet; thêm Prowlarr/Torznab nếu hợp quyền và cần thiết, Jackett fallback. Torznab là giao thức, không phải nguồn nội dung.
3. **Verification:** tách số seeders reported, scraped và connected (nguồn/timestamp khác nhau), đo rate/buffer; xác minh size/width/height/codec/audio bằng metadata và probe thật. Không suy nghĩa “2K” từ tên; hard constraints không được tự hạ.
4. **Playback:** Gateway session states dự kiến DISCOVERING → VERIFYING → PREPARING → BUFFERING → AUDIO_PREP → READY → PLAYING → DEGRADED/FAILED/STOPPED. Direct HTTP first; remux/HLS/transcode chỉ khi TorrServer deployed build và hardware hỗ trợ.
5. **TV:** nếu thật sự cần device control, mở rộng **OMP native playback components hiện có** với pairing và opaque session/manifest. ADB chỉ dev/test, Cast Connect khi firmware hỗ trợ; không build Kotlin/Compose app mới.
6. **Tiếng Việt:** embedded vi/vie audio có thật trước, external SRT/VTT theo P1, AI voice-over opt-in theo thứ tự pre-generated batch → rolling look-ahead sau đo seek/sync/cost. Không mặc định dùng cloud ASR/MT/TTS và không chọn model/vendor chỉ từ báo cáo.
7. **MCP connectivity:** outbound private MCP tunnel là research candidate, phải xác minh official support/entitlement/security. Không mở inbound WAN/port 8090 để kết nối ChatGPT. Xem RESEARCH_ALIGNMENT_2026-10-28.md và ADR-0008 (proposed).

## C3 — Ranh giới runtime

```text
User/remote/phone ──────────────> OMP-derived TV UI + native player
      │                                      ▲
      ├─ manual magnet/.torrent              │ HTTP media + metadata (trusted LAN)
      └─ optional natural-language agent     │
                    │                         │
              Torrent TV local gateway        │
              (PROPOSED, opt-in)               │
                    │                         │
         allowlisted search/selection ──> TorrServer on Windows/NAS
                    │                         │
              optional AI media worker ───────┘
                 (subtitles/audio assets)
```

- TorrServer API adapter, source-search adapters, TV-control adapter và AI worker là **các trust boundary khác nhau**; không để ChatGPT trực tiếp giữ secret LAN, tracker passkey hay gọi tùy ý vào TV/Windows.
- Gateway (nếu triển khai) là thành phần runtime của **Torrent TV**, không phải AIOS. Chỉ expose các operation hẹp như `search_allowed_sources`, `inspect_candidate`, `request_add_torrent`, `request_play`, `get_status`; mọi hành động có side effect cần confirmation/policy.
- Không đưa AI agent, search crawler hay ASR/TTS engine vào APK TV trong MVP. Hỗ trợ phone remote OMP có sẵn có thể giữ; không tự xây app companion mới P0.
- Chưa pin wire schema TorrServer hay Android TV control khi chưa có thực nghiệm; tham khảo `docs/TORRSERVER_INTERFACE.md`.

## C4 — Ranh giới phát triển và tái sử dụng

```text
Human / Issues / PR / ADR
           │
           v
Torrent TV GitHub repository (PRIVATE)
           │
      GitHub Actions (repo-scoped, least privilege)
           │
Dedicated Torrent TV self-hosted runner + isolated workspace
           │
    test / build / artifact / evidence / optional approved release

AIOS repositories ── optional audited source/template reference only
                   ── NO admission/dispatch/runtime/runner/credential link
```

- Mỗi lần lấy thành phần từ AIOS phải có: source URL + commit, license, file-level diff, lý do, bản địa hóa tên/path/labels, đánh giá quyền, test và rollback. Không đồng bộ tự động.
- Runner phải có scope riêng, identity/labels và workspace không chia sẻ AIOS; không mặc định cùng máy vật lý là cấm, nhưng tài khoản/quyền/đường dẫn/cache/secrets phải cách ly thực sự.
- Workflow dùng SHA-pinned actions, permissions tối thiểu, mặc định manual hoặc PR-safe; không chạy mã PR không tin cậy trên self-hosted runner có secret/quyền host. Không trigger qua AIOS. Chi tiết: `docs/DEVELOPMENT_WORKFLOWS.md`.

## C5 — Pháp lý, bảo mật, quyền riêng tư

- Media/test fixture tự tạo hoặc có giấy phép phù hợp; quyền stream, chia sẻ, dịch, tạo audio phải được kiểm tra theo từng nguồn. Tính năng website search không xác nhận mọi kết quả hợp pháp.
- Không lưu magnet cá nhân, infohash nhạy cảm, tracker passkey, token, URL có userinfo, IP LAN thật hoặc transcript/audio riêng tư trong Git, CI logs hay artifacts chia sẻ.
- OMP được mô tả trong audit là GPL-3.0-only; kiểm tra license upstream/submodule/dependencies tại commit thật trước import/phân phối. Repo PRIVATE không tự miễn nghĩa vụ khi phân phối APK.
- LAN-only mặc định; không public gateway/TorrServer/ADB, không UPnP/port forwarding, không bypass DRM. Bảo vệ API bằng auth/allowlist/rate limit/CSRF phù hợp; credential không xuất hiện trong stream URL/log/redirect.
- AI xử lý audio/subtitle chỉ với nội dung được phép, consent rõ ràng, policy retention/xóa dữ liệu và ước tính chi phí trước khi chạy.

## C6 — Acceptance gates và evidence

| Gate | Tiêu chí PASS tối thiểu | Nếu chưa có |
| --- | --- | --- |
| G-DEV | Repo riêng, branch/PR, workflow scope, runner identity/workspace và job evidence; không phụ thuộc AIOS | `RUNNER_UNVERIFIED` |
| G-OMP | Provenance/license, commit/submodule SHA, clean build/test và APK checksum | `BUILD_UNVERIFIED` |
| G-SOURCE | Website search còn từ UI; nguồn/fixture hợp lệ; lỗi và credential được xử lý | `SOURCE_UNVERIFIED` |
| G-SERVER | TorrServer thật trên Windows/NAS, version/API, stream/seek/Range/auth/offline | `REAL_SERVER_UNVERIFIED` |
| G-TV | Firmware/API/ABI thực, install, D-pad, play/pause/seek/resume/audio/subtitle | `REAL_TV_UNVERIFIED` |
| G-VI | UI Việt, track vi/vie thật, SRT/VTT Unicode đúng phim/tập | `VIETSUB_UNVERIFIED` |
| G-P1 | Tách G0 debug fixture render, G1 file ngoài APK và reopen, G2 hot-add, G3 sync, G4 release isolation; không gộp PASS | `EXTERNAL_SRT_E2E_UNVERIFIED` |
| G-VERIFY | Lawful source → seeder provenance/scrape nếu hỗ trợ → actual media probe → measured throughput/buffer | CANDIDATE_VERIFICATION_UNVERIFIED |
| G-GATEWAY | Session FSM, role/pairing, narrow operations, idempotency, audit, anti-SSRF/prompt-injection, rollback | GATEWAY_UNVERIFIED |
| G-AGENT | Authorized source → metadata/filter → Human confirmation → TorrServer → **OMP** TV playback/status thật | AGENT_E2E_UNVERIFIED |
| G-AUDIO-BATCH | Ưu tiên VI track thật; licensed audio → ASR/MT/TTS→duck/mix batch; seek/sync/cost/privacy QA | AUDIO_BATCH_UNVERIFIED |
| G-VOICE | Rolling chỉ sau batch; look-ahead/seek/underrun/fallback và resource/latency measured, no realtime guarantee | VOICEOVER_UNVERIFIED |
| G-RELEASE | License, secret audit, provenance, signed/reproducible artifact, Human approval | `RELEASE_BLOCKED` |

Các gate độc lập: một job build PASS không chứng minh TV thật; demo agent không chứng minh voice-over real-time.

## C6a — Bằng chứng hiện tại, không được gộp PASS

- PR #37 có Human-reported P0 Windows TorrServer → OMP Redmi playback/seek/reopen smoke PASS ngày 2026-10-27 (issue comment 6444479305). Phạm vi này không chứng minh trọn G-SERVER/G-TV về version/auth/Range/codec/firmware.
- PR #38: GitHub Actions run #40533478080 SUCCESS cho Debug + unit test và Human đã thử import SRT thật. Tuy nhiên G1-SUB-01 FAIL: file SRT đã lưu không tự render sau reopen cho đến khi chọn lại track. G1 E2E và release vẫn BLOCKED. G1-PLAY-01 về tốc độ phát đã được phân loại UNCONFIRMED; không tự thêm workaround.
- PR #9 (ADR-0004 P2 AI Vietsub) và PR #15 (acceptance P1a) vẫn Draft; không merge/rebase tự động. Nghiệm thu AC-01..08, G0..G4, font/style deferred phải được giữ nguyên.

## C7 — Phân kỳ ưu tiên

- **P0 — Foundation:** repo độc lập, workflow/runner audit, OMP feasibility/build, TorrServer Windows LAN và TV thật, manual magnet, player/remote/Vietsub cơ bản.
- **P1 — Subtitle & daily use:** external SRT/VTT source-agnostic, persistence/UX, lựa chọn transport sau evidence, hardening.
- **P2-SOURCE — Search intelligence:** chỉ nguồn được phép, metadata/filter/quality ranking, confirm trước add torrent; không tự động hóa website trái phép.
- **P2-AISUB — AI Vietsub theo yêu cầu:** mục tiêu đã được Human xác định trong Draft ADR-0004/PR #9, PoC offline local-first trên Windows/NAS: có timed SRT/VTT thì dịch từng cue; thiếu timed text mới ASR → dịch/QA → SRT/VTT UTF-8. Không yêu cầu Gateway và không tự triển khai cloud. E2E TV phải qua P1a-G1.
- **P3 — TV control:** local gateway, pairing/authorization, chọn media/play/pause/status qua API được kiểm chứng; ChatGPT integration tùy chọn sau P0/P2-SOURCE.
- **P4 — Tích hợp AI Vietsub:** nối output P2-AISUB vào OMP TV/UX sau khi G1 external subtitle E2E đạt; không lặp lại offline PoC.
- **P5 — AI voice-over:** TTS/align/mix/mux PoC trước, real-time chỉ là giả thuyết cần đo; không mặc định P0–P4 phụ thuộc P5.

Roadmap thể hiện thứ tự phụ thuộc, không cam kết lịch/chi phí. Deep Research đã hoàn thành và được đối chiếu, nhưng ước tính trong báo cáo chưa được hiệu chỉnh cho OMP-first; thời lượng, tài nguyên và hiệu năng thực tế phải đo qua PoC có bằng chứng.

## C8 — Authority và quản trị thay đổi

- Quyết định Human mới nhất > contract được merge trên `main` > PRD > ADR (ADR mới supersede phần nêu rõ) > Architecture > Roadmap > planning/chat drafts. Khi tài liệu chưa merge, phải nói rõ `DRAFT`.
- Issues/PR/ADR, review và GitHub Actions **của Torrent TV** là hệ quản trị duy nhất cho repo này. Không yêu cầu “fresh AIOS Brain Sync”, “canonical NEXT”, “TASK admission”, “cross-repo dispatch” hoặc “AIOS reviewer”.
- Thay đổi lớn (nền tảng client, server, giao thức search, gateway remote access, runner security, AI cloud, licensing, release) cần Human approval và ADR/PR. Việc Human đồng ý hướng nghiên cứu không phải phê duyệt tự bật hạ tầng.
- Không sửa `AIOS-renew` hoặc bất kỳ repo AIOS nào trong một task Torrent TV nếu chưa có yêu cầu riêng và scope cụ thể.

## C9 — Stop conditions, rollback, next handoff

STOP nếu phải truy cập nguồn trái phép/DRM, lộ secret, mở WAN/ADB/SMB/firewall chưa phê duyệt, dùng AIOS runner/credential/runtime, thiếu license/provenance, không rõ repo/branch/runner, hoặc gộp mock với E2E. Rollback bằng PR/commit; không rewrite lịch sử ADR.

**Handoff đầu tiên:** cập nhật `planning/OMP-EVAL-001-DRAFT.md` thành task nội bộ Torrent TV; review trạng thái các Draft PR đang mở trước khi rebase/merge; audit workflow hiện hữu, chạy thử chỉ theo phê duyệt, xác minh TV/server thật. Chưa tự dispatch, build, cài TV hay publish chỉ vì contract được sửa.
