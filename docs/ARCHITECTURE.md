# Architecture v3.0 — Torrent TV Vietsub độc lập AIOS

**Ngày:** 2026-10-28  
**Trạng thái:** `DRAFT_FOR_PR_REVIEW`; kiến trúc nền OMP + TorrServer và nguyên tắc độc lập AIOS đã được Human chọn. Các module agent/gateway/search ranking/AI voice-over là `PROPOSED`, chưa có E2E.  
**Đọc cùng:** `PROJECT_CONTRACT.md`, `PRD.md`, ADR-0001/0002/0006/0007, `DEVELOPMENT_WORKFLOWS.md`.

## 1. Hai hệ thống hoàn toàn tách biệt

### A. Product runtime (không có AIOS)

```text
                     USER / PHONE / TV REMOTE
                           |         |
                 manual magnet       | UI navigation
                           v         v
Allowed source adapters --> OMP-derived TV app (Preact/Capacitor)
   (user initiated)          |   Android native PlayerActivity
          |                  |   2160/Media3 or VLC fallback
          |                  |   Vietnamese UI/audio/subtitle
          v                  ^                   ^
Optional Torrent TV         |                   | optional .vi.srt / audio
local gateway               |                   |
(PROPOSED; opt-in)          |                   |
  | search/filter           |                   |
  | confirmation            |                   |
  +----> TorrServer API ----+---- HTTP stream --+
          on Windows/NAS                  ^
                 ^                        |
                 +-- optional AI media worker
                     (ASR/translate/TTS/align/mux; Windows/NAS)
```

**Đường P0:** OMP UI hoặc TorrServer Web UI nhập magnet/.torrent hợp pháp → TorrServer Windows/NAS → Android TV native player → track Việt/Vietsub. Website source search hiện có của OMP được giữ, nhưng test nguồn riêng theo điều khoản.

**Đường North Star (chưa triển khai):** yêu cầu ngôn ngữ tự nhiên → agent nhận intent → gateway có auth → search nguồn cho phép → filter/rank candidates → Human xác nhận → thêm vào TorrServer → chọn file/play TV → trả status; AI Vietsub/voice-over là bước riêng, opt-in. ChatGPT không được coi là có quyền truy cập LAN trực tiếp.

### B. Development plane (không có AIOS)

```text
Human decision / Torrent TV Issues / ADR / PR
                     |
              Torrent TV repo
                     |
         GitHub Actions (repo scope)
                     |
      Dedicated self-hosted runner identity
      isolated worktree/cache/credentials
                     |
           tests -> APK -> artifacts
                     |
         Human-reviewed release decision

AIOS source / workflows / runner patterns
       └── optional manual audit/copy into Torrent TV PR
           NO live dependency, NO AIOS TASK/admission/dispatch
```

GitHub Actions là CI/CD; runner là executor do repo quản lý; gateway là runtime phục vụ điều khiển sản phẩm. Ba khái niệm này **không thay thế nhau**. Không dùng AIOS làm “Brain” hoặc cầu nối điều khiển TV.

## 2. Module boundaries và contract dự kiến

| Module | Trách nhiệm | Trạng thái / ràng buộc |
| --- | --- | --- |
| OMP UI (TypeScript/Preact + Capacitor) | TV/phone navigation, search, library, settings | DECIDED baseline; chưa mặc nhiên import/build |
| Native Android player (Kotlin, 2160/Media3, VLC) | Decode, D-pad, audio/subtitle, seek/resume | DECIDED baseline; real-TV compatibility cần evidence |
| TorrServer adapter | Health, metadata, file selection, stream URL, errors | API/path/auth phải probe deployed version |
| Source adapters | User-triggered lawful website/configured indexers | Giữ OMP adapters; audit ToS, auth, availability từng nguồn |
| Candidate evaluator | Resolution, size, codecs, seeds, source proof | PROPOSED; seeders là chỉ số báo cáo, không bảo đảm peers |
| Torrent TV gateway | Narrow actions, confirmation, status, audit | PROPOSED; riêng repo/runtime Torrent TV, không AIOS |
| TV-control adapter | Pair/launch/play/status trên thiết bị hỗ trợ | PROPOSED; lựa chọn ADB/Cast/native API sau test thật |
| AI media worker | ASR, dịch, QA, TTS, align, mux/mix | P4/P5 opt-in, Windows/NAS, chưa hứa real-time |
| Development workflows | lint/test/build/CI/artifact/release gates | GitHub Actions + dedicated runner; không AIOS |

**Contract candidates (đề xuất, không phải API đã có):** `SearchCandidate{sourceId,sourceTermsEvidence,title,resolutionRaw,width,height,sizeBytes,seedersReported,seedersObservedAt,codec,audioTracks,subtitleTracks,magnetRef}`; `PlayRequest{candidateId,fileId,deviceId,confirmedByUser}`; `PlaybackStatus{state,position,errorCode}`. Không đưa passkey, magnet hoặc token vào model context, logs, issue, PR.

**Không được suy đoán:** “2K” có thể là 2560×1440 hoặc DCI 2048×1080; cần hỏi/cho user chọn tiêu chuẩn. Metadata indexer có thể sai. Chỉ xác minh độ phân giải/codec khi đọc metadata/container thực. Chỉ xác nhận peers/streamability sau TorrServer probe.

## 3. Giao thức và trust boundaries

1. **User ↔ UI:** remote D-pad/Back và phone remote sẵn có nếu phù hợp; không tự tạo companion app mới P0.
2. **UI ↔ TorrServer:** trusted LAN, cấu hình endpoint, timeout, typed errors, auth; không phát tán Basic Auth userinfo qua URL native/VLC/log. API schema chưa pin, tham khảo `TORRSERVER_INTERFACE.md`.
3. **Search ↔ external source:** adapter allowlist/terms, chỉ theo user action, secret isolation; không crawl trái phép, bypass login/DRM hoặc duy trì piracy index.
4. **Agent ↔ local gateway (optional):** chỉ công cụ allowlisted, auth, confirmation và idempotency cho action có side effect; rate limit, input validation, anti-SSRF, chống prompt injection từ tên torrent/indexer; không shell/ADB arbitrary. Không mở gateway ra WAN.
5. **Gateway ↔ TV:** pairing và device identity được kiểm chứng; ADB debug không phải mặc định production. Chọn native companion/Cast/other theo firmware và evidence; không giả định Redmi nội địa là Google TV quốc tế.
6. **AI worker ↔ media:** chỉ file có quyền xử lý; consent, local/cloud processing policy, giới hạn chi phí, retention; sidecar/mux output có checksum và gắn đúng file/tập.
7. **CI ↔ host:** self-hosted runner là bề mặt thực thi đặc quyền. Chỉ trusted source/branch; không chạy mã từ fork PR không tin cậy với secrets; permissions tối thiểu, path/runner identity checks.

## 4. Vietsub và voice-over seams

- `src/i18n/*` + Android `I18n.kt`: thêm `vi`; kiểm tra Unicode, placeholder và focus.
- `src/lib/tracks.ts`, `trackPrefs.ts`, `DubMatch.kt`: nhận diện track `vi/vie/vietnamese` thật; fallback rõ, không ghi đè preference tùy tiện.
- `src/player/nativePlayer.ts`, `Engine2160.kt`, `VlcEngine.kt`: sidecar SRT/VTT; ASS/SSA và PGS chỉ sau thử thực. Theo ADR-0006: G0 fixture trong debug APK ≠ G1 file ngoài APK ≠ G2 hot-add ≠ G3 sync ≠ G4 release.
- AI worker có thể xuất `.vi.srt` trước khi tạo TTS. TTS/voice-over cần chứng minh align, ducking/mixing, pause/seek và mux/external-audio route. Không tuyên bố OMP có sẵn audio rời đồng bộ.

## 5. Execution isolation và reuse policy

- Repo: `trung-via/torrent-tv-vietsub` PRIVATE; Git root/history và backlog riêng.
- Runner: scope/labels/name/workspace/cache/credential riêng; file workflow hiện có kỳ vọng runner `torrent-tv-vietsub-win` với label `torrent-tv-vietsub`, **không phải bằng chứng online hiện tại**.
- Kế thừa AIOS **chỉ ở cấp file/mẫu**: GitHub Actions, scripts kiểm tra runner, artifact retention, pin SHA, error reporting. Copy sau provenance/license/security review; đổi namespace, paths, labels, permissions; không phụ thuộc AIOS services, workflow dispatch, journal, canonical task.
- Hiện repo có các workflow manual-only và nhiều Draft PR; thay đổi kiến trúc này là **docs-only**, không chạy workflow hoặc sửa các PR cũ. Trước merge cần kiểm tra conflict với nhánh docs/AI Vietsub/P1 đang mở.

## 6. Lộ trình triển khai theo gate

| Stage | Thiết kế tối thiểu | Evidence |
| --- | --- | --- |
| P0 | OMP build, legal fixture, TorrServer Windows LAN, D-pad, SRT/VTT | G-DEV/G-OMP/G-SERVER/G-TV/G-VI |
| P1 | External SRT/VTT, đúng phim/tập, reopen; chọn transport sau PoC | G-P1 độc lập G0–G4 |
| P2 | Lawful source search + metadata/filter/rank, manual confirmation | G-SOURCE, candidate audit, negative tests |
| P3 | Torrent TV gateway + TV control + optional ChatGPT tool | G-AGENT real E2E, pairing/security |
| P4 | ASR/dịch/QA → Vietsub offline opt-in | sample QA + provenance/cost |
| P5 | TTS/voice-over/mix/mux, real-time feasibility riêng | G-VOICE sync/seek/resource evidence |

**PoC 2–4 tuần là kế hoạch đề xuất, không cam kết:** tuần 1 runner/build/device inventory; tuần 2 real TorrServer→TV + Vietnamese subtitle; tuần 3 legal-source candidate filter; tuần 4 optional gateway control prototype nếu hai gate đầu PASS. Nếu không có TV/server/quyền nguồn, báo BLOCKED và không nâng scope.

## 7. Security, stop và rollback

STOP khi cần mở WAN/UPnP, bypass DRM, scraping không phép, phát tán secret, dùng AIOS runner/runtime, thiếu GPL provenance, thiếu quyền với media hoặc phải coi mock là real E2E. Mọi thay đổi OS/TV/runner/network cần phê duyệt vận hành riêng. Rollback bằng branch/PR và version pin; không tự sửa các repo AIOS.

**Chưa xác minh:** firmware Redmi nội địa, version TorrServer deployed, HTTP Range/seek/auth, CI runner hiện thời, OMP import/build trong main, khả năng điều khiển TV từ gateway, độ trễ/chất lượng AI thuyết minh. Các kết luận mới từ Deep Research phải vào PR/ADR kèm nguồn và test trước khi nâng thành DECIDED.
