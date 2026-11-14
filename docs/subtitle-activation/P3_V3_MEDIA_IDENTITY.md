# P3 V3 — One media identity for OMP, local EN, OpenSubtitles and LEAN120

**Owner decision 2026-11-14:** file/movie identity is the source of **subtitle search** as well as embedded/sidecar subtitle extraction. This candidate composes prior Drafts **#142/#143/#145/#146/#147**, without claiming the live TV subscriber exists or overwriting any of them.

## Authority / status

- Repo PUBLIC main `a946720a39175113dbb149a8e28e4301afaec560` at time of source audit.
- Base Draft #146 `f4ead4a6ceea39a43cfc9d287fd91046eec62887` brings owner-session agent, P3 trigger gate, persistent D2/P2 source cache, deferred Hydrogen API availability and owner-only heartbeat. Earlier #143 owner enrollment was **HUMAN_REPORTED** for a previous pinned candidate, not installation of this V3 branch.
- Source work from #145/#147 is copied unchanged, then **one** `AutomaticVietsubFlow` composed carefully with #146's `source_fingerprint` behavior. Do not copy #145's older flow over #146 or create a second translator/worker/queue.

## Canonical chain

```text
Xiaomi OMP Remote or Redmi direct Play
    → REDMi OMP current accepted PlayRequest: session + selected torrent+file
    → P3-TRIGGER #142 (ON, owner AUTO, authorized content; no pause/seek)
    → owner-private V3 enqueue (video basename + opaque fingerprint + TV session)
    → existing owner-session agent, with *trusted* V3 adapter if configured
    → re-read CURRENT authenticated TV session and TorrServer selected file
    → #147 resolver: id/path/length + optional owner-pinned local video/EN
    → SAME matcher.Media(serverId, torrentHash, fileIndex, filename)
          ↳ #145 LOCAL_EN_DIRECT exact sidecar or complete text embedded track
          ↳ D1 matcher / D2 VI_FAST OpenSubtitles candidate search & release QA
    → existing AutomaticLean120Worker when EN requires translation
    → future D3/P4 exact signed current TV delivery, independently validated
```

The `matcher.Media` object is **shared** as the source identity for D1/D2 matching and local EN. The release's title/year/source/resolution/codec/group and optional SxxEyy/1xEE are *filename-derived search hints*, never authentication of actual video bytes or a perfect sync guarantee. D1 currently requires confident title/year/group/source/resolution/codec match; series lacking reliable year/release metadata must HOLD/REVIEW rather than invent search parameters. For episodes with a known season/episode token, mismatched episode candidates must not be downloaded.

## V3 event and per-film binding

V1 = private filename, V2 = private filename + fingerprint (legacy compatibility). **V3** adds `tv_session_id` so a later A→B→A session does not interpret old events as fresh. Fingerprint = SHA256(`server_id + NUL + lowercase infohash + NUL + fileIndex`) and is not a TV media HMAC. The V3 event itself contains **no torrent infohash, LAN address, subtitle bytes or provider key**, but filename and session remain **private** under owner profile; never send it through GitHub runner ProgramData WAKE.

The V3 processor **re-reads the active trusted TV state and exact TorrServer file**, verifies the same opaque fingerprint, session ID, selected filename, file ID and byte length before selecting a local EN or sending D1/D2 search. It re-reads the current TV state a second time before calling the existing workflow. A changed session/film, OFF/OTHER, already available VI, unsafe/ambiguous file path or wrong source → HOLD. Even this protects only *the check boundary*; a true race could happen after the final read, so D3/P4 must still verify current session immediately before applying subtitles.

Trusted readers must be owner-controlled and independently authenticated. `attested=True` from untrusted JSON is **not** verification. Neither this PR nor V3 supplies a native OMP event subscriber, TorrServer HTTP client, real owner-enrolled credentials, process installer or secure connection. The default CLI owner-agent without a trusted V3 factory **fails V3 events closed**; a host capable of verified session/file reads must inject `VerifiedV3Processor` into the existing polling agent.

## Search route and source priority

1. Real currently-selected VI subtitle track: retain VI and **do not** call provider.
2. Verified EN local SRT/VTT sidecar or complete MKV/MP4 EN text track: D2 private cache → existing P2 Gemini Hydrogen High LEAN120, **0 OpenSubtitles GET/POST**.
3. No owner-readable complete local source: same exact authenticated `matcher.Media` → existing VI_FAST OpenSubtitles then confident EN fallback. Never create a fabricated identity `owner-auto-unverified` for V3. Single POST claim scoped to media fingerprint + release, not filename only.
4. Wrong media, missing or stale session, conflicting sidecar/track, partial metadata or weak release match → REVIEW/HOLD, no charged download or upload.
5. On-screen OFF/OTHER and cancelled/changed TV session are authoritative. No automatic re-enable, WAN opening or GitHub secret sharing.

**Important:** TorrServer `file_stats`/`data.TorrServer.Files` supplies `{id,path,length}`. Its `/ffp/{hash}/{fileIndex}` only exposes probe/track metadata; stream-only media does not mean a complete owner-local source is available. Do not use stream URL as FFmpeg input in this slice.

## CI vs reality

- Target: V3 private envelope, stale-session replay, verified source mapping, same media for D1/D2 and local EN, synthetic FFmpeg sample, zero provider calls when EN local, wrong episode/ambiguous identity fail closed, whole P2 regression.
- **Still NOT_RUN/blocked for live:** a real authenticated Redmi accepted PlayRequest subscriber, read-only Windows TorrServer file reader in owner process, owner pinned path service, one-time interactive V3 enrollment, real Gemini/API, real P4 signed no-picker TV subtitle, and independent TV cue 131 acceptance.
- Owner previously **HUMAN_REPORTED** Mobile Companion M0–M3 PASS and older #143 agent enrollment; that evidence does not certify this new V3 candidate.
- Repo public: no real titles/trackers, private video/subtitles, user path, server address, API keys or paired TV code in commits or CI logs.

**Review/merge:** Draft/HOLD until exact HEAD CI, independent Issue #42 Brain review and applicable real device acceptance. No runner Session0 privileges or silent TV/Windows install.
