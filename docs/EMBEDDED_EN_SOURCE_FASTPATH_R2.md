# Torrent-contained English subtitle fast path — R2 design and latency audit

Date: 2026-11-21. Status: **DESIGN_ONLY, NOT IMPLEMENTED OR DEPLOYED**.
Target: one signed Redmi `Bật Vietsub AI` request -> existing Owner P2
LEAN120 job -> existing authenticated P4 receiver. Keep the parallel film
jobs and durable A→B→A SRT cache in PR #178.

## Current source audit

1. `owner_torrserver_ffp_tracks.py` calls TorrServer
   `GET /ffp/<hash>/<file_index>` with a 3-second request deadline. It
   collapses stream metadata to `PRESENT/ABSENT/UNKNOWN` **for Vietnamese
   only**. Its English text tracks are not selected for P2.
2. `owner_p3_p4_private_policy.py::locate_owner_pinned_files` returns `None`
   for the usual empty-media-list, torrent **stream-only** mode. Therefore
   `automatic_vietsub_flow.py` cannot call `find_local_english` in normal
   streamed playback, even if the MKV advertises an English track.
3. Existing `local_en_direct.py` supports an exact same-stem English SRT/VTT
   sidecar or `ffprobe`+`ffmpeg` text-track extraction **only from a complete,
   owner-pinned local video file**. The configured local deadlines are 20s
   (`ffprobe`) and 45s (`ffmpeg`); source is validated and cached as SRT.
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
* Only optional **GStreamer (`-gst`) builds** offer embedded text subtitle
  output as segmented WebVTT under `/gst/:hash/subs/:track.m3u8` and
  `/gst/:hash/subs/:track/:segment.vtt`. Standard builds do not provide it.
  [Upstream README](https://github.com/YouROK/TorrServer#readme).
* A plain FFmpeg demux over a multi-gigabyte MKV HTTP stream cannot be
  assumed to fetch only subtitle bytes: Matroska subtitle blocks occupy
  interleaved clusters. A `-map 0:<subtitle-stream>` command selects only
  the output, not necessarily which source bytes must be fetched.
  [RFC 9559](https://www.rfc-editor.org/rfc/rfc9559.html).

## Proposed source-admission sequence

1. **One trusted media identity:** use the exact signed TV session, Owner
   profile, TorrServer infohash, and selected-file index. Never infer a new
   torrent from subtitle names. A TV close invalidates P4 delivery only;
   Owner's admitted film job continues in the background.
2. **Inspect existing cache first:** reuse completed VI immediately, or
   rehydrate P2's saved latest revisions. Check actual local/embedded VI and
   an exact in-torrent VI sidecar before invoking any translator.
3. **Run a short candidate race:** in parallel, use the existing /ffp result
   to identify English text streams; query `/subs` for VI/EN sidecar files;
   and perform existing confidence-gated OpenSubtitles VI discovery. Choose
   a validated VI if available before committing a translation job.
4. **Prefer English supplied with the film over remote English:** a matched
   English `.srt/.ass/.ssa/.vtt` in the torrent via `/subs`, or a validated
   pinned local EN/embedded text stream, is handed to the existing P2 worker
   after normalization to UTF-8 timed SRT. No new AI provider or translator.
5. **Embedded text inside a stream-only MKV:** if the verified Owner already
   runs a compatible `-gst` text WebVTT feed, it may collect validated cues
   from the **same** selected media. Never launch a speculative HLS
   transcode just for subtitles. On a standard binary, perform an isolated
   bounded Range/index feasibility probe **before** proposing an optimized
   sparse extractor. Do not run unbounded whole-MKV FFmpeg demux on the
   foreground path. Image subtitles (PGS/VobSub) are not text sources.
6. **Fallback and commitment:** when no in-torrent/local English text source
   completes within the short budget, use the current OpenSubtitles
   VI-first/EN fallback. Freeze one selected source and its SHA before the
   first paid P2 batch; a later local result may not cause a duplicate job.
   Store source kind, track index and validation receipt privately per film.

## Time and traffic audit

| Task | Evidence | Budget / practical meaning |
| --- | --- | --- |
| Local synthetic MKV stream metadata | `ffprobe` 0.09s on 650,054-byte, 40-second fixture / 12 cues (Linux scratch) | CPU lower-bound only, **not Windows/TorrServer proof** |
| Local synthetic MKV English SRT extraction | `ffmpeg` 0.08s on same fixture | Exact 12 cues recovered; one newline differs |
| Existing Owner pinned complete video | Source timeouts `20s + 45s` | Up to 65s before translation; real large-file time unmeasured |
| Current Owner `/ffp` | Source HTTP timeout 3s | Only determines VI track state; may time out on missing peers |
| Proposed torrent `.srt` via `/subs` | Upstream supports companion files up to 2 MiB | Target 2s list + 8s fetch maximum, not an observed SLA |
| Proposed same-film embedded MKV through stream | **No direct full-text endpoint in standard upstream API** | No truthful fixed estimate; an FFmpeg pass may need data across the film |
| If full 4 GB stream must be read | Arithmetic at ideal steady 20/50/100 Mbit/s | About 27 / 11 / 5.3 minutes, before peer stalls |

The above extraction times **exclude** P2 model latency and P4 publication.
The proposed fast path has a 10-second source admission ceiling for the
in-torrent candidate (with OpenSubtitles running concurrently), not a
guarantee that all embedded English subtitles can be obtained in 10s.

## Smallest implementation and acceptance

- Extend `owner_torrserver_ffp_tracks.py` with a typed VI/EN stream inventory,
  keeping the current VI-state policy unchanged. Add an Owner-only `/subs`
  list/selected-file client to `owner_torrserver_readonly.py` (or adjacent
  module), strictly bound to the selected file. Map returned `lang`, `index`,
  `format`, never trust a returned absolute URL.
- Add a source-selector boundary in `automatic_vietsub_flow.py`: valid VI,
  exact in-torrent/local English, then OpenSubtitles fallback. Reuse
  `local_en_direct.py` conversion/QA and P2 per-film caches. Track source
  choice and elapsed times, no extra translation worker or new TV toggle.
- A read-only Torrent TV HostOps probe on the *installed* Owner should
  report TorrServer version, `/subs` availability, `/ffp` VI+EN count, text
  codec, time-to-list, time-to-first-validated-EN and bytes transferred.
  Do not log film names, private URLs, subtitle text or credentials.
- Device acceptance: three licensed/synthetic fixtures: (A) in-torrent EN
  sidecar, (B) complete pinned MKV embedded English, (C) stream-only MKV
  embedded English on the actual installed TorrServer. Verify each exact
  fallback, saved source, P2 first revision, P4 cue on the actual current TV,
  and no duplicate A after switching A→B→A. Measure median, p95, input bytes
  and number of HTTP Range requests. Unavailable binary capability must
  fallback promptly, never freeze playback.

Evidence status: SOURCE_AUDIT + LOCAL_SYNTHETIC_BENCH only. No Windows
HostOps endpoint, real TorrServer media probe, provider call, APK or Redmi
acceptance was executed for this design.
