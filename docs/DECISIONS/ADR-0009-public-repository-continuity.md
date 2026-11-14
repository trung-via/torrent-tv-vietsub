# ADR-0009 — Cho phép PUBLIC GitHub repository và tiếp tục dự án

**Ngày Human quyết định:** 2026-11-04  
**Trạng thái:** `HUMAN_DECIDED / PR_REVIEW_PENDING`  
**Phạm vi:** GitHub visibility, development continuity, supply chain và self-hosted CI; **không** thay product architecture, runtime LAN, TV/server acceptance hoặc APK release.

## Context

Các tài liệu trước từng mô tả repo `trung-via/torrent-tv-vietsub` là PRIVATE. Human muốn tiếp tục dự án khi chuyển repo sang PUBLIC. Đây là quyết định **cho phép trạng thái PUBLIC**, không phải bằng chứng GitHub đã chuyển hay lệnh tự động đổi visibility, merge hoặc release.

## Decision

1. Repo có thể là `PRIVATE` hoặc `PUBLIC`; cả hai đều là trạng thái hợp lệ. Việc chuyển sang PUBLIC **không chặn** source work, issue/PR, runner/CI được kiểm soát, OMP-first, P0–P5, accepted decisions hoặc verification còn hiệu lực. Giữ nguyên repo/Git history/branches và tiến độ; không phải tạo repo mới hay quay về PRIVATE.
2. Chuyển visibility chỉ khi Human yêu cầu cụ thể. Trước thao tác phải audit commit history, branches/tags/releases, source/fixtures, PR/issue/artifacts, credentials, personal magnet/passkeys, LAN IP, media licenses, OMP GPL-3.0-only, submodule/dependency notices. Nếu có blocker, tạm hoãn **public switch**, vẫn được tiếp tục công việc độc lập/an toàn.
3. Sau PUBLIC, coi fork PR, issue/comment và user-controlled input là không tin cậy. Không dùng self-hosted Windows runner có host access/secrets để build/run mã PR không tin cậy hoặc `pull_request_target` checkout mã PR. Các job đặc quyền chỉ chạy trusted ref có review, quyền tối thiểu, xác thực SHA/owner và log redaction. CI public dành cho input không tin cậy phải cách ly và không chứa secrets.
4. Public source code không cấp quyền public TorrServer/Gateway/ADB/SMB/WAN, không cho phép dùng media trái phép hoặc tự động phân phối APK/GitHub Release. Approval/signing/release có gate riêng.
5. Giữ quyền quản trị độc lập với AIOS theo ADR-0007; OMP-first, TorrServer LAN và evidence hierarchy không đổi. Repo visibility **không phải** acceptance gate của chức năng.

## Consequences

- Cập nhật `chatgpt/PROJECT_INSTRUCTIONS.md`, `AGENTS.md`, Contract, PRD, Architecture, Security, Development Workflows và README để không hard-block khi PUBLIC.
- Kịch bản công khai yêu cầu separate preflight/permission; không chạy scan, workflow, runner hoặc GitHub visibility switch chỉ vì tài liệu này được tạo.
- Nếu đã công khai, không coi PRIVATE là điều kiện để được mở lại công việc. Vấn đề security/license cụ thể được xử lý thành blocker riêng theo mức độ.

## Acceptance

- Tài liệu quy tắc cho phép `PRIVATE|PUBLIC`, tiếp tục trên cùng repo và giữ nguyên acceptance gates.
- Public CI/runner rules bảo vệ host/secrets trước untrusted PR và workflow comment/dispatch.
- Không thay đổi visibility, CI trigger, runner service, OS/TV/network hoặc publish APK trong PR này.

## Rollback

Nếu cần thay đổi quyết định, tạo ADR/PR mới sau Human approval. Không rewrite history hoặc xóa evidence chỉ để điều chỉnh visibility.
