# Thiết lập ChatGPT Project — Torrent TV Vietsub

1. Tạo hoặc đổi tên ChatGPT Project thành **Torrent TV Vietsub** (không có hậu tố “— AIOS”). Đây là dự án độc lập.
2. Trong Project settings → Instructions, sử dụng `chatgpt/PROJECT_INSTRUCTIONS.md`.
3. Trong Project sources, có thể thêm `docs/PROJECT_CONTRACT.md`, `docs/ARCHITECTURE.md`, `docs/PRD.md`, `docs/ROADMAP.md`, `docs/SECURITY.md`, `docs/DEVELOPMENT_WORKFLOWS.md`, ADR-0002/0006/0007. Khi có quyền GitHub, ưu tiên branch/commit thực so với bản upload cũ.
4. Workflow/runner/PR là của **Torrent TV**; không cấu hình AIOS Brain/TASK/dispatch hoặc dùng chung AIOS runner/credentials.
5. Ví dụ prompt: “Đọc contract và architecture hiện hành của Torrent TV trên GitHub; giữ OMP làm codebase, không viết lại Kotlin + Compose + Media3; kiểm tra Draft PR và gate P0/P1; không dùng AIOS runtime/dispatch.”

Việc đổi tên hoặc cấu hình Project trong giao diện ChatGPT do người dùng thực hiện; cập nhật tài liệu GitHub không tự đổi tên Project.
