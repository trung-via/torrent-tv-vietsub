# Torrent TV Vietsub

**Dự án độc lập với AIOS.** Ứng dụng xem video gia đình trên Android TV/Google TV/Redmi tương thích, sử dụng magnet/.torrent và các nguồn người dùng có quyền truy cập; ưu tiên Vietsub, audio tiếng Việt và remote D-pad.

## Kiến trúc được chọn: OMP-first

**Tiếp tục phát triển trên mã nguồn OMP**, không viết lại ứng dụng bằng **Kotlin + Jetpack Compose + Media3**. OMP cung cấp UI TypeScript/Preact + Capacitor và các native player Kotlin/2160 Player/Media3/VLC *bên trong chính OMP*. Tùy biến OMP cho tiếng Việt, tìm kiếm nguồn hợp lệ, thư viện, resume, phụ đề và trải nghiệm TV.

```text
User / TV remote / phone
            |
  OMP-derived UI + native player (existing OMP stack)
            |                         ^
            v                         | HTTP stream on trusted LAN
    TorrServer on Windows/NAS --------+
            ^
Optional Torrent TV search/gateway/AI worker
(PROPOSED, opt-in; no AIOS runtime)
```

Windows PC chạy TorrServer mặc định; NAS tùy chọn. TV là client, không nhúng torrent engine vào APK. Giữ OMP website torrent search adapters và nhập magnet/.torrent thủ công; chỉ dùng nguồn/media có quyền, không vận hành piracy catalog/crawler trái phép hoặc vượt DRM.

**North Star (đề xuất theo giai đoạn, chưa E2E):** lọc kết quả tìm kiếm hợp pháp theo chất lượng/dung lượng/metadata, xác nhận trước khi thêm torrent và phát lên TV; tùy chọn AI Vietsub/thuyết minh trên Windows/NAS sau PoC.

## Phát triển hoàn toàn độc lập AIOS

Repo `trung-via/torrent-tv-vietsub` (PRIVATE) có GitHub Issues/PR/ADR, GitHub Actions, self-hosted runner, workspace, credentials, artifacts và release **riêng**. Không dùng AIOS Brain Sync, TASK/admission, dispatch, executor, review, runtime hoặc runner. Có thể **tái sử dụng chọn lọc** mã nguồn/mẫu GitHub Actions, runner guard, script từ AIOS sau kiểm tra provenance, license, secrets và PR review; không tạo phụ thuộc vận hành.

## Tài liệu

- [Project Contract v2.0](docs/PROJECT_CONTRACT.md), [Architecture v3.0](docs/ARCHITECTURE.md), [PRD v4.0](docs/PRD.md), [Roadmap v3.0](docs/ROADMAP.md).
- [Development Workflows](docs/DEVELOPMENT_WORKFLOWS.md), [Security](docs/SECURITY.md), [ADR-0007 — Independence](docs/DECISIONS/ADR-0007-independent-project-and-selective-reuse.md).
- [ADR-0001 — Windows/NAS](docs/DECISIONS/ADR-0001-client-server.md), [ADR-0002 — OMP](docs/DECISIONS/ADR-0002-omp-baseline.md), [ADR-0006 — external subtitle](docs/DECISIONS/ADR-0006-p1-source-agnostic-external-subtitle.md).
- [OMP feasibility draft](planning/OMP-EVAL-001-DRAFT.md), [AGENTS.md](AGENTS.md), [ChatGPT instructions](chatgpt/PROJECT_INSTRUCTIONS.md).

**Trạng thái:** `main` và nhiều Draft PR/PoC có lịch sử riêng; tài liệu mới ở PR review chưa đồng nghĩa code/build/TV/server/agent đã PASS. Kiểm tra commit, runner, real TV/server evidence trước kết luận. Không auto merge, trigger workflow, thay Windows/TV/network hay publish APK.

**License:** audit OMP GPL-3.0-only, submodule và third-party licenses trước import/phân phối; repo PRIVATE không tự miễn nghĩa vụ GPL.
