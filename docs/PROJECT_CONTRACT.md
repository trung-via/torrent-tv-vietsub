# PROJECT CONTRACT v1.1 — Torrent TV Vietsub (OMP-based)

**Repo:** `trung-via/torrent-tv-vietsub` (PRIVATE, đã tạo)  
**Product:** Torrent TV Vietsub — AIOS  
**Ngày khởi tạo:** 2026-10-15 · **Human change approval:** 2026-10-25  
**Trạng thái:** `DECIDED_PRODUCT_DIRECTION / IMPLEMENTATION_UNVERIFIED` — Human chọn kế thừa OMP, **giữ tìm torrent qua website**; chưa clone/build APK trên target repo, chưa nghiệm thu TV/server thật.  
**ADR:** [ADR-0001](DECISIONS/ADR-0001-client-server.md) (Windows/NAS vẫn giữ), [ADR-0002](DECISIONS/ADR-0002-omp-baseline.md) (chuyển client sang OMP).  
**Ranh giới:** Contract sản phẩm này không thay canonical authority, admission, executor, review hoặc publish của `AIOS-renew`.

## C0 — North Star

Ứng dụng xem video gia đình từ magnet/.torrent mà người dùng có quyền truy cập, tối ưu cho Redmi/Xiaomi A Pro 55 (2026) hoặc Android TV/Google TV box tương thích: dễ thao tác bằng remote, phát/tua/resume ổn định, phụ đề tiếng Việt Unicode, lựa chọn bản lồng tiếng và xử lý lỗi rõ ràng. Kết quả được đo bằng test thực tế trên thiết bị và server, không bằng số tính năng hoặc số TASK.

## C1 — Quyết định sản phẩm đã được Human phê duyệt (`DECIDED`)

1. **Client–server:** Windows PC chạy TorrServer là mặc định; NAS là phương án triển khai thay thế. Server phải bật khi xem. TV là client; không viết BitTorrent engine mới.
2. **Nền tảng client:** kế thừa [OMP upstream](https://github.com/spacesarmat/omp) thay cho khởi tạo một client Kotlin + Compose for TV mới. Giữ kiến trúc OMP hiện có: **TypeScript/Preact + Capacitor/WebView cho UI, Android native Kotlin, 2160 Player/AndroidX Media3 và VLC fallback**. Không viết lại UI Compose trong MVP. Việc clone/import mã thực tế chỉ sau feasibility/build, provenance và license gate.
3. **Player:** tái sử dụng OMP playback, D-pad, library, series, resume, lựa chọn audio/subtitle, engine Auto/Built-in/VLC. Giữ seam hiện có giữa UI, TorrServer API và player; khi cần nâng cấp chỉ patch nhỏ, test được.
4. **Nguồn torrent:** **GIỮ tính năng tìm torrent qua website và các adapter nguồn hiện có của OMP**; KHÔNG tự tắt/xóa chỉ vì chuyển sang fork. Giữ khả năng nhập magnet/.torrent và cấu hình tìm kiếm bằng các nguồn người dùng có quyền truy cập (kể cả nguồn website/Jackett/Prowlarr phù hợp). Việc tìm kiếm, đăng nhập, tải dữ liệu phải tuân thủ quyền sử dụng và điều khoản nguồn; không triển khai crawler trái phép, vượt DRM, bypass truy cập hoặc chỉ mục phim lậu do dự án vận hành.
5. **Server:** sử dụng TorrServer upstream ngoài APK trên Windows/NAS, qua LAN. Không bundle TorrServer binary vào APK; tính năng chạy TorrServer trên điện thoại có sẵn trong OMP không thuộc MVP của sản phẩm này.
6. **Vietsub P0:** ưu tiên track tiếng Việt nhúng và sidecar SRT/VTT UTF-8; thử ASS/SSA qua player VLC khi phù hợp, không khẳng định PGS/typesetting trước E2E. Bổ sung UI tiếng Việt và nhận diện `vi/vie/vietnamese` cho audio/subtitle; nếu không có track Việt thì fallback có thể chọn, không tạo/đổi track giả.
7. **Điều khiển:** D-pad/Back/Play-Pause, focus, error UX; có thể tái sử dụng OMP phone remote, nhưng không viết companion app mới ở P0.
8. **Giới hạn MVP:** giữ player và website search; không tự vận hành billing/đăng ký trả phí OMP, bot thanh toán, VPS hay hệ thống theo dõi/tìm torrent nền ngoài scope. Không tự kích hoạt autostart TV, dịch vụ nền, firewall/router. Nếu module commercial đang là dependency, cô lập/đánh giá trước khi vô hiệu hóa để không làm hỏng chức năng tìm website được giữ lại.
9. **AI tiếng Việt:** nhận diện lời thoại, dịch, sinh phụ đề/thuyết minh tiếng Việt, căn thời gian và trộn audio là **P2 opt-in**, chạy trên Windows/NAS chỉ khi Human yêu cầu. Chỉ đánh giá thuyết minh bằng PoC hợp pháp; chưa tuyên bố phát audio rời đồng bộ đã có trong OMP.
10. **AIOS & repo:** app chạy độc lập với AIOS runtime, không thêm DB/router/orchestrator AIOS. GitHub repo `trung-via/torrent-tv-vietsub` PRIVATE, độc lập `AIOS-renew`. Không tự chuyển public, ký APK, publish hoặc dispatch TASK.

## C2 — Chưa được xác minh (`UNVERIFIED`)

- Fork/clone OMP kèm Git submodule `android/vendor/2160player`, pin commit, build debug/CI và dependency/license provenance trên target toolchain.
- TV chính xác thuộc Redmi nội địa hay Xiaomi Google TV, phiên bản firmware/API/ABI, quyền sideload, D-pad, video/codec/audio/HDR.
- Real TorrServer Windows/NAS: version, HTTP Range/seek, auth, API schema, LAN performance và stream dữ liệu thử hợp pháp.
- Unicode Vietsub thực tế trên player gốc/VLC; ASS/SSA/PGS và chất lượng tự chọn track `vi/vie`.
- Tính hợp lệ, login, độ ổn định và điều kiện sử dụng của từng website/indexer; không suy từ việc adapter có trong source rằng mọi nguồn luôn truy cập hợp pháp hoặc hoạt động.
- Trộn/thay audio tiếng Việt ngoài container, khớp timeline, độ trễ/lỗi khi seek; năng lực Windows/NAS cho AI ASR/TTS.
- AIOS cross-repo execution/publish sau fresh Brain Sync. Không có task admission hay dispatch nào được xác nhận trong contract này.

**Quy tắc:** source audit ≠ build PASS; mock/emulator ≠ TV thật; thiếu evidence báo `REAL_TV_UNVERIFIED` / `REAL_SERVER_UNVERIFIED`.

## C3 — Scope và mốc

- **P0 / Feasibility & usable fork:** upstream pinned snapshot và submodule, license/inventory/security audit, build APK debug; kiểm tra firmware/device gate; TorrServer Windows LAN; player/remote/resume; UI tiếng Việt, `vi/vie` + SRT/VTT có dấu; **giữ nguồn tìm website, manual magnet/.torrent và tìm kiếm người dùng chủ động**; test mock + test thật tách bạch.
- **P1 / Local experience:** nâng cấp UX Việt, reconnect, subtitle rời ngoài torrent nếu cần, quản lý track theo series, kiểm soát thông tin nhạy cảm; xem xét giữ/đơn giản hóa phone remote sẵn có; release chỉ khi Human duyệt.
- **P2 / AI opt-in:** pipeline Windows/NAS ASR → dịch Việt → QA → TTS → align/mix/mux; PoC 1 đoạn video legal trước tự động hóa. Không thực hiện nền khi chưa phê duyệt.
- **Out of scope:** hệ thống tìm kiếm/chia sẻ phim vi phạm quyền do dự án tự vận hành; scraping không có quyền, bypass DRM/paywall/chống truy cập; WAN public/UPnP; root TV; tự động transcode mọi định dạng; gói TorrServer vào APK; xây lại UI native Compose trong P0; commercial OMP billing infrastructure.

## C4 — Interface boundaries

```text
Phone / TV user search or manual magnet/.torrent
    |   (OMP website adapters / optional configured indexers, lawful use)
    v
OMP TypeScript/Preact UI + Capacitor bridge
    |                            | TorrServer API           Android native PlayerActivity
    v                           Engine2160 (Media3/2160) | VLC fallback
Windows PC / NAS TorrServer  ---- HTTP LAN media stream ----> TV / Vietsub
```

- Tái dùng `src/api/torrserver.ts`, `src/player/nativePlayer.ts`, `android/.../player/*`; không đưa wire schema khắp UI.
- Pin upstream OMP commit; ghi submodule SHA và dependency versions sau feasibility. Pin TorrServer version/API chỉ sau probe thật.
- Chỉ dùng mạng LAN tin cậy theo baseline; không mở router/firewall/UPnP/WAN. API credentials không hardcode; tránh userinfo trong URL/log, đánh giá đường VLC/WebView trước release.
- Website search là hành động theo yêu cầu người dùng; không tự khởi động nền hoặc lạm dụng đăng nhập/nguồn.

## C5 — Bảo mật, quyền sử dụng, giấy phép

- Chỉ dùng nội dung có quyền truy cập/chia sẻ; fixture tự tạo hoặc CC/open-license có provenance. Giữ tính năng tìm website **không đồng nghĩa xác nhận tính hợp pháp của mọi torrent/nguồn**; người dùng phải tuân thủ luật và điều khoản nguồn.
- Không vận hành kho phim lậu, crawler trái phép, vượt DRM; không lưu magnet cá nhân, tracker token/passkey, credential, IP thật trong git/log/screenshots/backup chia sẻ.
- TorrServer qua trusted LAN; không public IP/port/WAN, tự sửa Windows service/firewall/startup/router. Mọi thay đổi hệ thống cần phê duyệt riêng.
- OMP upstream là GPL-3.0-only; submodule 2160 Player, VLC, Media3 và dependencies có license riêng. Khi lấy mã OMP hoặc phát hành APK sửa đổi, rà soát nghĩa vụ GPL về mã nguồn tương ứng, notices và attribution; repo PRIVATE không xóa các nghĩa vụ khi phân phối.
- Tắt/gỡ thành phần billing, theo dõi nền/autostart và quyền Android không cần thiết **theo patch kiểm chứng**, không phá tìm kiếm website đã quyết định giữ lại.

## C6 — Acceptance & evidence

- **AC-SOURCE:** provenance OMP + commit/submodule/dependency pin; inventory search adapters; website source search còn truy cập từ UI bằng hành động chủ động và test với nguồn/fixture có quyền; không tự gọi crawler bất hợp pháp.
- **AC-BUILD:** clone sạch; npm/TypeScript tests + Android Gradle/Kotlin tests; APK debug hash, build log; CI chỉ sau authorize. Nếu không build được thì blocker, không công bố PASS.
- **AC-SECURITY:** không lộ secret qua source, link stream, redirect, logs, exception, report hay backup; kiểm tra luồng Basic Auth và network domain; license evidence.
- **AC-APP:** remote focus/Back/seek/resume, player 2160/VLC, offline/network/auth typed errors qua mocked fixture.
- **AC-SERVER:** health/list/play/seek/Range thử với TorrServer thật và media legal; thiếu thực nghiệm => `REAL_SERVER_UNVERIFIED`.
- **AC-TV:** APK install/launch/D-pad/player trên đúng TV/box thật và ABI/firmware có bằng chứng; thiếu => `REAL_TV_UNVERIFIED` / `DEVICE_BLOCKED`.
- **AC-VI:** UI tiếng Việt không lỗi dấu; track `vi/vie` được nhận và chọn đúng; SRT/VTT UTF-8 đồng bộ; ASS/PGS chỉ PASS khi test thật.
- **AC-RELEASE:** Human duyệt licensing, dữ liệu, chữ ký, rollback; không auto-production.

## C7 — Authority & quản trị thay đổi

- Quyết định Human mới nhất > `docs/PROJECT_CONTRACT.md` > `docs/PRD.md` > `docs/DECISIONS/*.md` > `docs/ROADMAP.md` > chat drafts.
- Thay đổi kiến trúc này đã được Human phê duyệt ngày 2026-10-25, ghi ADR-0002; dùng PR/diff audit, không auto merge/publish.
- Đối với AIOS: phải fresh Brain Sync, canonical main/NEXT, quyền cross-repo, executor, admission và review hiện hành trước khi author/dispatch TASK; không coi alias trong repo là TASK chính thức.
- Không sửa `AIOS-renew`, không áp test/governance internal AIOS lên app; thay đổi phạm vi/quyền mới phải có Human đồng ý.

## C8 — Stop conditions & rollback

Dừng nếu license/provenance không thể đáp ứng; toolchain không build sạch; TV không hỗ trợ APK; cross-repo authority không rõ; code có nguy cơ lộ credential; phải bypass DRM/vi phạm điều khoản nguồn; yêu cầu mở WAN hoặc thay đổi Windows/TV không được phép; hoặc báo mock như TV/server thật. Rollback theo branch/commit/PR; không xóa history trước khi đối chiếu.

## C9 — TASK lập kế hoạch đầu tiên

**Alias mới:** `OMP-EVAL-001` (planning only, **không phải canonical TASK ID**).  
**Mục tiêu:** kiểm tra clone/build upstream OMP + submodule, license/security/source inventory, TV/TorrServer feasibility, giữ nguồn tìm website; **chưa nhập mã upstream vào `main`**.  
**File:** `planning/OMP-EVAL-001-DRAFT.md`.  
`TVAPP-001` kiểu dựng Kotlin/Compose shell đã **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Không auto AUTHOR_TASK/dispatch/merge.
