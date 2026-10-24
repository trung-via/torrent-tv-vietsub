# Torrent TV Vietsub — AIOS

Dự án phát video từ magnet/.torrent được phép sử dụng, Vietsub và ưu tiên audio tiếng Việt trên Redmi/Xiaomi A Pro 55 (2026) hoặc Android TV/Google TV box tương thích.

**Trạng thái:** Repo GitHub PRIVATE, docs-first. Human đã phê duyệt **kiến trúc dựa trên OMP** ngày 2026-10-25; chưa import/build code OMP tại repo, chưa xác minh APK trên TV hoặc TorrServer thật.

## Kiến trúc quyết định

```text
Phone/TV search (OMP website adapters, user-configured sources) or manual magnet/.torrent
        |
        v
OMP TypeScript/Preact + Capacitor UI / Android native Kotlin
        |                              |
        | TorrServer LAN API           +-- Engine2160 (Media3) / VLC player + Vietsub
        v                              ^
Windows PC (default) / NAS (optional) TorrServer -- HTTP stream --
```

**Giữ chức năng tìm torrent qua website upstream OMP**; không tắt adapters vì quyết định fork. Chỉ dùng nguồn/nội dung được phép, không điều hành kho phim lậu/crawler trái phép hoặc vượt DRM. Không yêu cầu OMP paid billing/VPS/bot trong đường chuẩn của sản phẩm.

## Đọc trước khi triển khai

1. [Project Contract v1.1](docs/PROJECT_CONTRACT.md): authority, phạm vi, compliance và acceptance.
2. [ADR-0002](docs/DECISIONS/ADR-0002-omp-baseline.md): Human quyết định dùng OMP và giữ website search.
3. [PRD v3](docs/PRD.md) và [Architecture v2](docs/ARCHITECTURE.md).
4. [Roadmap](docs/ROADMAP.md) và [OMP-EVAL-001 draft](planning/OMP-EVAL-001-DRAFT.md).
5. [AGENTS.md](AGENTS.md) và [ChatGPT project instructions](chatgpt/PROJECT_INSTRUCTIONS.md).

## Repo trạng thái và bước đầu

Repo chỉ có docs/planning; **chưa clone upstream OMP vào `main`**. First gate là feasibility: pin OMP commit và 2160 Player submodule, audit GPL/security, build debug, giữ search sources, rồi thử TV/server thật có phép. `TVAPP-001` kiểu dựng Compose shell đã superseded; chưa có canonical AIOS TASK/dispatch.

## Quyền sử dụng / license

OMP upstream là GPL-3.0-only; khi nhập source phải tuân thủ GPL và license của dependencies. Repo PRIVATE không miễn nghĩa vụ cung cấp mã nguồn tương ứng nếu phân phối APK. TorrServer dùng upstream bên ngoài, không bundle vào APK. Không thay đổi `AIOS-renew` hoặc tự kích hoạt workflow/release.
