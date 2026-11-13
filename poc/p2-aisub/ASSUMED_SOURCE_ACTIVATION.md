# P2 -> P4 assumed English subtitle input (2026-11-12)

HUMAN DECISION: Brain subtitle discovery is deferred. Assume a correctly
matched English timed SRT/VTT for the currently playing film has already
been supplied to the PC. This is a TEST PRECONDITION, not evidence that a
finder exists or verified language, dialogue or timing against the video.

## Source contract

1. External workflow supplies OMP's opaque media.<64hex> identity, original
   English SRT/VTT bytes and format.
2. assumed_source_handoff.py validates UTF-8, cue IDs/timecodes and SHA256,
   status ASSUMED_MATCHED_EN_TIMED_TEXT. No finder, ASR or movie comparison.
3. The PC maps that opaque media key to the already supplied source. An
   unknown movie is a SOURCE_MISSING error, not invented subtitles.
4. One-time TV-PC pairing uses a strong random device master secret,
   kept in AndroidKeyStore-encrypted app-private storage. For each film the
   TV signs an activation request using the paired key and random nonce.
   PC validates and rejects wrong film, tampering and replay, then returns
   a signed fresh session ID and source SHA256.
5. Both sides derive the same per-film key from the paired master, session,
   media key and source SHA. TV reads that session's cumulative signed feed
   with a unique HMAC-authenticated GET nonce.
6. Explicit PC worker may call configured LEAN120 Gemini API (temporary
   gemini-3.8-flash, medium; profile replaceable), publishing cumulative
   120->240->... SRT/VTT after each validated batch.
7. TV verifies session/film/source/sha/HMAC/version, user ON and VLC;
   native G1 app-private file import and G2 first-frame ACK remain distinct.

## Executable code (no automatic service startup)

- assumed_source_handoff.py: typed source and preflight.
- paired_activation.py: signed PC activation, key derivation, bounded film
  session registry and replay protection.
- lan_revision_feed.py: signed immutable cumulative feed; GET reader HMAC
  with fresh nonce and bounded replay ledger, RFC1918-only bind.
- run_assumed_source_gateway.py: explicit opt-in Windows PC prototype.
  A real listener requires --start-lan; a live provider additionally
  requires --execute-api, GEMINI_API_KEY in local environment and an
  explicit supplied source file. Master key stays in P4_PAIRING_MASTER_HEX.
- P4 PR #120 separately owns Android Keystore, one-time developer-stage
  host:port|64hex key provisioning, native D-pad Bật/Tắt Vietsub AI,
  per-film activation and polling.

No live server, API call, ADB install, TV/Windows service/firewall/router
change or subtitle cloud upload was performed in authoring/CI.

## Security and acceptance boundary

HMAC authenticates version/reader, not subtitle confidentiality. Current
HTTP LAN prototype is cleartext: it must be restricted to private trusted
LAN with synthetic fixtures for debug. A production feature needs verified
encrypted transport and more convenient companion-phone/QR pairing.
Do not expose TorrServer admin/MCP to the TV subtitling client or WAN.
The host must already know the exact film media key and source bytes:
future Brain discovery can replace only this upstream input, without
changing LEAN120 or the G1/G2 TV contract.

Offline tests cannot certify real Gemini translation quality, source/movie
match, actual PC-TV LAN exchange, Redmi no-picker behavior or G4 release.
