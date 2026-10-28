# OMP-EVAL-001 — Feasibility task nội bộ Torrent TV (DRAFT)

**Status:** `DRAFT_ONLY / NOT_DISPATCHED` — alias backlog **Torrent TV**, không phải AIOS TASK.  
**Target:** `trung-via/torrent-tv-vietsub` PRIVATE, GitHub Actions/runner/workspace riêng.  
**Authority:** Project Contract v2.0 (sau merge), ADR-0001/0002/0006/0007, Development Workflows.  
**Upstream audit snapshot:** `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f` (không tự chứng minh build pin).

## Objective

Chứng minh **OMP là nền tảng phát triển phù hợp** và giữ các tính năng website source search, native player 2160/Media3/VLC, Vietsub và remote; **không dựng lại app Kotlin + Compose + Media3**. Audit license/security, build debug, thử TorrServer Windows/NAS và Redmi TV thật bằng media hợp pháp.

## A — Read-only audit

1. Xác minh repo/branch/SHA, Draft PRs, GitHub runner registration/online/labels/workspace isolation. Không cần AIOS Brain Sync/NEXT/admission/dispatch, không dùng AIOS runner.
2. Pin OMP upstream commit, `android/vendor/2160player` submodule SHA, lockfiles, license/dependencies; inventory website adapters, user-configured sources, paid/bot/background modules và URL credentials.
3. Audit workflow repo Torrent TV. Nếu tham khảo mã/mẫu AIOS, ghi commit/path/license và security review trước khi copy.
4. Xác minh fixture hợp pháp, firmware/API/ABI Redmi, Windows TorrServer version/API, auth/stream/Range; ghi thiếu evidence là UNVERIFIED.

## B — Isolated build (only when authorized)

- Clone pinned OMP + recursive submodule trên **runner/workspace riêng Torrent TV**, không import thẳng vào `main`.
- Chạy npm/TypeScript, Capacitor/Android Gradle build/test theo upstream đã xác minh; lưu tool versions, APK SHA và logs đã redact.
- Smoke UI/source search với legal fixture; manual magnet, track/Unicode, server offline/auth/no peers; không tự crawler hoặc publish.
- STOP nếu license, provenance, secrets hoặc toolchain không an toàn.

## C — Real device/server (only when authorized)

- Redmi thật: install, D-pad/Back, video/audio/seek/resume, SRT/VTT tiếng Việt, external subtitle G0/G1/G2/G3/G4 tách riêng.
- Windows/NAS TorrServer thật: version/API, legal fixture, stream/seek/Range/auth/offline.
- Không báo PASS từ mock/build/PR tên “test”.

## Acceptance

| Gate | Evidence |
| --- | --- |
| DEV | Dedicated runner/workspace/CI của Torrent TV, không AIOS dependency; run ID nếu đã chạy |
| OMP | Pin SHA/license, build/test/APK checksum, website search còn hoạt động |
| SECURITY | Không leak secret/userinfo; kiểm manifest và dependency |
| SERVER/TV | Real host/device logs/firmware hoặc `REAL_SERVER_UNVERIFIED`/`REAL_TV_UNVERIFIED` |
| P1 | External SRT gates G0–G4 riêng |
| CHANGE | Không auto merge/dispatch/publish, không sửa AIOS, Windows/TV/network |

**Deliverable:** evidence matrix, sanitized logs, licensing/security findings, legal source inventory, đề xuất PR nhỏ/rollback. Không tự chạy workflow hoặc cài TV từ tài liệu.
