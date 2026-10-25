# PROJECT CONTRACT v1.3-PROPOSED — Torrent TV Vietsub (OMP-based, independent runner)

**Repo:** `trung-via/torrent-tv-vietsub` (PRIVATE, đã tạo)  
**Product:** Torrent TV Vietsub — AIOS  
**Ngày khởi tạo:** 2026-10-15 · **Human change approval:** 2026-10-25  
**Trạng thái:** `DECIDED_PRODUCT_DIRECTION / IMPLEMENTATION_UNVERIFIED` — Human chọn kế thừa OMP, **giữ tìm torrent qua website**; chưa clone/build APK trên target repo, chưa nghiệm thu TV/server thật.  
**ADR:** [ADR-0001](DECISIONS/ADR-0001-client-server.md) (Windows/NAS vẫn giữ), [ADR-0002](DECISIONS/ADR-0002-omp-baseline.md) (chuyển client sang OMP), [ADR-0003](DECISIONS/ADR-0003-dedicated-repo-workspace-runner.md) (repo/workspace/runner riêng), [ADR-0005](DECISIONS/ADR-0005-p1-remote-external-subtitle.md) (lịch sử chọn SMB), [ADR-0006](DECISIONS/ADR-0006-p1-source-agnostic-external-subtitle.md) (Human điều chỉnh P1, thay ưu tiên SMB).  
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
11. **Execution isolation — quyết định Human nhắc lại ngày 2026-10-25:** dự án có **Git repository riêng, Git workspace/worktree riêng và self-hosted runner RIÊNG, dành cho Torrent TV Vietsub**. Không mặc định mượn runner, workspace, thư mục Runtime, locks, journals hoặc credentials của `AIOS-renew`. AIOS có thể giữ authority điều phối theo canonical hiện hành, nhưng việc admission/dispatch phải chứng minh tuyến đến **runner của repo ứng dụng**; không thay runner riêng bằng AIOS runner khi thiếu proof.

12. **P1 — External SRT/VTT source-agnostic (Human approval 2026-10-25, sau architecture audit):** mục tiêu P1 là **OMP VLC nạp, hiển thị, bật/tắt và quản lý phụ đề SRT/VTT UTF-8 rời ngoài torrent, đúng phim/tập và không mất tiếng khi seek/resume**. Đường lấy file (bộ nhớ TV/ADB thử nghiệm, Android picker/USB, SMB Windows, điện thoại hoặc đường khác) **chưa được chọn làm default**. SMB từng được Human đồng ý ở ADR-0005 nhưng nay được chuyển thành **ứng viên chờ feasibility + quyết định Human sau PoC**, không còn là yêu cầu P1 mặc định; ADR-0006 supersedes phần SMB-first/remote-file-browser của ADR-0005. Remote vẫn dùng để bật/chọn track trong player; không bắt buộc dùng remote để duyệt thư mục ngoài TV trong P1a. Không mở Windows share, SMB port/Firewall, dịch vụ, WAN hoặc thêm backend tùy ý.

## C2 — Chưa được xác minh (`UNVERIFIED`)

- Fork/clone OMP kèm Git submodule `android/vendor/2160player`, pin commit, build debug/CI và dependency/license provenance trên target toolchain.
- TV chính xác thuộc Redmi nội địa hay Xiaomi Google TV, phiên bản firmware/API/ABI, quyền sideload, D-pad, video/codec/audio/HDR.
- Real TorrServer Windows/NAS: version, HTTP Range/seek, auth, API schema, LAN performance và stream dữ liệu thử hợp pháp.
- Unicode Vietsub thực tế trên player gốc/VLC; ASS/SSA/PGS và chất lượng tự chọn track `vi/vie`.
- Tính hợp lệ, login, độ ổn định và điều kiện sử dụng của từng website/indexer; không suy từ việc adapter có trong source rằng mọi nguồn luôn truy cập hợp pháp hoặc hoạt động.
- Trộn/thay audio tiếng Việt ngoài container, khớp timeline, độ trễ/lỗi khi seek; năng lực Windows/NAS cho AI ASR/TTS.
- Tuyến AIOS authoring/dispatch tới **runner riêng của ứng dụng**, runner identity/registration/labels, trạng thái online, host/toolchain, Git workspace root và quyền read/write chính xác: **UNVERIFIED**. Quyết định có runner riêng không đồng nghĩa runner đã được cấu hình. Không có task admission hay dispatch nào được xác nhận trong contract này.

**Quy tắc:** source audit ≠ build PASS; mock/emulator ≠ TV thật; thiếu evidence báo `REAL_TV_UNVERIFIED` / `REAL_SERVER_UNVERIFIED`.

## C3 — Scope và mốc

- **P0 / Feasibility & usable fork:** upstream pinned snapshot và submodule, license/inventory/security audit, build APK debug; kiểm tra firmware/device gate; TorrServer Windows LAN; player/remote/resume; UI tiếng Việt, `vi/vie` + SRT/VTT có dấu; **giữ nguồn tìm website, manual magnet/.torrent và tìm kiếm người dùng chủ động**; test mock + test thật tách bạch.
- **P1a / External subtitle capability:** phân biệt G0 (render SRT trong vùng app-private từ fixture chỉ dành cho debug) và G1 (nhập file độc lập APK, quản lý/lưu lựa chọn theo phim/tập). G0 không chứng minh G1, hot-add, đồng bộ lời thoại hoặc persistence. **P1b / UX transport:** sau G1, đánh giá local picker/USB, SMB, phone hoặc cách khác; Human chọn default. Không thêm backend/Windows share lúc làm PoC.
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
- **AC-RUNNER:** có bằng chứng đăng ký self-hosted runner dành riêng cho repo ứng dụng, tên/labels, host workspace root độc lập, quyền, isolation và trạng thái online; thử một job vô hại được ủy quyền trên **đúng runner**. Nếu chưa có evidence: `DEDICATED_RUNNER_UNVERIFIED`, không fallback sang runner `AIOS-renew`.
- **AC-BUILD:** clone sạch; npm/TypeScript tests + Android Gradle/Kotlin tests; APK debug hash, build log; CI chỉ sau authorize, chạy trên runner riêng khi thực thi qua self-hosted. Nếu không build được thì blocker, không công bố PASS.
- **AC-SECURITY:** không lộ secret qua source, link stream, redirect, logs, exception, report hay backup; kiểm tra luồng Basic Auth và network domain; license evidence.
- **AC-APP:** remote focus/Back/seek/resume, player 2160/VLC, offline/network/auth typed errors qua mocked fixture.
- **AC-SERVER:** health/list/play/seek/Range thử với TorrServer thật và media legal; thiếu thực nghiệm => `REAL_SERVER_UNVERIFIED`.
- **AC-TV:** APK install/launch/D-pad/player trên đúng TV/box thật và ABI/firmware có bằng chứng; thiếu => `REAL_TV_UNVERIFIED` / `DEVICE_BLOCKED`.
- **AC-VI:** UI tiếng Việt không lỗi dấu; track `vi/vie` được nhận và chọn đúng; SRT/VTT UTF-8 đồng bộ; ASS/PGS chỉ PASS khi test thật.
- **AC-P1A-G0-RENDER (UNVERIFIED):** SRT UTF-8 tự tạo ở debug asset được chép vào app-private và khai báo trước khi mở VLC; kiểm Redmi thật: chữ Việt có dấu, chọn/tắt track bằng D-pad, hình/tiếng và seek. Chỉ được ghi `LOCAL_SRT_RENDER_PASS` nếu có real-TV evidence; không suy ra nhập file tùy ý, hot-add, đồng bộ lời thoại, persistence hay P1a E2E.
- **AC-P1A-G1-IMPORT (UNVERIFIED):** một file `.srt/.vtt` **không đóng gói trong APK** được nhập qua kênh thử hợp lệ, gắn đúng phim/tập, off/embedded (nếu có), pause/seek/resume, xử lý lỗi file/quyền và mở lại mà không tự chèn fixture. Chỉ kết luận `EXTERNAL_SRT_E2E_PASS` khi có đủ evidence thực Redmi; không yêu cầu SMB/phone làm đường mặc định.
- **AC-P1A-FROZEN-SCOPE (DECIDED, PROOF_UNVERIFIED):** Human chốt bộ tiêu chí G0/G1 và bảo lưu G2/G3/G4 độc lập theo [P1A Acceptance Criteria](../planning/P1A-ACCEPTANCE-CRITERIA-20261025.md). P1a bắt buộc SRT UTF-8 ngoài torrent **và ngoài APK** (G1), Unicode không lỗi glyph/cắt chữ, chọn/tắt track qua remote, giữ tiếng/hình và seek/resume/mapping phim-tập, lỗi file/permission an toàn. VTT cần proof định dạng riêng; G0 chỉ là render fixture debug, không tự tạo G1 PASS. **Không đặt bold/font-weight/outline/shadow/size tuning là điều kiện P1a PASS**; đưa UX style sang backlog sau P1a. Hai ảnh Human gửi chỉ chứng minh dấu Việt nhìn thấy, không chứng minh engine/file provenance hay SRT E2E.
- **AC-P1B-CHOICE (PROPOSED):** so sánh các đường nhập phụ đề sau P1a về độ tiện dùng bằng remote/phone, phạm vi quyền, chi phí, bảo mật và compatibility; lựa chọn default do Human phê duyệt riêng. Không mở Windows share/Firewall hay thay ứng dụng ngoài quyền được cấp.
- **AC-RELEASE:** Human duyệt licensing, dữ liệu, chữ ký, rollback; không auto-production.

## C7 — Authority & quản trị thay đổi

- Quyết định Human mới nhất > `docs/PROJECT_CONTRACT.md` > `docs/PRD.md` > `docs/DECISIONS/*.md` > `docs/ROADMAP.md` > chat drafts.
- Thay đổi kiến trúc này đã được Human phê duyệt ngày 2026-10-25, ghi ADR-0002; dùng PR/diff audit, không auto merge/publish.
- Đối với AIOS: phải fresh Brain Sync, canonical main/NEXT, quyền cross-repo, executor, admission và review hiện hành trước khi author/dispatch TASK; không coi alias trong repo là TASK chính thức. **Độc lập runner/workspace là điều kiện thực thi bất biến**, không phải sự cho phép tự chuyển quyền chạy sang runner AIOS nếu tuyến điều phối riêng chưa có.
- Không sửa `AIOS-renew`, không áp test/governance internal AIOS lên app; thay đổi phạm vi/quyền mới phải có Human đồng ý.

## C8 — Stop conditions & rollback

Dừng nếu license/provenance không thể đáp ứng; toolchain không build sạch; TV không hỗ trợ APK; runner/workspace riêng không có evidence hoặc dispatch trỏ về runner AIOS; cross-repo authority không rõ; code có nguy cơ lộ credential; phải bypass DRM/vi phạm điều khoản nguồn; yêu cầu mở WAN hoặc thay đổi Windows/TV không được phép; hoặc báo mock như TV/server thật. Rollback theo branch/commit/PR; không xóa history trước khi đối chiếu.

## C9 — TASK lập kế hoạch đầu tiên

**Alias mới:** `OMP-EVAL-001` (planning only, **không phải canonical TASK ID**).  
**Mục tiêu:** kiểm tra clone/build upstream OMP + submodule, license/security/source inventory, TV/TorrServer feasibility, giữ nguồn tìm website; **chưa nhập mã upstream vào `main`**.  
**File:** `planning/OMP-EVAL-001-DRAFT.md`.  
`TVAPP-001` kiểu dựng Kotlin/Compose shell đã **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Không auto AUTHOR_TASK/dispatch/merge.
