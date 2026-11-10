# Thor source-pinned FastPath v0.4 vs historical v0.3.4/v0.3.5

This is a **research replay guard**, not a new translation, Gemini call, device operation, or verified model speed improvement.

- Owner-authorized original source: `Thor.Ragnarok.2017.1080p.BluRay.x265-YAWNTiC_eng(1).srt` (1,761 cues).
- Required SHA-256: `76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a`.
- Matched windows: W01 `181–340`, W02 `561–720`, W03 `1081–1240`.
- Older v0.3.4 archived initial session wall (seconds), **excluding fully measured semantic repair**:

| Window | QUALITY_60 | FAST_120 | EXP_160 |
|---|---:|---:|---:|
| W01 | 78.552 | 66.091 | 63.348 |
| W02 | 76.987 | 85.538 | 82.465 |
| W03 | 72.968 | 74.610 | 79.167 |
| Total | 228.507 | 226.239 | 224.980 |

The **control** for a new v0.4 experiment is `BASE120` (v0.3.5-aligned FAST120). Candidates `LEAN120` and `ADAPTIVE` must translate those same English source cue IDs as fresh model outputs. v0.3.4 FAST120 timing is historical context only; its run is **not** interchangeable with a fresh v0.4 BASE120 measurement.

## Exact commands (offline; original owner-supplied file only)

```powershell
python poc/p2-aisub/brain_v04_thor_replay.py baseline
python poc/p2-aisub/brain_v04_thor_replay.py precheck --source PRIVATE_ORIGINAL_THOR_EN.srt
python poc/p2-aisub/brain_v04_thor_replay.py plan --source PRIVATE_ORIGINAL_THOR_EN.srt --workdir PRIVATE_NEW_THOR_V04_STUDY
```

The `plan` command calls the merged `brain_fastpath_v04_experiment.py` only after checking **byte-identical original source SHA** and full 1,761 numbered cues, and refuses an existing workdir. Prompts and private source text stay in owner-private workdir **outside the PUBLIC repo**. It creates 3×3 = 9 planned trials but **does not invoke ChatGPT Brain or Gemini**. Fresh translated `ID|VI` rows must be generated in ChatGPT itself, then logged with v0.4 `start` / `phase` / `finish` and independently bilingual-reviewed.

The original source metadata was located in ChatGPT Library on 2026-11-10, but authorized raw/text access failed for both historical English-SRT file entries. The old report text and partial VI extraction are accessible. **Current gate:** `SOURCE_BYTES_UNAVAILABLE`, `NEW_BRAIN_TRANSLATION_NOT_RUN`, `HISTORICAL_BASELINE_AVAILABLE`, `BRAIN_V035_DEFAULT_UNCHANGED`. Do not fill missing EN cue text by back-translating VI or downloading movie captions from unrelated sites. No historical film text should enter GitHub.

Only claim repeatable >=20% end-to-end gains after actual new same-source measurements including QA/repair, independent semantic non-inferiority, and at least 3 non-overlapping windows. Preserve existing reviewed VI, TV Debug Font v3, R3.1 legacy state, and G4 NOT_PLANNED.
