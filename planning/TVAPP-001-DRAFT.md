# SUPERSEDED — historical planning only

> **2026-10-25:** Human approved OMP-based architecture and retention of website torrent search; this original Kotlin/Compose-shell plan is **NOT to be executed**. See [ADR-0002](../docs/DECISIONS/ADR-0002-omp-baseline.md) and [OMP-EVAL-001-DRAFT.md](OMP-EVAL-001-DRAFT.md). This alias never became a canonical AIOS TASK.

---

# AIOS — FIRST TASK AUTHORING DRAFT: External Repo + Device/Server Feasibility

**Date:** 2026-10-15  
**Status:** DRAFT ONLY — NOT_CANONICAL / NOT_INGRESSED / NOT_DISPATCHED  
**Work item alias:** `TVAPP-001` (local planning identifier only, **not** an AIOS canonical TASK ID).  
**Target:** New independent repository `torrent-tv-vietsub` (not `AIOS-renew`).  
**Dependency:** PRD `AIOS_TORRENT_TV_VIETSUB_PRD_V2_WINDOWS_NAS_2026-10-15.md`.

## Outcome

Chứng minh AIOS có thể triển khai **một repo ứng dụng Android TV riêng** và có bản build/kiểm thử cơ bản trên Windows hoặc NAS streaming server. Giảm rủi ro thiết bị trước khi triển khai player và Vietsub hoàn chỉnh.

## Preconditions / authority

- **Fresh Brain Sync** từ canonical main của `trung-via/AIOS-renew` tại thời điểm author; xác minh latest SHA, unique NEXT, ownership, task ID allocation và AUTHOR_TASK permissions. SHA `03a4681962b7a5740d73a1374bc30a413a876fe3` chỉ là ảnh chụp read-only ngày 15/10/2026.
- Đọc canonical manifest/roadmap liên quan, phân biệt repo điều phối AIOS và repo target. Không tự nhận roadmap AIOS đã ủy quyền project mới.
- Chỉ sửa workspace target khi có canonical authorization. Không thay đổi AIOS governor, lifecycle, unrelated tests, secrets/rulesets.
- **Không tự tạo remote GitHub repo** và không bật inbound networking/workflows nếu Human chưa phê duyệt phạm vi, visibility và permission.
- Nếu repo ngoài chưa được hỗ trợ an toàn bởi đường self-host dispatch: trả blocker + đề xuất repair task riêng; không vá nóng AIOS hay gộp workaround vào app task.

## Primary scope

### Stage A — AIOS-to-repository proof

- Read-only kiểm tra CLI `--repo`, self-host working directory, relative paths, creation policy và verification on external workspace.
- Kiểm tra sự cô lập giữa repo điều phối và repo ứng dụng, có backup/rollback rõ.
- Nếu quyền hợp lệ: tạo local Git root `torrent-tv-vietsub` trong path riêng do Runtime/Human chấp thuận; seed `.gitignore`, docs, Android Gradle wrapper, LICENSES và CI config nháp.

### Stage B — Minimal TV APK

- Kotlin Android TV project, `LEANBACK_LAUNCHER` và manifest TV-ready; UI gồm màn hình kết nối TorrServer và trạng thái, D-pad/Back navigation.
- Use Media3 dependency được pin, có player stub/placeholder; **không** cần thật sự tải torrent/phát phim ở TASK đầu.
- Build debug APK không lỗi; GitHub Actions Android CI có unit-test/build (không đòi device/server thật).

### Stage C — Server contract & fixture tests

- Define `StreamEngine`/`TorrServerAdapter` seam, typed errors và client health probe.
- Kiểm tra version/API của TorrServer qua tài liệu và mock: `/echo`, auth denied, offline, invalid address, timeout.
- Nếu Windows server đang hiện hữu + endpoint LAN được Human cấp phép: thử GET health từ target runner; ghi version/HTTP code/timing theo evidence, không copy passkeys/magnets.
- Nếu không có server thật: mock test PASS riêng, `REAL_SERVER_UNVERIFIED` riêng; không giả mạo thành công thật.

### Stage D — Device feasibility artifact

- Ghi checklist Settings → About (model/build/OS), Android API/ABI nếu có, sideload capability, D-pad/remote và video codec capability.
- ADB script **không tự chạy nếu chưa được phép**. Khi có TV thật, thử install, launch, Back, D-pad và screenshot được biên tập thông tin riêng tư.
- Nếu firmware không tương thích APK: ghi blocker rõ và nhánh hardware fallback bằng Android/Google TV box.

## Acceptance criteria (AC)

| ID | Acceptance | Evidence / rule |
|---|---|---|
| AC1 | Canonical task authority hợp lệ + isolated target root | Fresh Brain Sync & admission proof; otherwise BLOCKED |
| AC2 | Có Android TV Gradle project trong repo riêng | Tree/diff; không có thay đổi trái phép lên AIOS-renew |
| AC3 | Reproducible debug APK build | Gradle stdout + APK checksum/artifact |
| AC4 | Basic TV UI chạy được trên emulator/ADB test runner | Screenshot/test record; test môi trường nào nêu rõ môi trường đó |
| AC5 | HTTP mock + timeout/offline/auth negative tests | Unit/integration PASS, không cần public torrent |
| AC6 | TorrServer real LAN health probe | PASS nếu server sẵn có; nếu không: `REAL_SERVER_UNVERIFIED`, không chặn AC1–AC5 |
| AC7 | TV real-device install/launch | PASS khi có hardware + permission; nếu không: `PHYSICAL_DEVICE_UNVERIFIED`, không chặn AC1–AC5 |
| AC8 | Repo isolation/security/license | Không WAN port opening, credentials/magnet logging, vendored server binary hoặc remote repo surprise |

## Verification design

- Tầng 1: Gradle compilation/lint, unit tests, mock HTTP contract, UI focus tests; không chạy full suite AIOS-renew.
- Tầng 2: Server health smoke Windows/NAS nếu được cấp quyền; không bắt buộc internet torrent.
- Tầng 3: APK install/launch + D-pad trên TV thật khi sẵn có; báo trạng thái riêng, không fake PASS.
- Sử dụng đúng hai lượt review/audit hiện hành theo canonical sau Brain Sync; chỉ review lỗi và evidence trong scope.

## STOP conditions

- Canonical authority cấm thao tác repo mới hoặc allocator chưa cấp TASK ID.
- Runtime/executor có nguy cơ mutate `AIOS-renew` thay vì target repo.
- Bắt buộc mở cổng WAN, lưu secret plaintext vào repo/log hoặc bypass firmware không được phê duyệt.
- TV không hỗ trợ APK mà không có phương án client thay thế được Human chấp thuận.

## Outputs

1. `torrent-tv-vietsub` local repo skeleton (chỉ nếu được ủy quyền).
2. Debug APK + checksum/build log (sau khi triển khai).
3. `docs/DEVICE_COMPATIBILITY.md`, `docs/TORRSERVER_CONTRACT.md`, `docs/TEST_MATRIX.md`.
4. AIOS review packet: canonical task ID/revision, target root, changed paths, AC matrix, evidence / blockers.
5. Đề xuất TASK kế tiếp: `TorrServer Adapter & Playback Core` (chưa phân bổ ID).

## Suggested Executor (pending canonical selection)

Codex GPT-6.1 Sol high/xhigh nếu được Human chọn và môi trường cung cấp; duy trì executor đã chọn xuyên suốt task. Không cài đặt lại chính sách hoặc tự dispatch từ tài liệu nháp.

## Handoff instruction for Brain

> Thực hiện fresh Brain Sync từ canonical main và xác minh unique NEXT. Đọc PRD V2 và FIRST TASK DRAFT. Nếu phù hợp với canonical authority, đưa nội dung vào template TASK hiện hành và phân bổ TASK ID qua AUTHOR_TASK. Scope phải độc lập repo, không ghi vào AIOS-renew. Chưa dispatch nếu chưa có admission/authorization và Human xác nhận quyền tạo repo từ xa. Không báo real-device PASS khi chưa cài trên TV thật; không báo real-server PASS khi chỉ dùng mock.
