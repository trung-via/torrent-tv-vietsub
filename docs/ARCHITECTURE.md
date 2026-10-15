# Architecture v1 — DECIDED client/server, API details UNVERIFIED

```text
Phone / PC user input (magnet/.torrent from content with access rights)
          |
          v
TorrServer web UI/API on Windows default, NAS optional
  - peer discovery + piece/cache management
  - expose HTTP video stream
          | trusted home LAN
          v
Android TV app (if device firmware supports APK)
  server setup & connectivity
  StreamEngine interface -> TorrServerAdapter -> typed failures
  Media3 ExoPlayer -> track selectors -> subtitle renderer
  remote/D-pad focus and Back navigation
```

## Strict seams

- `StreamEngine` returns normalized video file descriptors + playable stream handles + typed failures, never internal TorrServer schema to UI.
- Adapter uses configurable endpoint, timeout, cancellation and authentication handling. Wire routes (`/echo`, `/torrents`, `/stream`, `/play`) are **candidates only**, NOT contractual until real version probe and fixtures.
- Video streams should support seek/HTTP Range where real upstream supports it. Probe with fixture before PASS.
- Embedded Vietsub or sidecar UTF-8 SRT/VTT; image-based subs and complex ASS require future viability tests.
- Transcode/remux only if native playback is insufficient AND the server has measured capacity.

## Hardware compatibility

Redmi A Pro 55 (China HyperOS) and Xiaomi TV A Pro 55 2026 (global Google TV) may differ. Gather exact `Settings > About` model/build, API/ABI, ADB/install permission, codec/remote behavior. Fallback to dedicated Google TV / Android TV box with Human approval; do not root TV.
