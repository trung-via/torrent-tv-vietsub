# P3: owner-local TorrServer exact file metadata, read only

2026-11-14 · independent Draft source for [Issue #149](https://github.com/trung-via/torrent-tv-vietsub/issues/149), child of [#152](https://github.com/trung-via/torrent-tv-vietsub/pull/152) (P3/P4 single paired HTTPS handler) and ultimately [#148](https://github.com/trung-via/torrent-tv-vietsub/pull/148) V3 media identity.

## Real OMP source anchor

`spacesarmat/omp@52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f`:
`src/api/torrserver.ts` `TorrServerClient.get(hash)` sends `POST /torrents` JSON `{"action":"get","hash":hash}`. Its `files()` prefers `torrent.file_stats`, falling back to JSON `torrent.data.TorrServer.Files`. Each `TorrentFile` contains `id, path, length`.

`owner_torrserver_readonly.py` implements only that **single metadata request**, no `add`, `rem`, `stream`, `loadInfo`, tracker, torrent playback, ffprobe or contents download. It is a **callable injected into #148 VerifiedV3Processor as read_verified_torrserver_file**, not a new worker/service. It is constructed only with a **preconfigured local owner profile ID and localhost port**, no server URL from TV or public payload. Requests use only `127.0.0.1` (TorrServer on the SAME Windows laptop), never an RFC1918 remote host, proxy, redirect, DNS, WAN or credentials embedded in URLs.

## Binding

The incoming paired TV P3 signed envelope contains only `tv_session_id + torrent_hash + fileIndex`. It does **not** carry a source filename or trusted server URL. A verified owner current-TV reader must provide the *pre-paired* server profile and the actual viewer ON/OFF/OTHER state. Only then may this read-only localhost adapter request TorrServer metadata.

It compares explicit owner profile, 40/64 lowercase infohash, a nonnegative fileIndex, exact `response.hash`, unique `file_stats.id` and positive `length`, bounded UTF-8 JSON max 512 KiB/4096 files; returns `TorrServerSelectedFile(id,path,length)`. The downstream #147 resolver separately checks path safety, basename==selected video, locally complete movie size and trusted owner-pinned source. **Metadata path is not a claim of real file existence**.

When no readable local EN exists, #148 uses the SAME canonical `matcher.Media(profile,hash,fileIndex,verified_filename)` for D1/D2 OpenSubtitles candidate search; English timed subtitles then use existing LEAN120. No alternate media identity is fabricated from OMP UI title.

## Correct P4 native media-key reconciliation

The existing G1/P4 Kotlin `P1ProductionSubtitles.mediaKey` is **not** the V3 trigger fingerprint. Exact algorithm in `poc/g1-prod/P1ProductionSubtitles.kt`:

`media.` + SHA256(`"prod" + NUL + server_profile_id + NUL + lower(infohash) + NUL + fileIndex`).

The P3 `source_fingerprint` omits the `"prod" + NUL` prefix and is scoped only for triggering/caching; treating it as P4 key would send subtitles to a different identity and P4 would refuse them. `p3_p4_media_key.py` derives the **correct existing native key** from the same exact `matcher.Media` (VLC, valid owner profile, 40-hex torrent hash and file index). Fixed synthetic hash vector and G1 source-anchored test ensure this cannot silently diverge. P4 key derivation does **not** enable automatic import/ON or prove the TV is still playing; D3/P4 must separately validate current session, consent, media and signed payload.

## Evidence and boundaries

Offline tests cover exact POST only with capture transport, invalid hash/profile/index, duplicate file id, metadata hash mismatch, failed/redirect response, and a REAL TCP HTTP loopback on 127.0.0.1 with synthetic media names (no real server contacted). Not proof of real TorrServer Windows credentials/port/state, not proof TV active session and not a real D1/D2 query.

Before running on owner's laptop: record exact TorrServer version/port/auth and ensure the locally installed server supports this GET action shape. Require separate physical current TV reader and owner P3 consent / P4 pairing; do not read API key, change Windows firewall, install Task Scheduler service or open an external LAN endpoint under this PR. Reject ambiguous server profiles and private multimedia path leaks.

**Draft/HOLD** until CI and independent Issue #42 Brain review. No media file, torrent hash, LAN address, credentials or subtitle bytes may be committed to the PUBLIC repository.
