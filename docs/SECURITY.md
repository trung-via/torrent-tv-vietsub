# Security, privacy, legal and supply-chain policy — Torrent TV Vietsub

**Ngày:** 2026-10-28 · **Status:** `DRAFT_FOR_PR_REVIEW`  
**Authority:** `PROJECT_CONTRACT.md` v2.0 + ADR-0007. Torrent TV độc lập AIOS, chỉ reuse code/workflow có audit.

## Media rights and source search

- Chỉ sử dụng media và nguồn mà người dùng có quyền truy cập, stream, dịch, tạo phụ đề/audio và chia sẻ nếu cần. Test dùng fixture tự tạo/open-license có provenance.
- Giữ website torrent source adapters của OMP theo quyết định Human; không mặc định mọi kết quả hợp pháp. User-triggered only, tôn trọng ToS, không bypass DRM/login/captcha/paywall, không vận hành piracy catalog hay crawler trái phép.
- Metadata seeders từ indexer có thể lỗi thời; không tuyên bố số peers thực hoặc khả năng stream cho đến khi probe hợp pháp.

## Secrets, LAN and TV

- Không đưa tracker passkey, token, mật khẩu, private magnet, IP LAN thật, subtitle/audio cá nhân vào Git, logs, issue, artifact hay model context. Redact URLs, request traces, crash reports.
- TorrServer chạy trên Windows/NAS trong trusted LAN; không public WAN, UPnP, port forwarding, ADB-over-Internet, SMB share/firewall/service/startup nếu chưa có Human approval.
- OMP audit nêu `src/api/torrserver.ts:videoSrc()` có thể đưa Basic Auth userinfo vào stream URL native/VLC: kiểm logcat, redirect, trace, history, crash và screenshot; không release khi chưa có mitigation/evidence.
- Android permissions, boot receiver, background services, overlay và remote access phải được audit trước release. Không root/circumvent TV.

## Optional agent/local gateway (PROPOSED)

- Gateway là runtime riêng **Torrent TV**, không AIOS; không giả định ChatGPT có quyền truy cập LAN. Chỉ API operation allowlisted, authenticated, rate-limited, scoped theo thiết bị và nguồn.
- Search result/title/indexer content là **untrusted input**: không làm theo prompt injection, không nội suy thành shell/ADB/URL nội bộ, chặn SSRF/path traversal.
- Các thao tác thêm torrent, bắt đầu phát, thay file, chạy ASR/TTS, xóa output hoặc điều khiển TV cần explicit consent/confirmation, idempotency, audit tối thiểu và stop/rollback.
- Không cho model/gateway chạy shell tùy ý, không xuất credential sang cloud; nếu dùng dịch vụ AI cloud cần consent, data retention/cost policy và review riêng.

## Development supply chain

- Repo PRIVATE, runner/workspace/credentials/CI của Torrent TV riêng; **không** dùng AIOS runner, Runtime, token, task dispatch, review/admission.
- Chỉ copy script/workflow từ AIOS sau provenance/commit/license review, secret scan, permission/trigger audit, đổi paths/labels/namespace và PR review.
- SHA-pin third-party GitHub Actions, least privilege, tránh untrusted PR trên self-hosted runner có host access, artifacts private và retention giới hạn.
- OMP upstream được audit là GPL-3.0-only; submodule 2160 Player, VLC, Media3 và dependencies cần inventory/license notices. Repo PRIVATE không miễn nghĩa vụ khi phân phối APK. TorrServer binary không bundle trong APK.

## Evidence and stop conditions

- Test lỗi server offline/auth/no peers, stream/seek/Range, source failure, subtitle malformed/permission, TV pairing và agent confirmation bằng fixture hợp pháp.
- Build/CI PASS không đồng nghĩa TV thật/server thật PASS. Ghi `REAL_TV_UNVERIFIED`, `REAL_SERVER_UNVERIFIED`, `AGENT_E2E_UNVERIFIED` nếu thiếu evidence.
- STOP nếu thiếu license/quyền media, lộ secrets, phải bypass DRM/ToS, cần mở WAN/host service chưa được phép, dùng AIOS infrastructure hoặc phải báo mock như real E2E.

## Deep Research gateway security baseline (PROPOSED; required before enablement)

- **No direct ChatGPT -> TorrServer native MCP:** Gateway provides narrow semantic search/verify/prepare/play/status actions. Do not expose TorrServer admin, raw /mcp, raw tracker credentials, private magnet, shell_exec or arbitrary_http_get. Native TorrServer API and credentials remain LAN-only.
- **Device pairing:** OMP-native integration only after Redmi/firmware gate; short pairing code confirmed in trusted UI, device identity in platform keystore when available, session-scoped short-lived tickets, auth manifest retrieval, token rotation/revocation. Do not put raw magnet or TorrServer Basic Auth into TV session packets.
- **Untrusted data:** release names/indexer descriptions are NOT instructions. Sanitize source IDs, parse only structured metadata, block SSRF against localhost/private metadata/control interfaces, disallow arbitrary redirects, shell and URL execution; cap magnet length and metadata timeouts.
- **Side effects:** add/prepare/play/stop/cleanup require scoped permissions, user confirmation according to action policy, idempotency/replay protection and sanitized audit logs. Indexer admin changes and deletion are privileged operations not available to end-user AI tools.
- **Cloud AI:** explicit local_only / cloud_allowed / cloud_preferred processing policy, rights/consent, cost and retention limits. No silent audio upload; no unauthorized cloning of real actors' voices.
- **Connectivity:** Secure MCP Tunnel claimed in Deep Research is a candidate pending verification of current official docs, account permissions and threat model. Never port-forward TorrServer 8090 or open public inbound gateway as a workaround.
- **Attack tests:** forged device tickets, replayed sessions, indexer prompt injection, SSRF, playlist/stream URL userinfo leaks (including OMP native/VLC), auth failure, missing metadata/peers, cloud consent refusal and failure rollback.

Reference: RESEARCH_ALIGNMENT_2026-10-28.md, proposed ADR-0008. This section does not activate a service or change Windows/TV/network security settings.
