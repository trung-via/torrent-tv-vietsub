# ADR-0007 — Torrent TV Vietsub độc lập AIOS, chỉ tái sử dụng có chọn lọc

**Ngày quyết định Human:** 2026-10-28  
**Trạng thái:** `ACCEPTED_DIRECTION / DOCUMENTATION_PR_PENDING`  
**Phạm vi:** governance, development workflow, runner, workspace và runtime boundary.  
**Supersedes:** ADR-0003 các đoạn coi AIOS là nguồn authoring/admission/dispatch tiềm năng; các đoạn AIOS canonical trong Contract v1.x, PRD v3.x, Architecture v2.x, planning/OMP-EVAL. **Giữ nguyên** yêu cầu repo/workspace/self-hosted runner riêng trong ADR-0003. Không thay ADR-0001/0002/0006 hoặc xóa lịch sử.

## Context

Dự án đã có GitHub repo riêng và các GitHub Actions thủ công. Tuy vậy tài liệu cũ còn diễn giải rằng AIOS có thể giữ quyền canonical hoặc dispatch tới runner Torrent TV. Human nay xác định **Torrent TV là dự án độc lập hoàn toàn**, chỉ tham khảo/tái sử dụng mã nguồn phù hợp từ AIOS để thiết kế workflow repo (ví dụ GitHub Actions, self-hosted runner).

## Decision

1. Torrent TV có **quyền quản trị riêng**: Human → Torrent TV Issues/PR/ADR → review → GitHub Actions → dedicated runner → artifact/release. Không có AIOS Brain Sync/NEXT/TASK/admission/executor/reviewer/dispatch trong đường phát triển hoặc runtime.
2. Không tạo liên kết phụ thuộc giữa Torrent TV và `AIOS-renew`: không gọi API, runner, workflow, secrets, journals, locks, workspace, router, canonical tasks hay dữ liệu AIOS. Không sửa repo AIOS khi làm việc trong repo này.
3. Được phép **tham khảo hoặc copy thủ công từng phần** từ AIOS: YAML workflows, shell/PowerShell helper, mẫu CI, guard runner, checklist hoặc kiến trúc build. Mỗi lần phải ghi nguồn commit, license, diff, dependency, security review, adaptation và rollback trong PR.
4. Self-hosted runner **riêng của Torrent TV** vẫn là quyết định bắt buộc; có thể đặt cùng host vật lý nếu isolation đủ, nhưng không dùng chung runner identity/worktree/cache/credentials/Runtime với AIOS. GitHub Actions phải repo-scoped, least-privilege, manual hoặc trusted PR-safe, không trigger từ AIOS.
5. Product runtime chỉ có OMP-derived app, TorrServer Windows/NAS và các module Torrent TV được phê duyệt về sau (local gateway/AI worker). **Gateway không phải AIOS**.
6. Mọi nghiên cứu về agent/voice-over/search là product roadmap có gate riêng, không mặc nhiên bật automation hay khai báo tính năng đã hoạt động.

## Consequences

- Bỏ hoàn toàn bước “fresh AIOS Brain Sync”, “canonical NEXT”, “AIOS cross-repo admission/dispatch” khỏi các task của Torrent TV.
- Alias như `OMP-EVAL-001`, `P1-G1` là backlog nội bộ của Torrent TV; không cần ánh xạ sang TASK ID AIOS.
- Workflow/runner hiện có phải được audit độc lập. Các YAML hardcode runner name/path là expected configuration, không chứng minh online hoặc pass.
- Các ADR cũ còn nhắc AIOS được giữ làm lịch sử; khi xung đột, ADR-0007 có hiệu lực đối với ranh giới AIOS.

## Acceptance

- Contract/Architecture/PRD/Roadmap/AGENTS/README/ChatGPT instructions không còn quy định AIOS admission/dispatch.
- Có `DEVELOPMENT_WORKFLOWS.md` nêu rõ provenance, workflow scope, security và quy trình reuse.
- Không thay đổi source code sản phẩm, chạy runner, bật workflow, merge, release hay sửa repo AIOS chỉ vì ADR này.
- Review PR trước merge; nếu thiếu quyền/license/evidence thì báo `BLOCKED`.

## Rollback

Revert PR tài liệu bằng commit mới sau Human review; không rewrite lịch sử ADR-0003. Mọi quyết định kết nối lại AIOS trong tương lai cần **yêu cầu Human riêng và ADR mới**, không được suy từ “reuse code”.
