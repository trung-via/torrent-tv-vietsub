# Roadmap v2 — OMP-based app repo (không phải AIOS canonical roadmap)

**DECIDED:** OMP-based client, Windows/NAS TorrServer, **giữ website torrent source search**.  
**UNVERIFIED:** runner dự án đã đăng ký/online hay chưa; chưa clone/build APK, chưa test TV/server thật.

| Order | Alias | Scope | Exit |
| --- | --- | --- | --- |
| 0 | PROJECT-BOOTSTRAP (DONE docs-first) | Repo private + contract/PRD | GitHub repo tồn tại, docs được version |
| 1 | OMP-EVAL-001 (DRAFT) | **Verify dedicated project runner + separate workspace first**, pinned upstream OMP/submodule, GPL/security/dependency audit, isolated clone/build & TV/server preflight; source adapters không bị tắt | Runner identity/online proof hoặc `DEDICATED_RUNNER_UNVERIFIED`; npm/Gradle build evidence hoặc blocker; TV/server thật PASS riêng hoặc UNVERIFIED |
| 2 | OMP-VI-002 (PROPOSED) | Việt hóa TS/Kotlin UI; `vi/vie` audio/sub; UTF-8 SRT/VTT; giữ website source search | UI Việt, D-pad, fixture Vietsub và source-search smoke trên TV/box |
| 2a | P1-SRT-REMOTE (DECIDED scope / PROPOSED implementation) | Ưu tiên duyệt **SMB read-only Windows share** bằng remote TV để nạp SRT/VTT vào OMP VLC; USB/TV fallback, nhớ track theo phim và offset; không bật share/port/firewall trước Human authorization riêng | TV thật: SMB2/3 authentication, D-pad/Back, Unicode Vietsub, seek/resume, VLC audio còn PASS; kiểm thử server offline/sai credential/permission, USB fallback; trước E2E = `SMB_SRT_UNVERIFIED` | 
| 3 | OMP-HARDEN-003 (PROPOSED) | Security URL credentials, OMP legacy billing/background isolation, permission/autostart review, LAN resilience | Không leak secret, search website vẫn hoạt động, E2E real server+TV hoặc blockers |
| 4 | OMP-RELEASE-004 (PROPOSED) | Packaging/licensing, doc Windows/NAS, Human-approved APK release | GPL attribution/compliance, stable repeatable build, Human release approval |
| 5 | OMP-AI-005 (OPTIONAL P2) | Windows/NAS ASR/translation/QA/TTS, audio sync/mux proof | Legal fixture, QA tiếng Việt, seek/sync evidence; chỉ opt-in |

`TVAPP-001` trước đây là bản DRAFT dựng Kotlin/Compose shell; **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Mọi alias không phải TASK ID của AIOS. Để giao việc phải fresh Brain Sync, xác minh canonical NEXT/admission/executor/cross-repo authority và review. Không auto dispatch/merge/publish.
