# Thiết lập ChatGPT Project — Torrent TV Vietsub

1. Tạo hoặc đổi tên Project thành **Torrent TV Vietsub** (bỏ hậu tố “— AIOS”). Project này quản lý sản phẩm độc lập.
2. Trong Project settings → Instructions, dùng nội dung `chatgpt/PROJECT_INSTRUCTIONS.md`. Khi cần nguồn, ưu tiên repo GitHub `trung-via/torrent-tv-vietsub` và branch/commit thực, không coi file upload cũ là canonical.
3. Thêm `docs/PROJECT_CONTRACT.md`, `docs/ARCHITECTURE.md`, `docs/PRD.md`, `docs/ROADMAP.md`, `docs/SECURITY.md`, `docs/DEVELOPMENT_WORKFLOWS.md` và ADR-0007 vào Project sources nếu muốn dùng như tài liệu tham khảo.
4. Các alias `OMP-EVAL-001`/`P1-G1` là backlog nội bộ Torrent TV, không phải TASK ID của AIOS. Không cấu hình AIOS Brain/dispatch hoặc chia sẻ runner/workspace/credentials.
5. Nếu dùng GitHub integration, kiểm tra repository/branch/PR trước khi sửa; dùng PR review riêng của Torrent TV. Không tự bật Actions, điều khiển runner, Windows hay TV chỉ từ Project instructions.

**Ví dụ prompt mở đầu:** “Đọc contract và architecture hiện hành của Torrent TV Vietsub trên GitHub, kiểm tra Draft PR và các gate P0/P1. Không sử dụng AIOS runtime/dispatch; báo DECIDED/PROPOSED/UNVERIFIED và đề xuất PR nhỏ.”

Việc đổi tên/thiết lập Project trong giao diện ChatGPT do người dùng thực hiện; tài liệu repo không tự đổi tên Project.
