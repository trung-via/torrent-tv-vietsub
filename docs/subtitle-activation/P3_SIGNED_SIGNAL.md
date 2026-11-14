# P3 Selected Playback: signed TV → owner Windows source contract

**2026-11-14 · SOURCE_ONLY · NOT_INSTALLED.** Related [Issue #149](https://github.com/trung-via/torrent-tv-vietsub/issues/149); parent [Draft #148](https://github.com/trung-via/torrent-tv-vietsub/pull/148) V3 exact selected-file identity; P4 pairing concepts [Draft #120](https://github.com/trung-via/torrent-tv-vietsub/pull/120) and reliability [#137](https://github.com/trung-via/torrent-tv-vietsub/pull/137).

## Why the signed event contains no movie name

OMP pinned source `spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`: `PlayerActivity.load` accepts `PlayRequest`, `playItem` advances selected file, `emitClosed` closes/replaces. `QueueItem.hash` + `fileIndex` are selected torrent coordinates. `QueueItem.title` is **display heading, not authoritative TorrServer filename**. `PlayRequest.session: Long?` is a web-view run token; the page increments a local counter which can reset, so it must not be the standalone P3 session identity.

A verified TV producer will mint **random 128-bit tv_session_id** per selected file (not the web-view counter). It sends just the exact selected file coordinates; owner Windows resolves filename and search release hints by an independently authenticated read-only TorrServer `/torrents get` in the configured owner's server profile. The same resulting `Media(server, hash, fileIndex, filename)` is passed to local EN and D1/D2 OpenSubtitles. No title guessed from UI, movie bytes, subtitle text or API keys cross the TV event transport.

## Fixed signed wire (source candidate)

**Proposed endpoint only:** `POST /p3/selection` on existing owner-approved **P4 certificate-pinned LAN HTTPS** server. This PR **does not create/register or bind that endpoint**. The P4 pairing secret would be re-used with an **independent domain-separated HMAC** string so the event cannot authorize P4 revision/activation.

```json
{
  "schema":"TTV-P3-TV-SELECTION-V1",
  "kind":"PLAY_REQUEST_ACCEPTED",
  "tv_session_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "torrent_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "file_index":7,
  "sent_at_ms":1800000000000,
  "nonce":"cccccccccccccccccccccccccccccccc",
  "signature":"c554546c5d9e78424f5fa3d17c31589652d4e9139fa93125a7a9ab76989e6964"
}
```

Synthetic example only: key = bytes 0..31, HMAC of exact ASCII
`TTV-P3-TV-SELECTION-V1\nPLAY_REQUEST_ACCEPTED\n<session>\n<hash>\n7\n1800000000000\n<nonce>`.
No production key/version printed. Valid kinds are `PLAY_REQUEST_ACCEPTED`, `NEXT_QUEUE_ITEM_ACCEPTED` and `PLAYBACK_CLOSED` (which must **not** start provider work). JSON keys strict, wire max 1024 bytes, HMAC SHA256, 15-second clock skew, in-process nonce replay/window; any signed event **still needs** a fresh verified current TV state and exact server/file read. Reverse proxy must not expose route to WAN, and no raw TorrServer MCP/admin actions.

## Endpoint/owner trust requirements not supplied here

`p3_signed_playback_signal.py` verifies only **paired TV device origin** and freshness. This is insufficient to assert the user still watches that file. `p3_signed_signal_to_owner.py` therefore requires a trusted local source that re-reads the currently accepted TV selection, P4 per-media ON/OFF/OTHER state, and selected TorrServer file. It compares the current hash/index/session before calling the existing `TrustedPlaybackToOwner` policy and V3 event inbox. Owner's configured server profile **cannot come from the JSON**. The downstream #148 processor independently checks `Media`, filename, TV session and selected file again before D1/D2 or local EN.

The verified request does **not** call Gemini/OpenSubtitles or open Windows sockets; the trusted endpoint handler and real TV status source are **not implemented**. In-process replay guard is not a durable replay journal across owner-agent restarts; V3 provider claims and P4 session binding are independent, mandatory layers. A production ingress should add restart-proof replay/sequence storage and a bounded private HTTPS route before claiming full security acceptance.

**Explicit P3 event enablement** on TV should default OFF, require already provisioned P4 pairing, and be a distinct owner action from manually pairing the Xiaomi OMP remote. Transport is optional; a failure never interrupts normal movie playback. No DNS/WAN, HTTP URL, log of hash/IP/movie or insecure cert bypass.

## Acceptance
- Source tests: HMAC synthetic pinned vector, replay/tamper, expiry, exact current TV comparison, V3 private enqueue, no provider/window listener; hosted CI only.
- Future real TV/Windows: one legally owned test file, P4 paired PC/private TLS cert pin, real signed native `load` and `playItem` and `close`, PC read-only TorrServer metadata, recheck viewer ON, stop on OFF, no Seek/Pause/Resume trigger, A→B→A and stale event.
- Separate real OpenSubtitles/Gemini and P4 subtitle no-picker cue 131 acceptance, not inferred from source CI.
