# Agent contract — Torrent TV Vietsub (independent, OMP-first)

**Repo:** `trung-via/torrent-tv-vietsub`. **Không thuộc AIOS.**

## Before any change

1. Đọc `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/DEVELOPMENT_WORKFLOWS.md` và ADR-0001/0002/0006/0007. Kiểm tra repo, branch, SHA, Draft PR thật; file upload cũ không phải canonical.
2. **OMP là codebase ứng dụng:** TypeScript/Preact + Capacitor UI và native Kotlin/2160 Player/Media3/VLC **có sẵn trong OMP**. Không viết lại app mới bằng Kotlin + Compose + Media3. Windows/NAS TorrServer là server LAN ngoài APK.
3. Dự án có GitHub Issues/PR/ADR, Actions, runner/workspace/credentials riêng. **Không gọi AIOS** Brain Sync/NEXT/TASK/admission/executor/reviewer/dispatch/Runtime/runner; không sửa `AIOS-renew`.
4. Nếu kế thừa file/mẫu từ AIOS, bắt buộc ghi source commit/path/license, kiểm tra secrets/permissions/dependencies, đổi repo/labels/paths, test và rollback trong PR. Không import AIOS runtime hoặc tự đồng bộ.
5. Giữ OMP website source search adapters và manual magnet/.torrent cho nguồn/media hợp pháp; không crawler trái phép, DRM bypass, piracy index hoặc thu thập passkey.
6. Giữ library, remote D-pad, resume, series/track; ưu tiên UI `vi`, audio/subtitle `vi/vie`, SRT/VTT Unicode. Theo ADR-0006, G0 debug fixture ≠ G1 external file ≠ G2 hot-add ≠ G3 sync ≠ G4 release.
7. Gateway/ChatGPT agent, metadata ranking và AI Vietsub/voice-over là module đề xuất theo phase, không phải chức năng đã có. Side effects cần auth/confirmation, legal media, consent, cost và real-device evidence.
8. Không tự chạy workflow, cài/đổi runner service, mở SMB/firewall/router/WAN, sửa TV, ký/phát hành APK, auto merge. Verify runner identity/online/workspace khi được phép; không fallback sang AIOS runner.
9. Audit GPL/dependencies, native stream URL credential leakage, CI logs và artifacts; không báo mock/build là `REAL_TV_PASS`/`REAL_SERVER_PASS`.

**Output:** changed files, acceptance/evidence, explicit `DECIDED`/`PROPOSED`/`UNVERIFIED`/`BLOCKED`, risks, blockers, next handoff. Không tự nhận Deep Research, TV hoặc runner đã PASS nếu chưa có evidence.

## Deep Research alignment — project engineering rules

- Review docs/RESEARCH_ALIGNMENT_2026-10-28.md and proposed ADR-0008 for discovery, session Gateway, media verification and AI voice-over work. Research is not deployed evidence or acceptance of every technology suggestion.
- **OMP-first outranks the report's separate Kotlin/Media3 app workstream**. Extend existing OMP Preact/Capacitor and 2160/Media3/VLC native layers only after actual source/device proof.
- Keep manual playback and OMP website sources. Treat reported/scraped/connected seeders as separate observations, probe real media, prioritize embedded vi audio + external SRT/VTT, and batch licensed voice-over before rolling.
- Do not expose native TorrServer /mcp/admin to ChatGPT, put credentials in TV URLs, open WAN, assume MCP tunnel entitlement or rely on AIOS admission/dispatch. Use Torrent TV PRs/review/CI and record measured gate evidence.
