# P1-EXT-SRT-POC — PoC Vietsub rời độc lập nguồn (planning only)

**Ngày:** 2026-10-25  
**Status:** `DRAFT_ONLY / NOT_CANONICAL / NOT_DISPATCHED / E2E_UNVERIFIED`  
**Authority:** ADR-0006 đã merge qua PR #10; Human chốt acceptance P1a ngày 2026-10-25 theo [P1A-ACCEPTANCE-CRITERIA-20261025.md](P1A-ACCEPTANCE-CRITERIA-20261025.md). Không tự merge/dispatch hoặc thay đổi Windows/TV/AIOS.

## Mục tiêu

Chứng minh app OMP-derived chạy VLC trên Redmi HyperOS có thể nạp **một phụ đề SRT UTF-8 rời ngoài torrent** mà không mất âm thanh, đúng dấu tiếng Việt, chọn/tắt track và giữ position/tracks qua seek/resume. Không cài SMB hoặc thêm Python agent/service để tạo/dẫn phụ đề trong PoC.

## Gate / Evidence (read-only trước khi sửa mã)

- Kiểm tra SHA của `trung-via/torrent-tv-vietsub/main`, nhánh PR, upstream OMP pin `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`, `2160player` submodule, GPL/license/dependencies.
- Target repo đang docs-first; có workflow build upstream thành công `40159082083`, runner smoke `40128964785`, **không phải fork đã nhập source, cũng không phải bằng chứng P1 E2E**. Đánh giá quyền repo/runner/workspace hiện thời trước mutation.
- Nếu đi qua AIOS: fresh canonical Brain Sync, verified NEXT/admission, quyền cross-repo và tuyến dispatch đúng runner app; không tạo official TASK từ alias này.
- Có quyền thử trên TV thật, fixture có bản quyền hợp lệ, không log torrent token/magnet, secrets.

## Scope file tối thiểu (PROPOSED, chỉ sau source import & authorization)

- `android/app/src/main/java/com/spacesarmat/omp/player/PlayerActivity.kt`: tạo fixture ở app-private storage trong bản debug và đưa `SubFile` vào queue item hiện tại trước `PlayerSession.load()`, qua luồng đã có. `VlcEngine.kt`: **đánh giá trước, chỉ sửa nếu đường addSlave predeclared thất bại hoặc cần hot-add sau PoC đầu tiên**.
- `android/app/src/main/java/com/spacesarmat/omp/player/PlayerEngine.kt`, `PlayerSession.kt`: chỉ sửa khi có bằng chứng cần mở bridge/track state; không xây file browser production.
- `src/player/nativePlayer.ts`/track preferences **chỉ khi bắt buộc** cho bridge/state.
- Android/unit fixtures + report kiểm thử app; không thêm `android/.../smb/*`, service/router/DB, không chỉnh TorrServer, Windows Firewall hoặc AIOS.
- Thiết kế storage mapping `serverProfile+infohash+fileIndex` nếu cần; không lưu credential/media vào repo.

## Evidence gates sau V1-method audit — không gộp PASS

- **G0: LOCAL_SRT_RENDER** — debug-only SRT asset → app-private → predeclared current `QueueItem.subtitles` before opening VLC; tiếng Việt đúng dấu, D-pad on/off, VLC hình/tiếng, pause/seek. Chỉ chứng minh render local trên Redmi thật; không chứng minh import tùy ý, hot-add, hội thoại đồng bộ hay ghi nhớ.
- **G1: EXTERNAL_SRT_IMPORT** — file không đóng gói trong APK được đưa vào TV bằng kênh thử hợp pháp (ADB nếu được phép); nạp đúng phim/tập, track off/embedded nếu mẫu có, lỗi file và quyền, pause/seek/resume, persistence qua reopen **không có test injection**. Chỉ G1 đủ chứng cứ thực mới cho `EXTERNAL_SRT_E2E_PASS`.
- **G2: LIVE_ADD** — thử nạp sau khi phim đang chạy và reload preserving position/audio nếu cần; không gộp với G0/G1.
- **G3: SYNC** — dùng video kiểm soát với cue khớp timestamp; 4 cue trong fixture chỉ kiểm glyph/cú pháp, không khớp lời thoại của video tùy ý.
- **G4: RELEASE_ISOLATION** — debug fixture/hook không xuất hiện hoặc không thể kích hoạt trong bản release; phải kiểm kết quả đóng gói/variant.

## Verification theo thứ tự

1. Xác thực OMP/submodule/license và điều kiện runner; không coi build upstream là bản fork P1. Chuẩn bị debug-only fixture tự tạo, chọn video hợp pháp để kiểm cue tại các mốc 2–17 giây, với track tiếng Việt được gắn **chỉ cho item hiện tại** và test injection mặc định OFF.
2. G0: thử local URI, bật/tắt track bằng D-pad, dấu Unicode, VLC audio, pause/seek. Nếu track không hiện, ghi lỗi/trace đã redacted; không tự mở SMB hay thêm backend.
3. G1: thử `.srt/.vtt` không nằm trong APK, gắn đúng media key (server profile + infohash + file index); đổi tập/reopen với debug injection OFF, thử track nhúng nếu video có; không gán nhầm file.
4. G2/G3 riêng: hot-add và sync chỉ sau khi có cơ sở test phù hợp, không biến chúng thành điều kiện ẩn của G0.
5. Negative: G0 asset missing/malformed không crash; G1 file không tồn tại, lỗi encoding/timestamp, quá lớn, permission denied báo lỗi an toàn. Không log magnet/passkey/URL chứa credentials.
6. Thu bằng chứng tách biệt theo từng gate: main/branch/upstream SHA, APK SHA256, variant, TV firmware/API/ABI, Gradle/test, thao tác D-pad và ảnh/video test hợp pháp đã redact. Mock/build PASS không thay real-TV proof.

## AC và Stop

- **AC-G0:** Chỉ kết luận `LOCAL_SRT_RENDER_PASS` sau khi Android debug APK trên Redmi thật hiển thị track Unicode và giữ VLC audio/seek; nếu thiếu chứng cứ `UNVERIFIED`.
- **AC-G1:** Chỉ kết luận `EXTERNAL_SRT_E2E_PASS` sau khi file ngoài APK hoạt động trên Redmi thật với media binding, track/off, lỗi, resume/reopen không injection; không lấy G0 thay.
- **AC-G2/G3:** hot-add và sync phải có matrix/evidence riêng; thử embedded switching khi video fixture có embedded track.
- **AC-G4:** release không chứa hoặc không thể bật fixture/hook debug, không sinh hành vi tự chèn phụ đề.
- **STOP:** không có quyền source/import/runner, chưa xác minh AIOS canonical route khi cần, cần tự sửa SMB/Windows/firewall/TV, license blocker hay test có nguy cơ lộ secret. Không auto-dispatch, merge hay release.
## Sau PoC

P1b đo và so sánh local picker/USB, SMB read-only, phone file transfer, phương án ít hạ tầng hơn; Human quyết định nguồn nhập ưu tiên sau. AI Vietsub P2 tạo `.vi.srt` tái dùng importer; TTS audio là PoC khác.

## Source audit supplement — 2026-10-25 (read-only; exact pinned source)

### Immutable evidence

| Evidence | Status |
| --- | --- |
| App main HEAD `67b769ce29ce9c166472f97ef46b37170a525e29` | docs-first, no OMP source |
| Upstream `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` | resolved immutable commit |
| `android/vendor/2160player` gitlink | `6ba6edd39f5d986ddfae29b5425b8ac0b319844e` |
| OMP and 2160 Player LICENSE | GPL-3.0; separate dependency assessment pending |
| Target dedicated-runner smoke | SUCCESS: GitHub Actions run `40128964785`, historical proof only |
| Target pinned-upstream build + Android unit tests | SUCCESS: run `40159082083`, build artifact `omp-debug-apk` (not app fork) |
| AIOS target downstream dispatch route | UNVERIFIED; no canonical TASK author/dispatch |
| P1 external SRT Android runtime | UNVERIFIED, requires new debug APK + real Redmi |

### Smallest test seam — choose predeclared subtitle first

- `NativePlayer.kt`: `QueueItem(subtitles: List<SubFile>)` is a data class. `SubFile(url, label, ext, lang)` accepts a subtitle URL. `PlayRequest` is a data class with `queue` and `index`.
- `PlayerSession.load()` opens `EngineMedia(q.url, q.subtitles)`; `TrackOptions.subs()` displays external files in the existing subtitle menu.
- `VlcEngine.refresh()` enqueues `item.subtitles` after playback starts, then `addNextSlave()` calls `mp.addSlave(IMedia.Slave.Type.Subtitle, Uri.parse(url), false)` on `VlcThread`. No new player, SMB browser or UI menu required **for a first proof at media open**.
- `VlcSupport.lang("vi")` passes through a 2-letter language code, so `SubFile(... lang = "vi")` gives the correct candidate language. Selecting via existing remote subtitle menu is the first verification.
- **Unverified:** LibVLC actually opens an app-private `file://` URI on Redmi HyperOS, discovers the external SPU, maps label and preserves VLC audio/position. Dynamic `addSlave` *after* the item is already open is a **second** experiment, not implied PASS.

### Bounded patch proposal (DO NOT EXECUTE outside approved app source import)

1. Create a **debug-only** asset `android/app/src/debug/assets/p1-vietsub-utf8.srt` from the self-authored repository fixture `fixtures/p1-vietsub-utf8.srt`; never package as a release fixture.
2. At the debug-only test seam (prefer a tiny helper called from `PlayerActivity.load()` **before `PlayerSession.load()`**), materialize the asset into `filesDir` and append `SubFile(url = Uri.fromFile(file).toString(), label = "PoC Việt", ext = "srt", lang = "vi")` **only to the currently playing queue item**. Gate with Android's debuggable application flag; default false; no modifications to release behavior.
3. Use existing VLC setting and remote subtitle-track menu. No new Android permissions, server process, file-picker, Windows share or credential exchange.
4. Add focused tests for `vi/vie` track language, subtitle source mapping and debug gating, keeping real libVLC behavior for physical-TV evidence.
5. After static/build test, run with a rights-cleared playable sample and record whether the debug SRT appears. **Only if this passes**, attempt hot-add while actively playing, then state/seek/resume and wrong-episode checks. Evaluate UI/final importer separately.
6. Remove all debug hooks and test fixtures from release after PoC; do not assume this prototype is production external file import.

**Reason to prefer this order:** it separates "can VLC render a local SRT outside torrent?" from "how does the user transfer that SRT?" and avoids adding SMB, HTTP services and Windows permission changes before confirming the decoder/subtitle path.

### Physical TV gate and evidence checklist

- Record exact TV firmware/API/ABI and installed APK ID/version/SHA256, OMP source pin and gradle test result (no secret-bearing logs).
- Verify [ ] VLC picture/audio [ ] visible Vietnamese diacritics [ ] menu contains separate external track [ ] off↔external↔embedded [ ] pause/seek ±30s [ ] reopen same media [ ] next episode does not inherit wrong subtitle.
- Negative: inaccessible/corrupt SRT and track-not-found should not crash; user-visible error desired for eventual UI. Report each as PASS/FAIL/UNVERIFIED.
- Before external-source PoC has real-TV evidence, never claim `EXTERNAL_SRT_E2E_PASS`.

### Stop / safe boundary

No source mutation in `main` or upstream during this docs/fixture preparation. OMP source import/fork provenance, isolated workspace and required authorization must precede actual patch/build. GitHub workflow rerun, self-hosted runner commands, sideload, ADB access, Windows changes and AIOS dispatch are **not** authorized by this planning note. Keep PR #9/#10 Draft and reconcile overlapping docs before any merge.

## V1 findings applicability / supersession

Đọc `planning/P1-V1-AUDIT-FINDINGS.md` trước khi giao executor. Phần source-audit supplement phía trên/bên dưới chỉ mô tả **candidate HOW**; nếu wording cũ nói nạp fixture, hot-add, reopen hoặc media mapping là cùng một phép thử PASS, các gate G0–G4 mới **supersede**. Ưu tiên debug-only source set; guard `debuggable` đơn lẻ không thay được kiểm tra release artifact.
