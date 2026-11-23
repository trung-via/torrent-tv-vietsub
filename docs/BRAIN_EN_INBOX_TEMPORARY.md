# Temporary Brain EN inbox → existing AGY Vietsub (2026-11-23)

Status: **SOURCE CANDIDATE ONLY — not installed on Windows Owner or accepted on Redmi**.
Human decision: use a Brain-prepared matching English OpenSubtitles SRT. The TV tap
must never launch an OpenSubtitles search/download or a second source fallback.

## One temporary path

1. Human adds an authorized film/episode to the **existing TorrServer Library**.
2. Human supplies the film / exact release and an OpenSubtitles.org page or asks
   Brain to find the right English subtitle. Brain may retrieve a permitted SRT,
   verify the title, season/episode, release and timeline, then arrange an
   **Owner-private** handoff. No CAPTCHA/login bypass or invented SRT.
3. The currently authenticated Owner/TorrServer metadata provides
   `server_profile_id + torrent_hash + file_index + exact video_name`. The
   existing P3 fingerprint is SHA256 of those first three fields joined by NUL.
   A filename or film title alone **cannot** establish this binding. Never
   place the raw identifiers, SRT contents, user login or private local paths
   in the PUBLIC repo, Issue #82, PR text or CI logs.
4. The SRT is staged in the **existing Owner cache root**, under
   `<Owner cache_root>/.brain-en-inbox/<source_fingerprint>/english.srt` with a
   bounded `receipt.json` beside it. This must happen **before** TV tap.
   The staging tool only accepts a real local SRT file; it does not make a
   network request, upload to GitHub or infer the TorrServer media identity.
5. On Redmi `Bật Vietsub AI`, the original signed P3 selection verifies
   the current film and session. Owner reads the exact staged English SRT,
   checks source page, release/year/group, SHA256, cue count and timestamps,
   then invokes the **existing** Antigravity CLI LEAN120 worker in
   50/120-cue windows and **existing** P4/G2 revision delivery. No added
   translator, queue, receiver, APK or GStreamer.
6. Missing staged SRT → `REVIEW_REQUIRED` /
   `AUTO_EN_SOURCE=BRAIN_EN_NOT_STAGED`, **zero OpenSubtitles API calls and
   zero AGY translation calls**. A stale legacy AI cache with no staged EN
   cannot override it. A mismatched staged source/cache stops with a reason;
   no automatic deletion/retry.

## Staging command (Windows Owner context after file transfer)

Once the reviewed code is installed, run in the **Owner's own Windows account**
and only with values read from the verified current TorrServer record:

```powershell
python .\poc\p2-sub-discovery\brain_english_inbox.py `
  --cache-root "<actual private Owner cache_root>" `
  --source-fingerprint "<exact Owner P3 fingerprint>" `
  --video-name "<exact selected TorrServer video filename>" `
  --release-name "<actual matching OpenSubtitles release name>" `
  --source-page "https://www.opensubtitles.org/en/subtitles/<actual-id>/<actual-slug>" `
  --srt "<existing local downloaded English SRT absolute path>"
```

A successful stage prints `BRAIN_EN_STAGE=READY_EXACT_MEDIA`. Re-running with
identical contents is idempotent; replacing a different staged SRT refuses
`BRAIN_EN_STAGE_CONFLICT` rather than overwriting translation state.

**Important current transfer limitation:** The ChatGPT sandbox is not the
Windows Owner's filesystem. GitHub PUBLIC Issue/PR text and CI artifacts
are not acceptable storage for a private subtitle. This source patch
implements the **Owner-side import/consume** but not an authenticated
Brain-to-laptop binary upload channel. For a direct SRT URL, a separately
verified HostOps staging job may download it into this private inbox when
the URL truly returns an SRT and Owner identity is known. Otherwise the
user must save the Brain-provided SRT locally and invoke the stage command.
Do not claim the end-to-end transfer is automated until a real receipt exists.

## Acceptance / rollback

- Offline: staged, wrong-media, wrong-release, corrupted SRT, duplicate/conflict,
  missing file, and source→LEAN120 cache tests.
- Windows: observed installed source SHA / loaded PID; trusted exact P3
  fingerprint and private receipt; validate staged SRT without any GET/POST.
- AGY: one real EN→VI first-50 cue checkpoint and subsequent 120-cue revisions;
  dedupe A→B→A, preserve old checkpoints / unknown-effect state.
- TV: P4 signed revision ACK, first visible Unicode Vietnamese cue on current
  Redmi film, keep playback and test switching films. No API result or unit test
  alone equals real-TV success.
- Rollback: restore the last known-good Owner source/manifest and restart
  **only after** reconciling in-flight jobs; preserve the staged inbox,
  existing translations and all receipts. This candidate does not authorize
  runtime deployment, cache deletion, service restart, provider calls, or APK
  installation.
