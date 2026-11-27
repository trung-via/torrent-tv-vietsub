# Torrent sidecar English fast path — R2 decision and latency audit

Date: 2026-11-21. Status: **SOURCE_IMPLEMENTED in PR #178 candidate;
not installed on Owner, real TorrServer/Redmi unverified**.
Target: one signed Redmi `Bật Vietsub AI` request -> existing Owner P2
LEAN120 job -> existing authenticated P4 receiver. Keep the parallel film
jobs and durable A→B→A SRT cache in PR #178.

**Human decision (2026-11-21): Do not extract subtitles embedded in MKV.**
This excludes complete locally pinned MKV and stream-only MKV, including
FFprobe/FFmpeg demux, GStreamer `-gst` and HTTP Range/index experiments.
Keep native VI subtitle **presence detection** for playback/translation
avoidance; that is not extracting English subtitle bytes.

## Current source audit

1. `owner_torrserver_ffp_tracks.py` calls TorrServer
   `GET /ffp/<hash>/<file_index>` with a 3-second request deadline. It
   collapses stream metadata to `PRESENT/ABSENT/UNKNOWN` **for Vietnamese
   only**. Its English text tracks are not selected for P2.
2. `owner_p3_p4_private_policy.py::locate_owner_pinned_files` returns `None`
   for the usual empty-media-list, torrent **stream-only** mode. Therefore
   `automatic_vietsub_flow.py` cannot call `find_local_english` in normal
   streamed playback, even if the MKV advertises an English track.
3. `local_en_direct.py` supports an exact same-stem English SRT/VTT sidecar
   on the Owner. The previous `ffprobe`+`ffmpeg` complete-local-MKV EN
   extraction branch is removed. FFmpeg remains only to normalize a `.vtt`
   **sidecar file** into SRT.
4. Without a valid local source, the candidate Owner flow lists external
   VI/EN file companions using `/subs`; falls back to OpenSubtitles `VI_FAST`
   and the existing P2 translator. The installed Owner is unverified.

## Upstream interface distinction (do not confuse the two)

* `GET /subs/{hash}/{id}` in current TorrServer upstream lists subtitle
  **files alongside the video inside the torrent**; a selected track can be
  downloaded with `?track=<index>&format=vtt&encoding=utf8`. This is not
  extraction of a subtitle **track embedded in the MKV**. Upstream states
  the endpoint works in standard builds, but the Owner's installed binary
  version and endpoint response are still unverified.
  [Upstream docs](https://github.com/YouROK/TorrServer/blob/master/server/subs/README.md).
* `/ffp` returns media stream metadata; it does **not** return the full text
  of the embedded subtitle track.
* Any GStreamer `-gst`, FFmpeg full-MKV demux or HTTP Range/index extraction
  of embedded English is explicitly **out of scope**. Matroska subtitle
  blocks can be interleaved with video: source read time is unbounded by
  the subtitle file size. [RFC 9559](https://www.rfc-editor.org/rfc/rfc9559.html).

## Implemented source-admission sequence in candidate code

1. **One trusted media identity:** use the exact signed TV session, Owner
   profile, TorrServer infohash, and selected-file index. Never infer a new
   torrent from subtitle names. A TV close invalidates P4 delivery only;
   Owner's admitted film job continues in the background.
2. **Inspect existing cache first:** reuse completed VI immediately, or
   rehydrate P2's saved latest revisions. Check actual local/embedded VI and
   an exact in-torrent VI sidecar before invoking any translator.
3. **List exact-file companions:** list VI/EN sidecar **files** in the torrent
   through Owner-only `/subs`. Download a unique, validated VI immediately.
   Otherwise probe OpenSubtitles VI (one bounded request); if no confident VI,
   fetch the unique in-torrent EN candidate. This implementation is sequential,
   not a parallel race. `/ffp` remains for VI presence only.
4. **Prefer English supplied with the film over remote English:** a matched
   English `.srt/.ass/.ssa/.vtt` in the torrent via `/subs`, or a validated
   pinned local English `.srt/.vtt` sidecar, is handed to the existing P2 worker
   after normalization to UTF-8 timed SRT. No new AI provider or translator.
5. **Never extract subtitle bytes from MKV:** ignore its English text/image
   tracks as P2 source candidates, irrespective of file completion or
   installed TorrServer binary. Do not probe GStreamer or Range/index paths.
6. **Fallback and commitment:** unavailable/malformed `/subs` listing, no
   unambiguous track, or invalid fetched VTT resumes OpenSubtitles without
   repeating its VI request. The selected asset is SHA-checked and cached
   under the verified film identity before existing P2 batches. Per-film
   reuse prevents a later source from invoking a duplicate translation.

## Time and traffic audit

| Task | Evidence | Budget / practical meaning |
| --- | --- | --- |
| Removed complete-MKV EN extraction | Previous configured `ffprobe` + `ffmpeg` timeouts `20s + 45s` | **Now eliminated**; up to 65s timeout budget no longer occurs in this EN source route |
| Historical synthetic local MKV measurement | `ffprobe` 0.09s; `ffmpeg` 0.08s on a 650,054-byte synthetic file | Historical evidence only; **not** justification to reinstate extraction |
| Current Owner `/ffp` | Source HTTP timeout 3s | Only determines VI track state; may time out on missing peers |
| Candidate torrent sidecar via `/subs` | Owner client limits list to 64 KiB / 2s; selected VTT to 256 KiB / 8s | Source timeout cap per request, **not a measured installed-server SLA**; large tracks fall back |
| Embedded MKV English extraction | **Excluded by Human decision** | No probe, transcode, transfer or translation-source candidate |

The above extraction times **exclude** P2 model latency and P4 publication.
The implemented `/subs` path has a 2s list and 8s per selected-track request
cap; VI-first OpenSubtitles discovery happens **after** the list and before
English sidecar fetch when an English candidate exists. No parallel race is
claimed. The per-track cap is not a whole-flow 10-second guarantee.
There is no embedded MKV extraction SLA because that feature is removed.

## Source implementation and pending live acceptance

- `owner_torrserver_subs.py`: a bounded localhost-only `/subs` reader bound to
  the verified profile/hash/file index. Handles TorrServer's `lang=und` for
  Vietnamese via explicit filename tokens; never follows advertised track URLs.
  Validates WebVTT and normalizes to UTF-8 SRT using existing cue code.
- `p3_owner_state_wiring.py` attaches the reader to the existing
  `AutomaticVietsubFlow`, which preserves VI-first OpenSubtitles discovery,
  EN sidecar priority, per-film cache and P2/P4 handoff. No new worker,
  provider, user toggle or MKV extraction.
- Offline synthetic tests prove fallback for 404/malformed cue, duplicate EN,
  VI sidecar, EN sidecar, cached reopening and no duplicate provider call.
- A read-only Torrent TV HostOps probe on the *installed* Owner should
  report TorrServer version, `/subs` availability, `/ffp` VI state,
  time-to-list, time-to-first-validated-sidecar-EN and bytes transferred.
  Do not log film names, private URLs, subtitle text or credentials.
- Device acceptance: licensed/synthetic fixtures (A) in-torrent EN sidecar,
  (B) pinned local EN sidecar, (C) MKV with only embedded EN and no sidecar.
  (C) **must skip embedded extraction and fall back to OpenSubtitles**.
  Verify saved source, P2 first revision, P4 cue on the actual current TV,
  and no duplicate A after switching A→B→A. Measure median, p95 and input
  bytes; unavailable `/subs` must fall back promptly, never freeze playback.

Evidence status: SOURCE_ONLY + OFFLINE_TESTS only. No Windows HostOps
endpoint, installed TorrServer `/subs` probe, real subtitle download,
Gemini call, APK or Redmi acceptance has run for this candidate.
