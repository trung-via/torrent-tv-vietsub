# Roadmap v2.1 — OMP-based app repo (không phải AIOS canonical roadmap)

**DECIDED:** OMP-based client, Windows/NAS TorrServer, **giữ website torrent source search**.  
**UNVERIFIED:** runner dự án đã đăng ký/online hay chưa; chưa clone/build APK, chưa test TV/server thật.

| Order | Alias | Scope | Exit |
| --- | --- | --- | --- |
| 0 | PROJECT-BOOTSTRAP (DONE docs-first) | Repo private + contract/PRD | GitHub repo tồn tại, docs được version |
| 1 | OMP-EVAL-001 (DRAFT) | **Verify dedicated project runner + separate workspace first**, pinned upstream OMP/submodule, GPL/security/dependency audit, isolated clone/build & TV/server preflight; source adapters không bị tắt | Runner identity/online proof hoặc `DEDICATED_RUNNER_UNVERIFIED`; npm/Gradle build evidence hoặc blocker; TV/server thật PASS riêng hoặc UNVERIFIED |
| 2 | OMP-VI-002 (PROPOSED) | Việt hóa TS/Kotlin UI; `vi/vie` audio/sub; UTF-8 SRT/VTT; giữ website source search | UI Việt, D-pad, fixture Vietsub và source-search smoke trên TV/box |
| 3 | OMP-HARDEN-003 (PROPOSED) | Security URL credentials, OMP legacy billing/background isolation, permission/autostart review, LAN resilience | Không leak secret, search website vẫn hoạt động, E2E real server+TV hoặc blockers |
| 4 | OMP-RELEASE-004 (PROPOSED) | Packaging/licensing, doc Windows/NAS, Human-approved APK release | GPL attribution/compliance, stable repeatable build, Human release approval |
| 5 | OMP-AI-005 (PROPOSED P2; feature requested) | **AI Vietsub on-demand trước:** SRT/VTT nguồn → dịch Việt; nếu thiếu → Windows/NAS ASR → dịch Việt → QA/timestamp; import SRT rời vào OMP VLC; tái sử dụng track theo phim. **Sau đó riêng:** TTS/thuyết minh, audio-sync/mux PoC | Hai fixture hợp pháp (có SRT nguồn và audio-only lời thoại), SRT/VTT UTF-8 và sync, playback thật trên Redmi TV, consent/local-first, đo tài nguyên; `AI_VIETSUB_UNVERIFIED` cho đến E2E PASS |

`TVAPP-001` trước đây là bản DRAFT dựng Kotlin/Compose shell; **SUPERSEDED** bởi ADR-0002, giữ làm lịch sử. Mọi alias không phải TASK ID của AIOS. Để giao việc phải fresh Brain Sync, xác minh canonical NEXT/admission/executor/cross-repo authority và review. Không auto dispatch/merge/publish.
