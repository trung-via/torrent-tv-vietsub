# Torrent TV Vietsub — AIOS

Dự án ứng dụng phát video gia đình từ magnet/.torrent được phép sử dụng, có phụ đề tiếng Việt, cho Redmi/Xiaomi A Pro 55 2026.

**Trạng thái:** khởi tạo contract/repo; chưa có APK, chưa chứng minh TV hoặc server thật hoạt động.

## Kiến trúc được chọn

```text
Phone or laptop (TorrServer Web UI)
            |
            v
Windows (default) / NAS (optional)
TorrServer: metadata, pieces, cache, HTTP stream
            |
            v
Android TV client (Kotlin + Compose for TV + Media3)
Remote UI / playback / Unicode Vietsub
```

## Đọc trước khi xây dựng

1. [`docs/PROJECT_CONTRACT.md`](docs/PROJECT_CONTRACT.md) — mục tiêu bất biến, ranh giới, acceptance và authority.
2. [`docs/PRD.md`](docs/PRD.md) — phạm vi và các giai đoạn chi tiết.
3. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — kỹ thuật và đường seam.
4. [`docs/ROADMAP.md`](docs/ROADMAP.md) — trình tự P0/P1/P2.
5. [`planning/TVAPP-001-DRAFT.md`](planning/TVAPP-001-DRAFT.md) — TASK khởi tạo, chưa canonical.
6. [`AGENTS.md`](AGENTS.md) — quy định cho coding agents.
7. [`chatgpt/PROJECT_INSTRUCTIONS.md`](chatgpt/PROJECT_INSTRUCTIONS.md) — nội dung dán vào ChatGPT Project Settings.

## Repo bootstrap

Repo này được khởi tạo ở dạng **docs-first**: chỉ có contract, instructions và planning. Không có Android binary hay workflow chạy tự động. Khi đã tải ZIP starter lên Windows, chạy `scripts/publish-private.ps1` nếu đã đăng nhập GitHub CLI để tạo và push repo PRIVATE.

## Không làm

Không có catalog/index phim lậu; không vượt DRM; không nhúng TorrServer vào APK; không public server ra WAN; không tự thay đổi `AIOS-renew`.

## License

Chưa chọn license phát hành của code ứng dụng. Repo mặc định private, all rights reserved tới khi Human quyết định. TorrServer là upstream third-party với license riêng, không có binary vendored.
