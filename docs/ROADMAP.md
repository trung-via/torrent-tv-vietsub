# Roadmap v2 — OMP-based app repo (không phải AIOS canonical roadmap)

**DECIDED:** OMP-based client, Windows/NAS TorrServer, **giữ website torrent source search**.  
**UNVERIFIED:** runner dự án đã đăng ký/online hay chưa; chưa clone/build APK, chưa test TV/server thật.

| Order | Alias | Scope | Exit |
| --- | --- | --- | --- |
| 0 | PROJECT-BOOTSTRAP (DONE docs-first) | Repo private + contract/PRD | GitHub repo tồn tại, docs được version |
| 1 | OMP-EVAL-001 (DRAFT) | **Verify dedicated project runner + separate workspace first**, pinned upstream OMP/submodule, GPL/security/dependency audit, isolated clone/build & TV/server preflight; source adapters không bị tắt | Runner identity/online proof hoặc `DEDICATED_RUNNER_UNVERIFIED`; npm/Gradle build evidence hoặc blocker; TV/server thật PASS riêng hoặc UNVERIFIED |
| 2 | OMP-VI-002 (PROPOSED) | Việt hóa TS/Kotlin UI; `vi/vie` audio/sub; UTF-8 SRT/VTT; giữ website source search | UI Việt, D-pad, fixture Vietsub và source-search smoke trên TV/box |
| 2a | P1-EXT-SRT-POC (DECIDED scope / implementation proposal) | PoC OMP VLC nạp SRT/VTT **rời và độc lập nguồn**; fixture có quyền được chép lên TV qua ADB/test; bật/tắt, track choice, Unicode, remember per media; KHÔNG yêu cầu SMB | `EXTERNAL_SRT_E2E_PASS` chỉ khi test thực Redmi + VLC audio/seek/resume + lỗi file; nếu chưa, `EXTERNAL_SRT_E2E_UNVERIFIED` |
| 2b | P1-SUB-SOURCE (PROPOSED, chưa chọn) | Sau 2a so sánh Android picker/USB, SMB read-only, phone remote/file transfer và lựa chọn khác; đo effort, bảo mật, remote UX, compatibility | Human duyệt phương án ưu tiên riêng, không mở Windows share/firewall hoặc xây backend trong lúc đánh giá | 
| 3 | OMP-HARDEN-003 (PROPOSED) | Security URL credentials, OMP legacy billing/background isolation, permission/autostart review, LAN resilience | Không leak secret, search website vẫn hoạt động, E2E real server+TV hoặc blockers |
| 4 | OMP-RELEASE-004 (PROPOSED) | Packaging/licensing, doc Windows/NAS, Human-approved APK release | GPL attribution/compliance, stable repeatable build, Human release approval |
| 5 | OMP-AI-005 (OPTIONAL P2) | Windows/NAS ASR/translation/QA/TTS, audio sync/mux proof | Legal fixture, QA tiếng Việt, seek/sync evidence; chỉ opt-in |

`TVAPP-001` trước đây là bản DRAFT dựng Kotlin/Compose shell; **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Mọi alias không phải TASK ID của AIOS. Để giao việc phải fresh Brain Sync, xác minh canonical NEXT/admission/executor/cross-repo authority và review. Không auto dispatch/merge/publish.
