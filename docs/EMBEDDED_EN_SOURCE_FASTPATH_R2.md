# Torrent sidecar English fast path — R2 decision and latency audit

Date: 2026-11-21. Status: **MKV EN extraction removed in PR #178;
torrent `/subs` sidecar fast path DESIGN_ONLY, NOT IMPLEMENTED OR DEPLOYED**.
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
4. Without a valid local source, current owner flow uses OpenSubtitles
   `VI_FAST`, then confidence-gated English -> existing P2 translator.

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

## Proposed source-admission sequence

1. **One trusted media identity:** use the exact signed TV session, Owner
   profile, TorrServer infohash, and selected-file index. Never infer a new
   torrent from subtitle names. A TV close invalidates P4 delivery only;
   Owner's admitted film job continues in the background.
2. **Inspect existing cache first:** reuse completed VI immediately, or
   rehydrate P2's saved latest revisions. Check actual local/embedded VI and
   an exact in-torrent VI sidecar before invoking any translator.
3. **Run a short candidate race:** in parallel, query `/subs` for external
   VI/EN sidecar **files** in the torrent and perform existing confidence-gated
   OpenSubtitles VI discovery. `/ffp` remains for VI presence only. Choose
   a validated VI if available before committing a translation job.
4. **Prefer English supplied with the film over remote English:** a matched
   English `.srt/.ass/.ssa/.vtt` in the torrent via `/subs`, or a validated
   pinned local English `.srt/.vtt` sidecar, is handed to the existing P2 worker
   after normalization to UTF-8 timed SRT. No new AI provider or translator.
5. **Never extract subtitle bytes from MKV:** ignore its English text/image
   tracks as P2 source candidates, irrespective of file completion or
   installed TorrServer binary. Do not probe GStreamer or Range/index paths.
6. **Fallback and commitment:** when no in-torrent/local sidecar text source
   completes within the short budget, use the current OpenSubtitles
   VI-first/EN fallback. Freeze one selected source and its SHA before the
   first paid P2 batch; a later local result may not cause a duplicate job.
   Store source kind, track index and validation receipt privately per film.

## Time and traffic audit

| Task | Evidence | Budget / practical meaning |
| --- | --- | --- |
| Removed complete-MKV EN extraction | Previous configured `ffprobe` + `ffmpeg` timeouts `20s + 45s` | **Now eliminated**; up to 65s timeout budget no longer occurs in this EN source route |
| Historical synthetic local MKV measurement | `ffprobe` 0.09s; `ffmpeg` 0.08s on a 650,054-byte synthetic file | Historical evidence only; **not** justification to reinstate extraction |
| Current Owner `/ffp` | Source HTTP timeout 3s | Only determines VI track state; may time out on missing peers |
| Proposed torrent `.srt` via `/subs` | Upstream supports companion files up to 2 MiB | Target 2s list + 8s fetch maximum, not an observed SLA |
| Embedded MKV English extraction | **Excluded by Human decision** | No probe, transcode, transfer or translation-source candidate |

The above extraction times **exclude** P2 model latency and P4 publication.
The proposed fast path has a 10-second source admission ceiling for
**external subtitle files in the torrent**, with OpenSubtitles in parallel.
There is no embedded MKV extraction SLA because that feature is removed.

## Smallest implementation and acceptance

- Keep `owner_torrserver_ffp_tracks.py` unchanged for VI presence. Add an Owner-only `/subs`
  list/selected-file client to `owner_torrserver_readonly.py` (or adjacent
  module), strictly bound to the selected file. Map returned `lang`, `index`,
  `format`, never trust a returned absolute URL.
- Add a source-selector boundary in `automatic_vietsub_flow.py`: valid VI,
  exact in-torrent/local English, then OpenSubtitles fallback. Reuse
  `local_en_direct.py` conversion/QA and P2 per-film caches. Track source
  choice and elapsed times, no extra translation worker or new TV toggle.
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

Evidence status: SOURCE_AUDIT + LOCAL_SYNTHETIC_BENCH only. No Windows
HostOps endpoint, real TorrServer media probe, provider call, APK or Redmi
acceptance was executed for this design.
