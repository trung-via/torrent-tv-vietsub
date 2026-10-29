# TV compatibility gate — UNVERIFIED

Collect: manufacturer, exact model, region and OS/build (Settings > About); Android API, ABI; sideload/ADB permission; D-pad/Back behavior; supported containers/video/audio codecs/HDR; 4K playback behavior; whether TV and Windows/NAS are on same LAN.

Device test result vocabulary: `REAL_TV_PASS`, `REAL_TV_FAIL`, `REAL_TV_UNVERIFIED`, `DEVICE_BLOCKED`. Emulator PASS is reported as `EMULATOR_PASS` separately. Do not replace unknown actual hardware facts with online specifications of similarly named TV.

## Research reconciliation — native capability inside OMP

The report recommends a new native Kotlin/Media3 TV app. **This is superseded by Human OMP-first choice**: test and adapt the existing OMP Preact/Capacitor app with its 2160/Media3/VLC native playback components, not a new Compose client.

For the **actual Redmi A Pro 55 China/HyperOS unit**, capture model/build/API/ABI, sideload/ADB conditions, codec support (H.264/HEVC Main10/AV1/HDR, AAC, Dolby/DTS if relevant), audio-language tracks, D-pad/Back, network path and bitrate peaks. Verify Google Cast/Cast Connect capability rather than extrapolate from a Xiaomi Google TV variant.

Development-only ADB deep link may be used with permission as a test probe, not production control. Pairing/session token/WSS/manifest and OMP native track selector require dedicated feasibility and security checks. Cast Connect optional if available; DLNA fallback only if session control/audio limitations are acceptable.

Evidence: exact TV/firmware, fixture license, player build SHA, first frame, pause/seek/resume, Vietnamese track, external SRT G0–G4, LAN command time, buffering/recovery. Documentation is not REAL_TV_PASS.
