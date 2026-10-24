# Architecture v2.1 — OMP-based client + dedicated project runner

**DECIDED_PRODUCT_DIRECTION:** Human chọn OMP (ADR-0002, 2026-10-25).  
**UNVERIFIED_IMPLEMENTATION:** chưa import/build mã OMP, chưa chạy APK/TV/TorrServer thật.

```text
[Người dùng] 
  |-- thêm magnet/.torrent thủ công qua OMP UI hoặc TorrServer Web UI
  |-- tìm kiếm theo yêu cầu: OMP website source adapters / configured Jackett/Prowlarr/TorrServer
  |                                     (chỉ nội dung/nguồn được phép)
  v
[OMP TypeScript/Preact TV + phone UI, Capacitor/WebView]
  |-- Library, series, history, watch progress, D-pad/phone remote
  |-- src/api/torrserver.ts (LAN client)
  |-- src/player/nativePlayer.ts -> native bridge
  v
[Windows default / NAS optional TorrServer] ------ trusted LAN HTTP media -------+
  | metadata, pieces/cache, API /echo /torrents /stream                         |
  | server ON while viewing                                                    v
                                      [Android PlayerActivity / PlayerSession]
                                        -> Engine2160 (2160 Player + Media3)
                                        -> VlcEngine fallback (ASS/SSA/errors)
                                        -> audio/subtitle selection, SRT/VTT
```

## Development execution boundary (`DECIDED` / `UNVERIFIED`)

```text
AIOS-renew canonical governance (authoring/admission — only if authenticated)
                      |  dispatch bridge: UNVERIFIED
                      v
Torrent TV Vietsub's OWN dedicated runner (registration/online: UNVERIFIED)
                      |
                      v
Torrent TV Vietsub's OWN isolated Git workspace
                      |
                      +-- OMP source/build/test/APK evidence
                      +-- Git remote: trung-via/torrent-tv-vietsub (PRIVATE)

AIOS-renew runner / Runtime checkout / .git/aios journals: NOT A FALLBACK
```

Repo/workspace/runner riêng là quyết định Human, không phải bằng chứng máy runner đã cài/online. Không giả định chung máy vật lý hoặc riêng máy vật lý khi chưa có xác nhận; yêu cầu là tách runner identity, working directory, quyền và dữ liệu Runtime. Không tự bật workflow, cài runner/service, nạp secrets, mở firewall hoặc dùng runner `AIOS-renew` để lách admission.

## Boundaries (`DECIDED`)

- UI giữ Preact/TypeScript; Android playback dùng Kotlin, Media3/2160 Player và VLC. **Không có yêu cầu rewrite sang Compose** ở P0.
- Website source adapters `src/sources/*` được giữ và có thể tìm theo yêu cầu người dùng; không xóa/tắt vì audit; không vận hành index phim lậu hoặc crawler vi phạm quyền, không bypass login/captcha/DRM.
- TorrServer riêng trên Windows/NAS; không vendor binary hay BitTorrent engine trong APK. Existing OMP phone-local TorrServer không cần thiết trong đường chuẩn.
- Việc giữ OMP phone UI/remote không đồng nghĩa phải viết companion app mới. Billing/backends/bot/monitor nền/autostart upstream được audit và cô lập khỏi MVP **sau** kiểm chứng dependency.
- Chưa chốt commit production, dependency lock hoặc stream wire contract. Audit snapshot OMP: `52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`; clone + submodule `android/vendor/2160player` phải pin riêng khi feasibility.

## Vietnamese seams

- `src/i18n/{ru,en,index}.ts` + Android native `I18n.kt` hiện phục vụ ru/en: mở rộng từ điển `vi`, giữ placeholders/plural/format và test.
- `src/lib/tracks.ts`, `DubMatch.kt`, `trackPrefs.ts`, `src/store/settings.ts`: nhận diện `vi/vie/vietnamese`, ưu tiên Việt khi track có thật, nhớ lựa chọn, fallback rõ.
- `src/lib/episodes.ts`, `src/player/queue.ts`, `Engine2160.kt` và `VlcEngine.kt`: sidecar `.srt/.vtt` Unicode; ASS/SSA qua VLC nếu phù hợp; PGS và typesetting phải kiểm tra thực tế.
- **P2/AI:** Windows/NAS ASR/dịch/QA/TTS/căn thời gian; thực nghiệm mux hoặc external-audio synchronization trước khi coi là supported. Không thêm AI agent/backend vào TV APK.

## Security gates

- `src/api/torrserver.ts` có `videoSrc()` đưa userinfo vào URL; Android native/VLC có đường nhận URL này. Không phát hành khi chưa audit log/redirect/trace/backup và phương án hạn chế lộ credentials.
- Search websites có điều khoản truy cập và tài khoản khác nhau. Chỉ gọi nguồn bằng hành động chủ động, che secret/passkey; không tự crawl trong nền.
- LAN trusted. Không tự mở WAN/UPnP/router/Windows service/firewall/autostart. Check manifest quyền/receivers sau khi cô lập module.

## Device/server gates

- Ghi model/firmware/API/ABI thật; Redmi nội địa không mặc định giống Xiaomi Google TV.
- Nếu không hỗ trợ APK: `DEVICE_BLOCKED`, hỏi Human về TV box; không root/circumvent.
- Thử media hợp pháp qua TorrServer Windows thật, seek/HTTP Range, media codec/audio, Vietsub/remote. Mock không chứng minh `REAL_TV_PASS` hay `REAL_SERVER_PASS`.
