# OMP-EVAL-001 — Read-only upstream evaluation, isolated build and device/server preflight

**Status:** DRAFT ONLY — NOT_CANONICAL / NOT_INGRESSED / NOT_DISPATCHED  
**Human decision:** 2026-10-25 (OMP platform, **retain website torrent sources**).  
**Target:** `trung-via/torrent-tv-vietsub` PRIVATE, independent of `AIOS-renew`.  
**Authority:** `docs/PROJECT_CONTRACT.md` v1.2, ADR-0001, ADR-0002, ADR-0003, PRD v3.1.  
**Upstream audit snapshot:** `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`; recheck actual ref, LICENSE and submodule SHA before execution.

## Objective

Chứng minh nền tảng OMP đủ điều kiện để nhập vào repo sản phẩm: build/debug APK, nguồn website search được giữ, hiệu năng cơ bản, bản quyền GPL/security, native subtitles/audio; tìm blocker thiết bị/server trước khi fork code chính thức.

## Phase A — authority & evidence (read-only)

1. Fresh AIOS Brain Sync từ canonical `AIOS-renew` main/NEXT **nếu dùng tuyến AIOS**, xác thực cross-repo, executor, task admission, review; xác thực chính xác đường dispatch đến runner riêng của Torrent TV Vietsub, **không tự thay bằng runner AIOS**. Không phân bổ ID từ alias.
2. Chứng minh **dedicated self-hosted runner của app** và isolated Git workspace chỉ cho app repo: registration/labels, host identity, online status, root path, quyền vào target Git remote, tách biệt runner/worktree/Runtime state của `AIOS-renew`; nếu chưa đủ chứng cứ `DEDICATED_RUNNER_UNVERIFIED` và không dispatch. Snapshot OMP latest/main + pin submodule `android/vendor/2160player`, license/third-party dependency provenance.
3. Inventory website source adapters và user-configured Jackett/Prowlarr/TorrServer; không disable, không thêm crawler trái phép, không buộc paid OMP billing để tìm website.
4. Read-only review URL credential flow, manifest permissions, boot receiver, hidden background monitoring, OMP paid/bot/VPS integration.
5. Không clone nếu quyền/working tree/target root chưa rõ; không chạm `AIOS-renew`.

## Phase B — isolated build (chỉ khi authorized)

- Chỉ sau runner readiness/authority gate: clean clone pinned OMP + `git submodule update --init --recursive` **trên dedicated app runner và workspace độc lập**; không import source vào `main`. Không dùng runner AIOS làm fallback.
- Run `npm ci`, targeted unit tests, `npm run build:mobile`, Android Gradle `assembleDebug testDebugUnitTest` hoặc lệnh tương đương từ upstream khi version đã xác minh.
- Report Node/Java/Android SDK versions, build outputs, APK checksum, fail logs sanitized. Không bật CI/workflows hoặc secrets tự động.
- Smoke mock/offline TorrServer, player/track/subtitle parsing, website source search UI preserving adapter inventory with legal fixture/test data.
- Evaluate GPL-3.0-only/2160/libVLC/Media3 obligations, source notices, credential handling. Chưa merge/redistribute.

## Phase C — real environment (only when accessible/approved)

- TV model/OS/build/API/ABI; sideload APK and D-pad/Back/launch, player decode/seek/resume, UTF-8 Vietsub sample.
- Windows/NAS TorrServer version/API and legal video stream, health/list/seek/Range/auth failure.
- Nếu không có TV/server, ghi `REAL_TV_UNVERIFIED`/`REAL_SERVER_UNVERIFIED`, không fake PASS.

## Acceptance criteria

| ID | Evidence |
|---|---|
| AC1 | Fresh AIOS canonical auth proof (khi dùng AIOS) and exact authorized dispatch to dedicated target runner, or explicit `BLOCKED` |
| AC1R | Dedicated app runner GitHub registration/labels/online + isolated workspace/root/credentials evidence; otherwise `DEDICATED_RUNNER_UNVERIFIED` |
| AC2 | Pinned OMP SHA and 2160 submodule SHA, clean isolated worktree |
| AC3 | npm/TypeScript + Kotlin/Gradle test results; APK debug SHA if build succeeds |
| AC4 | Website source UI retained; valid legal-source smoke; no paid billing requirement for core website search |
| AC5 | Licensing/GPL + dependency inventory; security finding & test of URL creds/log/redirect/manifest |
| AC6 | Media3/2160/VLC, subtitle/audio `vi/vie` gap inventory and localization patch plan |
| AC7 | Real TV/server evidence or correctly separated UNVERIFIED/BLOCKED |
| AC8 | No repo `main` mutation, no auto publish/dispatch/Windows system/network changes |

## Stop conditions

- Invalid canonical cross-repo admission, dedicated target runner unverified/offline, dispatch routing to AIOS-renew runner, or target workspace isolation uncertain.
- GPL/dependency provenance mismatch, secret in logs/repo, unauthorized site scraping/access/DRM bypass or prohibited network change.
- Build/toolchain blocker; TV firmware incompatible without Human-approved fallback.
- Would require disabling OMP website source search as a blanket policy, contrary to latest Human direction: escalate a scoped conflict instead.

## Deliverables

- Evaluation report and AC matrix + sanitized logs/APK checksum where obtainable.
- File-level keep/remove/enhance plan, source-search preservation test cases, licensing/security issue list.
- Recommendation: import OMP source in a separate follow-up PR, or stop/rollback if infeasible. No automatic merge, release, or AIOS dispatch.
