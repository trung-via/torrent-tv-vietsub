# Torrent TV Vietsub

**Dự án độc lập — không thuộc AIOS.** Ứng dụng xem video gia đình trên Android TV/Google TV/Redmi tương thích, từ magnet/.torrent và các nguồn người dùng có quyền sử dụng; ưu tiên Vietsub, audio tiếng Việt và trải nghiệm remote.

**Trạng thái:** GitHub repo PRIVATE. `main` hiện là baseline tài liệu OMP-based; các PoC và nhiều Draft PR có lịch sử riêng. Việc có workflow/PR không tự chứng minh APK, Redmi, TorrServer hoặc AI agent đã nghiệm thu. Hướng mới và tài liệu v2/v3/v4 đang ở PR review.

## Kiến trúc sản phẩm

```text
TV/phone user ── OMP-derived UI (Preact/Capacitor)
                       |    Android native 2160/Media3 + VLC
                       |               ^
                       v               | LAN media stream
                 TorrServer Windows/NAS
                       ^
Optional Torrent TV gateway + allowed search/AI worker (future, opt-in)
```

- **Đã quyết định:** OMP baseline, Windows PC TorrServer mặc định/NAS tùy chọn, website torrent source adapters và manual magnet, D-pad/library/resume, tiếng Việt, P1 external SRT/VTT source-agnostic.
- **North Star:** tìm/lọc nội dung hợp pháp theo yêu cầu tự nhiên, chọn bản phù hợp, phát lên TV, hỗ trợ AI Vietsub/thuyết minh theo opt-in. Gateway/TV control/AI voice-over **chưa được xác minh**, không mặc nhiên có trong MVP.
- Không vận hành piracy catalog, crawler trái phép, DRM bypass, WAN-exposed TorrServer/gateway hoặc BitTorrent engine trong APK.

## Dự án độc lập AIOS

Torrent TV sở hữu **Git repository, backlog/Issues, ADR/PR, GitHub Actions, self-hosted runner, workspace, credentials và release riêng**. Không sử dụng AIOS Brain Sync, TASK admission, executor, reviewer, dispatch, runtime hay runner. Chỉ được tham khảo/copy **từng thành phần mã nguồn hoặc mẫu workflow** từ AIOS sau khi kiểm tra commit/license/security và review PR; không có runtime dependency.

Xem [ADR-0007](docs/DECISIONS/ADR-0007-independent-project-and-selective-reuse.md) và [Development Workflows](docs/DEVELOPMENT_WORKFLOWS.md).

## Tài liệu canonical sau khi merge

- [Project Contract](docs/PROJECT_CONTRACT.md): scope, quyền, gates, stop conditions.
- [Architecture](docs/ARCHITECTURE.md): runtime/development plane và boundaries.
- [PRD](docs/PRD.md), [Roadmap](docs/ROADMAP.md), [Security](docs/SECURITY.md).
- [ADR-0001](docs/DECISIONS/ADR-0001-client-server.md), [ADR-0002](docs/DECISIONS/ADR-0002-omp-baseline.md), [ADR-0006](docs/DECISIONS/ADR-0006-p1-source-agnostic-external-subtitle.md), [ADR-0007](docs/DECISIONS/ADR-0007-independent-project-and-selective-reuse.md).
- [OMP evaluation draft](planning/OMP-EVAL-001-DRAFT.md), [Agent instructions](AGENTS.md), [ChatGPT project instructions](chatgpt/PROJECT_INSTRUCTIONS.md).

## First execution gate

Audit workflow/runner thật và các Draft PR đang mở; pin OMP/submodule, GPL/dependency/security review, clean build, thử media legal trên TorrServer Windows và TV Redmi thật. Chỉ chạy CI/ADB/install/release theo phê duyệt cụ thể; không auto merge, không sửa repo AIOS.

**License:** OMP upstream được audit là GPL-3.0-only; xác minh license của mọi dependency và nghĩa vụ cung cấp source tương ứng trước khi phân phối APK. Repo PRIVATE không tự miễn nghĩa vụ GPL.
