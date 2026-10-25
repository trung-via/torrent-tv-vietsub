# Torrent TV Vietsub — PRD v3.2-P1-PROPOSED (OMP-based / dedicated runner)

**Ngày cập nhật:** 2026-10-25  
**Status:** Human-approved product direction; implementation, real device and real server UNVERIFIED.  
**Authority:** `docs/PROJECT_CONTRACT.md` v1.3 proposed in PR #10 + ADR-0001/ADR-0002/ADR-0003/ADR-0004 (P2 AI Vietsub)/ADR-0006 (P1a; ADR-0005 SMB-first đã superseded một phần). Thay cho PRD v2 đề xuất Kotlin + Compose for TV app từ đầu.

## 1. Mục tiêu

Xây trên OMP upstream một ứng dụng xem video gia đình cho Android TV/Google TV với TorrServer Windows mặc định/NAS tùy chọn, hỗ trợ tìm torrent qua website theo yêu cầu người dùng, thêm magnet/.torrent, thư viện series, D-pad và Vietsub/track tiếng Việt. Chỉ sử dụng nguồn và nội dung được phép. Không biến app thành kho phim vi phạm quyền.

## 2. Quyết định sản phẩm

- **DECIDED:** tái sử dụng OMP TypeScript/Preact, Capacitor, Android Kotlin native player (2160 Player/Media3 + VLC). Không xây Compose for TV client mới ở P0.
- **DECIDED:** giữ website torrent source adapters hiện có trong OMP; các nguồn tìm website và nguồn tự cấu hình hợp lệ (TorrServer/Jackett/Prowlarr) phải còn truy cập được từ UI. Tìm kiếm theo yêu cầu người dùng, không chạy crawler trái phép.
- **DECIDED:** TorrServer Windows PC / NAS riêng, LAN trusted; PC/NAS luôn cần bật khi xem. Không fork engine hay bundle TorrServer binary vào APK.
- **DECIDED:** giữ OMP library, watch history, resume, multiple series/episodes, D-pad, native player, track selection và những tính năng player đã có.
- **DECIDED:** ưu tiên Việt: UI `vi`; track `vi/vie`, SRT/VTT UTF-8; đảm bảo fallback nếu không có tiếng Việt.
- **DECIDED:** repo GitHub PRIVATE, **Git workspace độc lập và dedicated self-hosted runner riêng cho Torrent TV Vietsub**; không dùng runner/Runtime workspace của `AIOS-renew` như môi trường mặc định. Tuyến điều phối AIOS đến runner này phải được xác minh riêng, chưa mặc định là hoạt động.
- **DECIDED:** không đưa billing/paid OMP infrastructure, bot/VPS, tự động theo dõi nền, phone-local TorrServer hoặc TV autostart vào đường mặc định P0. Tách theo dependency, không phá tìm kiếm website. Phone remote/UI có sẵn có thể giữ; không xây companion app mới.
- **DECIDED feature goal (2026-10-25):** AI tạo Vietsub theo yêu cầu. **PROPOSED P2 implementation:** ưu tiên dịch timed SRT/VTT nguồn; nếu thiếu mới ASR audio → dịch Việt → QA SRT/VTT UTF-8 trên Windows/NAS, opt-in, không tự chạy nền; TTS/thuyết minh là bước sau, PoC riêng.

## 3. Người dùng và hành trình

1. Cài OMP-derived APK trên TV/box tương thích; chỉ sau device gate xác minh model/API/ABI/remote.
2. Cấu hình địa chỉ TorrServer Windows/NAS qua LAN. TV không phải nơi chạy torrent engine.
3. Thêm magnet/.torrent qua OMP UI/web UI, **hoặc tìm qua website source** trong OMP rồi chọn nội dung có quyền sử dụng; chỉ khi nguồn/điều khoản cho phép.
4. Duyệt thư viện, chọn phim/series/tập, resume và phát bằng native player.
5. Ưu tiên tiếng Việt nếu có audio/sub track; chọn track, SRT/VTT Unicode, điều chỉnh hiển thị.
6. Nếu lỗi: thông báo phân loại server/network/auth, metadata/peers, decoder/player/subtitles.

## 4. P0 — Feasibility & localized fork

| Workstream | Acceptance |
|---|---|
| Infrastructure | Runner self-hosted **riêng của dự án** có registration/labels, isolated workspace, Git remote và permissions được kiểm chứng; runner readiness có evidence hoặc `DEDICATED_RUNNER_UNVERIFIED` |
| OMP upstream | Commit/submodule/dep lock, build sạch npm/Gradle và APK debug SHA; license GPL provenance |
| Search sources | Website adapters upstream còn trong code và được gọi từ UI; kiểm chứng với nguồn/fixture hợp lệ; không buộc đăng ký dịch vụ OMP trả phí |
| TorrServer | Local LAN configuration, API/seek/player verified thật hoặc `REAL_SERVER_UNVERIFIED` |
| Player | Giữ Engine2160+VLC, D-pad/Back, episode, pause/seek/resume |
| Việt hóa | UI TS và Android native `vi`; track `vi/vie` và Vietsub UTF-8 `.srt/.vtt` trên fixture |
| Security | Không leak credentials từ URL/Basic Auth/log/backup; review permissions và startup/monitor |
| Device | TV/box install & playback evidence hoặc `REAL_TV_UNVERIFIED` / `DEVICE_BLOCKED` |

Trong P0 không viết lại player, không xây AI thuyết minh, không tự mở mạng Internet public hoặc dùng test phim không có quyền.

## 5. P1 — Dùng thường ngày

- Tối ưu dịch tiếng Việt, font, subtitle offset/size, bản audio tiếng Việt được nhớ theo phim/series.
- **DECIDED P1a, phân tầng bằng chứng theo V1 audit:** G0 chỉ PoC VLC render một SRT UTF-8 self-authored từ debug asset vào app-private, khai báo lúc mở phim, đo tiếng Việt Unicode + D-pad + audio + seek trên Redmi thật (`LOCAL_SRT_RENDER_PASS` nếu đủ proof). G1 là thử **file ngoài APK** với track/media binding, lỗi, seek/resume và persistence qua reopen không có debug re-injection (`EXTERNAL_SRT_E2E_PASS` chỉ sau proof riêng). G2 hot-add, G3 sync theo clip/cue kiểm soát và G4 release isolation được báo độc lập. Trước test thực: `UNVERIFIED`; chưa xây SMB/phone transport.
- **PROPOSED P1b:** sau P1a, thử/so sánh Android local file picker/USB, Windows SMB read-only, điện thoại và phương án ít hạ tầng hơn; lựa chọn default UX/transport do Human quyết định sau evidence. Remote vẫn điều khiển phát và chọn track; không bắt buộc duyệt file Windows bằng remote trong P1a. **SMB-first và SMB Android client ở ADR-0005 đã được Human rút khỏi baseline P1** (ADR-0006), không tự tạo Windows share/Firewall/backend.
- Kiểm thử ASS/SSA và PGS riêng; phone gửi file từ LAN là nhánh sau khi đường nạp SRT hoạt động.
- Củng cố LAN reconnect/error UX và phone-to-TV remote vốn có trong OMP; không thêm app mobile mới nếu chưa có bằng chứng.
- Giữ tìm torrent website; dependency isolation và policy quyền truy cập/credential rõ ràng.
- Release APK chỉ sau license/security check, TV thật, Human approval.

## 6. P2 — AI Vietsub theo yêu cầu (opt-in), thuyết minh sau

**DECIDED product goal:** người dùng chủ động yêu cầu tạo Vietsub, có `.vi.srt/.vi.vtt` để chọn sử dụng lại cho đúng phim/tập. **PROPOSED implementation**, chưa chọn model/hạ tầng và chưa triển khai.

1. Nếu đã có track `vi/vie` dùng được: chọn track, không cần AI.
2. Có timed SRT/VTT nguồn: dịch theo từng cue, bảo toàn timing cơ bản và QA ngữ nghĩa/thuật ngữ/ngắt dòng.
3. Thiếu timed text: tách âm thanh hợp pháp trên Windows/NAS → ASR tạo transcript/cue → dịch tiếng Việt qua model khác → QA đồng bộ/timestamp → UTF-8 SRT/VTT.
4. PoC đầu dùng lệnh chạy local khi người dùng yêu cầu; không nền/daemon/listener/DB/router mới. Không gửi media qua remote JSON control plane. Cloud/chi phí/upload chỉ sau phê duyệt Human riêng.
5. **TV E2E:** file AI Vietsub muốn phát trong OMP VLC cần nạp dưới dạng file **ngoài APK** đã được chứng minh tại **P1a-G1**. `LOCAL_SRT_RENDER_PASS` (G0 debug) không đủ. Có thể thử dịch timed SRT offline song song, nhưng chưa gọi full E2E PASS.
6. **Phone UI (sau):** chỉ đánh giá tận dụng OMP paired remote và đường điều khiển bảo vệ quyền; chưa chọn transport hay tự mở Windows/Firewall/SMB.

**PoC acceptance:** hai fixture có quyền (một timed SRT/VTT, một audio lời thoại không timed text), giữ cue có mốc hợp lệ, đánh giá sai dịch/sync thủ công và tài nguyên; chỉ báo `AI_VIETSUB_UNVERIFIED` cho TV đến khi P1a-G1 thực Redmi và phát đúng, không log secrets/media.

**Thuyết minh TTS/audio (P2b về sau):** PoC giọng nói, audio track/duck/mix, căn lời thoại và sync pause/seek riêng; không gộp với kết quả Vietsub. Xem [ADR-0004](DECISIONS/ADR-0004-ai-vietsub-on-demand.md).

## 7. Technical inventory và vị trí thay đổi

```text
OMP upstream (clone/submodule after authorization)
  src/api/torrserver.ts
  src/sources/*               # GIỮ website sources
  src/i18n/*                  # thêm vi
  src/lib/tracks.ts           # vi/vie + filename language aliases
  src/player/trackPrefs.ts
  src/player/nativePlayer.ts
  android/app/.../player/     # 2160 Player/Media3 + VLC
  android/vendor/2160player  # Git submodule
Windows/NAS TorrServer       # external, not vendored
docs/ + planning/            # contract, ADR, AC and evidence
```

Pin upstream OMP và submodule riêng; không tuyên bố snapshot audit là build đã PASS. CI workflows, third-party ops và secret distribution phải được kiểm tra trước khi mang qua target.

## 8. Rủi ro và verification

- **License:** OMP GPL-3.0-only; khi import mã hoặc phân phối APK phải giữ license/attribution và điều kiện cung cấp source tương ứng. Rà soát dependency và third-party notices.
- **Security:** OMP `videoSrc()` hiện có thể gắn userinfo trong URL; đường native/VLC/WebView yêu cầu evidence không leak credential. Không log magnet/passkey/IP/secret.
- **Nguồn torrent:** giữ website search, nhưng kết quả/indexer có thể chứa nội dung không được phép, site có login/captcha hoặc không hoạt động; không bypass truy cập hoặc cam kết mọi nguồn hợp pháp.
- **Runtime:** TV Redmi nội địa chưa chắc cùng Google TV quốc tế; 4K/HEVC/HDR/audio/subtitle cần test thật.
- **Testing:** unit/mock PASS không thay thế TV/server thật. Negative tests server offline/auth/timeout/peers/decoder/subtitles và search source failures.
- **Governance:** `OMP-EVAL-001` chỉ là planning alias. AIOS canonical author/dispatch cần fresh Brain Sync + authorization, target cross-repo isolation **và xác thực tuyến tới runner riêng**, cùng review. Không tự chuyển tác vụ qua AIOS runner khi chưa hỗ trợ dispatch riêng.

## 9. Roadmap / next

Tham chiếu `docs/ROADMAP.md`, `planning/OMP-EVAL-001-DRAFT.md`. Bước đầu tiên: read-only audit → authorized isolated clone/build → thử fixture hợp pháp → đề xuất nhập mã OMP qua PR. Không auto merge, release hoặc thay đổi `AIOS-renew`.

## 10. Tham chiếu upstream

- https://github.com/spacesarmat/omp — OMP, audited commit `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` (snapshot 2026-10-25).
- https://github.com/spacesarmat/2160player — Git submodule/player.
- https://github.com/YouROK/TorrServer — TorrServer streaming host.
