# OMP-EVAL-001 — Torrent TV internal feasibility task (DRAFT)

**Date:** 2026-10-28  
**Status:** `DRAFT_ONLY / NOT_DISPATCHED`; planning alias nội bộ Torrent TV, **không phải AIOS TASK**.  
**Target:** `trung-via/torrent-tv-vietsub` PRIVATE, dedicated runner/workspace, independent GitHub Actions.  
**Authority:** `PROJECT_CONTRACT.md` v2.0 after merge, ADR-0001/0002/0006/0007, `DEVELOPMENT_WORKFLOWS.md`.  
**Upstream audit snapshot (not build pin proof):** `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`; verify submodule/lockfiles/license again.

## Objective

Đánh giá có bằng chứng việc sử dụng OMP làm nền tảng Torrent TV: build APK, website source search vẫn hoạt động với nguồn hợp pháp, player/remote/Vietsub, security/GPL, TorrServer Windows/NAS và Redmi TV thật. Không nhập mã upstream vào `main` trước khi có PR review.

## A — Read-only audit (không cần AIOS)

1. Kiểm tra target repo/branch/open Draft PRs; xác minh runner riêng bằng GitHub registration, labels, online/run evidence, isolated workspace/permissions. Không dùng AIOS runner/worktree/credentials; không cần Brain Sync/NEXT/admission/dispatch.
2. Audit source OMP commit, `2160player` submodule SHA, lockfiles, license/dependencies, billing/background modules, manifest, URL credentials và source adapters. Giữ website search; không gọi website không có quyền.
3. Đối chiếu toolchain và các workflow đã có trong `.github/workflows/`; không tự chạy hoặc chỉnh service. Nếu copy pattern từ AIOS, phải có provenance/license/secret review và PR riêng.
4. Xác minh scope, fixtures legal, thiết bị/host có thể test; ghi rõ những gì chưa có evidence.

## B — Isolated build (chỉ khi có approval)

- Clone OMP pinned + recursive submodules vào **workspace riêng của Torrent TV**, không import thẳng `main`; dùng runner đúng repo và trusted ref.
- Chạy npm/TypeScript build/test và Android Gradle debug/test theo upstream đã xác minh; ghi versions, APK SHA, sanitized logs, failure taxonomy.
- Smoke legal-source UI/search, manual magnet, player track parsing, server offline/timeout/auth, không dùng media không có quyền.
- Nếu license/provenance/credential issue không thể giải quyết, STOP; không tự publish.

## C — Real device/server (chỉ khi được phép)

- Redmi model/firmware/API/ABI, sideload, D-pad/Back, player video/audio/seek/resume, Vietnamese UI/SRT.
- Windows/NAS TorrServer deployed version/API, LAN health/list/stream/Range/auth/seek, legal media fixture.
- P1 SRT external: theo ADR-0006, G0 debug render không phải G1 ngoài APK; hot-add, sync, release gate độc lập.

## Acceptance

| Gate | Evidence |
| --- | --- |
| AC-DEV | Dedicated Torrent TV runner/workspace, repo-scoped GitHub Actions, no AIOS dependency; run ID nếu đã authorized |
| AC-OMP | OMP/submodule pinned SHA, license inventory, clean build/tests, APK checksum |
| AC-SOURCE | Website search adapters còn hoạt động trong UI với nguồn/fixture được phép |
| AC-SEC | No secrets/userinfo leak; permissions, background/billing isolation review |
| AC-SERVER | Real TorrServer Windows/NAS evidence hoặc `REAL_SERVER_UNVERIFIED` |
| AC-TV | Real Redmi evidence hoặc `REAL_TV_UNVERIFIED` |
| AC-P1 | External subtitle G0/G1/G2/G3/G4 riêng, không false PASS |
| AC-CHANGE | Không auto merge, dispatch, publish, mở Windows service/firewall/SMB/WAN, không sửa AIOS |

## Deliverables

Report với source/commit, diff/provenance, build/test logs sanitized, license/security findings, legal source-search inventory, real TV/server matrix và đề xuất PR nhỏ. Chưa có evidence thì `UNVERIFIED`/`BLOCKED`; không hứa kết quả Deep Research chưa được công bố.
