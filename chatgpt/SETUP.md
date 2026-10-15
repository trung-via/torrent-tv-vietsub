# Tạo ChatGPT Project

1. Trong ChatGPT, chọn **Dự án mới / New project** ở thanh bên; tên: **Torrent TV Vietsub — AIOS**.
2. Nếu có tùy chọn memory, chọn **Bộ nhớ chỉ dành cho dự án / Project-only** để cô lập khỏi các luồng AIOS và chat khác. Khi chọn chế độ này, phải tải/đính kèm các tài liệu dự án vào Project vì ChatGPT không tham chiếu các chat bên ngoài.
3. Vào dấu ba chấm `•••` của Project -> **Cài đặt dự án / Project settings** -> **Instructions**. Dán toàn bộ file `chatgpt/PROJECT_INSTRUCTIONS.md`.
4. Trong **Project sources**, thêm `docs/PROJECT_CONTRACT.md`, `docs/PRD.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md` và `planning/TVAPP-001-DRAFT.md` (có thể thêm files sau).
5. Khi GitHub repo đã tạo, dùng liên kết GitHub của repo trong cuộc chat Project và gọi app GitHub (nếu đã kết nối) để kiểm tra commit/nhánh hiện hành trước việc sửa code. Tài liệu upload chỉ là snapshot, còn nguồn canonical của app là repo GitHub.
6. Chat đầu tiên trong Project: "Đọc contract và PRD của dự án Torrent TV Vietsub. Kiểm tra GitHub repo ở nhánh main theo quyền truy cập, không dispatch AIOS. Báo các điểm DECIDED/UNVERIFIED và kế hoạch triển khai TVAPP-001."

Không có API/connector hiện tại để tạo Project và ghi instructions tự động trong chính cuộc chat này; các bước giao diện cần người dùng thực hiện.
