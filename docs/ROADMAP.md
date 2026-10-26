# Roadmap v2.1-PROPOSED — OMP-based app repo (không phải AIOS canonical roadmap)

**DECIDED:** OMP-based client, Windows/NAS TorrServer, **giữ website torrent source search**.  
**UNVERIFIED:** runner dự án đã đăng ký/online hay chưa; chưa clone/build APK, chưa test TV/server thật.

| Order | Alias | Scope | Exit |
| --- | --- | --- | --- |
| 0 | PROJECT-BOOTSTRAP (DONE docs-first) | Repo private + contract/PRD | GitHub repo tồn tại, docs được version |
| 1 | OMP-EVAL-001 (DRAFT) | **Verify dedicated project runner + separate workspace first**, pinned upstream OMP/submodule, GPL/security/dependency audit, isolated clone/build & TV/server preflight; source adapters không bị tắt | Runner identity/online proof hoặc `DEDICATED_RUNNER_UNVERIFIED`; npm/Gradle build evidence hoặc blocker; TV/server thật PASS riêng hoặc UNVERIFIED |
| 2 | OMP-VI-002 (PROPOSED) | Việt hóa TS/Kotlin UI; `vi/vie` audio/sub; UTF-8 SRT/VTT; giữ website source search | UI Việt, D-pad, fixture Vietsub và source-search smoke trên TV/box |
| 2a-0 | P1-LOCAL-SRT-RENDER (DECIDED PoC / PROPOSED HOW) | SRT fixture chỉ trong APK debug → app-private → VLC predeclared subtitle; test dấu Việt, remote, VLC audio/video/seek | `LOCAL_SRT_RENDER_PASS` chỉ sau Redmi thật; không gộp importer, persistence, sync hay hot-add |
| 2a-1 | P1-EXT-SRT-IMPORT (DECIDED product / PROPOSED HOW) | SRT/VTT ngoài APK, đúng phim/tập, track/off, lỗi, pause/seek/resume, reopen không debug injection | `EXTERNAL_SRT_E2E_PASS` sau real-device evidence riêng; chưa = `UNVERIFIED` |
| 2b | P1-SUB-SOURCE (PROPOSED, chưa chọn) | Sau 2a so sánh Android picker/USB, SMB read-only, phone remote/file transfer và lựa chọn khác; đo effort, bảo mật, remote UX, compatibility | Human duyệt phương án ưu tiên riêng, không mở Windows share/firewall hoặc xây backend trong lúc đánh giá | 
| 3 | OMP-HARDEN-003 (PROPOSED) | Security URL credentials, OMP legacy billing/background isolation, permission/autostart review, LAN resilience | Không leak secret, search website vẫn hoạt động, E2E real server+TV hoặc blockers |
| 4 | OMP-RELEASE-004 (PROPOSED) | Packaging/licensing, doc Windows/NAS, Human-approved APK release | GPL attribution/compliance, stable repeatable build, Human release approval |
| 5 | OMP-AI-005 (DECIDED goal / PROPOSED P2) | **AI Vietsub trước:** timed SRT/VTT → dịch theo cue; thiếu text → Windows/NAS ASR → dịch Việt → QA/timestamps → `.vi.srt/.vi.vtt`; PoC CLI local opt-in. Nạp lên TV chỉ sau **P1a-G1**; **TTS/thuyết minh** là PoC riêng về sau | Hai fixture hợp pháp (timed source + audio), cue hợp lệ/QA, đo tài nguyên/privacy; TV thật chỉ PASS sau G1 importer E2E, `AI_VIETSUB_UNVERIFIED` nếu chưa |

**Thứ tự thực nghiệm:** Dịch SRT source offline có thể PoC độc lập với G1; nhưng tuyên bố AI Vietsub xem được trên TV phải có P1a-G1 thực Redmi, không suy từ G0. Không tự kích hoạt model/AIOS/phone/SMB. P1a-G0/G1 vẫn là các gate riêng như ADR-0006 và V1 findings F-01..F-04.

`TVAPP-001` trước đây là bản DRAFT dựng Kotlin/Compose shell; **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Mọi alias không phải TASK ID của AIOS. Để giao việc phải fresh Brain Sync, xác minh canonical NEXT/admission/executor/cross-repo authority và review. Không auto dispatch/merge/publish.
