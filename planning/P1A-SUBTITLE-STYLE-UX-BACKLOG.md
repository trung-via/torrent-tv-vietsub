# P1a — Subtitle styling UX backlog (không chặn PoC)

**Trạng thái:** `DEFERRED_BY_HUMAN / PROPOSED_UX_WORK / NOT_P1A_AC`
**Nguồn:** Quyết định Human ngày 2026-10-25: chốt tính năng nạp SRT rời trước; chữ hơi mỏng chấp nhận được, chưa yêu cầu chỉnh style.
**Liên kết:** [P1a acceptance](P1A-ACCEPTANCE-CRITERIA-20261025.md) · [ADR-0006](../docs/DECISIONS/ADR-0006-p1-source-agnostic-external-subtitle.md).

## Backlog UX sau P1a

| ID | Nội dung hoãn | Trạng thái / ràng buộc |
| --- | --- | --- |
| UX-SUB-01 | Tăng font-weight/độ đậm nếu người dùng cần | DEFERRED; không là điều kiện G0/G1 PASS |
| UX-SUB-02 | Đánh giá thay font/font family phù hợp chữ Việt | DEFERRED; chỉ sau đánh giá renderer thực |
| UX-SUB-03 | Tùy chỉnh viền (outline) và bóng (shadow) | DEFERRED; không mặc định thêm hiệu ứng |
| UX-SUB-04 | Tùy chọn nền/background phụ đề | DEFERRED; không tự thêm overlay khi PoC |
| UX-SUB-05 | Tinh chỉnh kích cỡ chữ/size cho khoảng cách xem TV | DEFERRED; chưa định ngưỡng hoặc UI control |

## Ranh giới với P1a

- **DECIDED — vẫn bắt buộc:** UTF-8 đúng dấu, ký tự không bị thay thế/mất, text không bị cắt và còn đọc được ở điều kiện test thực. Lỗi mất dấu/clipping/không đọc được là defect của P1a, không được đẩy sang backlog để tuyên bố PASS.
- **DECIDED — không bắt buộc:** độ đậm, font mới, viền/bóng, nền và tinh chỉnh size. Nhận xét `chữ hơi mỏng` trong hai ảnh là quan sát UX, không phải FAIL.
- **UNVERIFIED:** chưa đo legibility theo khoảng cách/màn hình hay so sánh style trên OMP VLC thực. Hai ảnh không xác nhận external SRT hoặc thao tác player.
- **PROPOSED:** sau G1 real-TV proof, chọn ưu tiên UX với Human; tạo acceptance và patch riêng nếu cần, bảo toàn việc chọn track, audio và hiệu năng. Không gộp vào PR #15 hoặc PoC G0/G1 dưới dạng code.

Không chọn SMB/phone source, không đổi player, không thêm backend/permissions và không thay đổi `AIOS-renew` từ backlog này. Không tự author/dispatch TASK, merge hoặc release.
