# Development workflows — Torrent TV Vietsub only

**Status:** `DRAFT_FOR_PR_REVIEW` · **Owner:** Torrent TV Vietsub · **No AIOS runtime dependency**

## 1. Principle

GitHub Actions là bộ điều phối CI/CD của **repo Torrent TV**, self-hosted runner là executor riêng, PR/ADR là nơi review. AIOS chỉ có thể là **nguồn mã/mẫu để tham khảo và copy chọn lọc**; không dùng Brain Sync, TASK admission, dispatch, reviewer, Runtime journals, runner hay secrets AIOS.

## 2. Existing workflow inventory (file-level, không phải run evidence)

| Workflow path | Vai trò theo YAML/tên file | Gate |
| --- | --- | --- |
| `.github/workflows/torrent-tv-runner-smoke.yml` | Kiểm runner identity/repo/workspace | Human-approved manual run; không chứng minh online chỉ bằng YAML |
| `.github/workflows/torrent-tv-toolchain-preflight.yml` | Kiểm toolchain Windows/Android | Diagnostic only, không tự cài |
| `.github/workflows/omp-fast-build.yml` | Build OMP debug pinned + APK checksum | Manual, runner riêng, license/build evidence |
| `.github/workflows/p1-*-manual.yml` | PoC phụ đề/TV theo snapshot riêng | Audit SHA, branch, host side effects trước run |

Các workflow đang tồn tại không đồng nghĩa tất cả đã chạy PASS; các PR P1 là draft và có thể trỏ đến snapshot/branch khác `main`. Không chỉnh YAML hoặc trigger trong PR thay đổi tài liệu này.

## 3. Runner contract

- Scope repo `trung-via/torrent-tv-vietsub`; runner identity/labels riêng (workflow hiện kỳ vọng `torrent-tv-vietsub-win` / `torrent-tv-vietsub`), workspace, cache, service account và credentials cách ly khỏi AIOS.
- Kiểm tra actual GitHub runner registration, online status, run ID, host path, branch, SHA, permissions và log đã redact trước khi báo `RUNNER_READY`.
- Cùng máy vật lý có thể chấp nhận **chỉ nếu** isolation được chứng minh; không tái sử dụng runner service, worktree, cache, token hoặc journal AIOS.
- Không cài/đổi service, đăng ký runner, sửa firewall/OS hoặc chạy workflow chỉ theo lời suy diễn từ tài liệu.

## 4. Reuse AIOS source/template checklist

Mỗi PR tái sử dụng phải có:

1. Source repository, path, commit SHA, author/license và bằng chứng quyền tái sử dụng; không copy secret, token, cấu hình máy cá nhân.
2. Mô tả chức năng cần lấy, tại sao phù hợp, file-level diff và dependencies; ưu tiên template tối thiểu thay vì copy nguyên workflow/orchestrator.
3. Đổi namespace, repo, branch, runner labels, workspace, paths, artifact names, permission, trigger; **loại bỏ mọi call tới AIOS**, cross-repo dispatch, journals, canonical TASK.
4. Pin SHA cho third-party actions, least-privilege `permissions`, timeouts, checksum/provenance, log redaction, rollback.
5. Test an toàn trên branch và runner của Torrent TV khi được phép; PR review trước merge. Không auto-sync với upstream AIOS.

## 5. Security policy cho GitHub Actions

- Không chạy code từ PR không tin cậy trên self-hosted runner có host access/secrets; không dùng `pull_request_target` để checkout/run mã người đóng góp.
- `GITHUB_TOKEN` mặc định chỉ `contents: read`; quyền ghi chỉ ở job/release được Human duyệt. Không đưa credentials vào URL/command line/log.
- Manual dispatch cho job cài/chạy APK/ADB hoặc chạm Windows host; action chạy trên host phải có bounded timeout, exact ref và stop conditions.
- Artifact APK/checksum là evidence của build, **không** là bằng chứng TV/server real PASS. Giữ retention ngắn, private; không tự publish.
- Branch protection/review policy là quyết định của repo Torrent TV, không phụ thuộc AIOS.

## 6. Definition of Done cho workflow change

PR có diff/owner, provenance, threat review, action pin, permissions, runner isolation, test logs sanitized, rollback và Human approval. Nếu runner offline/không rõ scope thì `RUNNER_UNVERIFIED`; nếu license/secret/permission không an toàn thì `BLOCKED`. Không fallback sang AIOS runner.
