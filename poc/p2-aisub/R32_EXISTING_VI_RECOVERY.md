# Torrent TV Vietsub — Recover completed subtitles without R3.1 ZIP

**Scope:** source-only, local-first. This is NOT the expired 2026-11-08 `Torrent_TV_AISUB_R3_1_WorkLock_Telemetry.zip` and does not recreate its original executable/manifest format.

## Why this is useful

If the complete, lawful **original EN SRT/VTT** and its already translated **VI SRT/VTT** both still exist on the Windows machine, there is no reason to spend Antigravity quota translating the same movie again just because the old helper ZIP download expired. The new `r32_existing_vi_rehydrate.py` validates the two real files against the canonical `cue_pipeline` contract and can rebuild *a new, separate* 90-cue cache from the completed VI, with no provider calls or old checkpoint modification. The completed VI's semantic accuracy is **not** certified by byte/timing checks.

## Modes and exact guarantees

1. **Read only (default):** `python poc/p2-aisub/r32_existing_vi_rehydrate.py --source <private-en.srt> --translated <private-vi.srt>` checks 1..N cue IDs, cue count, original start/end milliseconds, encoding and safe VI text. Prints sanitized JSON with SHA-256 hashes, cue/batch counts and unchanged-EN cue count. The source and VI files are not modified.
2. **Create separate private cache (explicit opt-in only):** add `--new-cache-dir <brand-new-private-directory> --confirm CREATE_NEW_PRIVATE_CACHE_V1`. This creates *only* the new directory, a manifest under `work/input_manifest.json` and `work/batch_001.json` ... with 90 translated cues per batch (20 for the 1,761-cue example). The destination MUST NOT exist and MUST NOT be under an existing legacy `work/` directory. It never overwrites or deletes files. A partial new directory after an I/O error is **untrusted**, not auto-retried/cleaned up.
3. **Read-only verify created cache:** `python poc/p2-aisub/r32_existing_vi_rehydrate.py --source <private-en.srt> --verify-cache-dir <new-cache-directory>` checks exact manifest source identity, batch set, per-file hash, cue IDs/text integrity and reconstructed VI hash. Fails on missing/extra/tampered batch or unknown legacy format.

The new cache's schema is `torrent-tv-existing-vi-recovery-v1`, model provenance is intentionally marked `UNKNOWN_IMPORTED_EXISTING_VI`. This is NOT R3.1's undocumented `input_manifest.json`/`batch_###.json` schema. Do not point `--new-cache-dir` at any old `work/` or feed these checkpoint files into the original R3.1 helper without a separate adapter review. No `agy`, Gemini, paid APIs, subtitle cloud transfer, Windows runner process control, TV install/ADB or G4 Release action exists in this tool.

**Privacy:** This code may read private EN/VI only when the owner explicitly selects paths. It prints no subtitle lines, film names or filesystem paths. The optional cache contains private translated dialogue and must remain **outside the PUBLIC GitHub repo and GitHub Actions artifacts**. Do not upload user media to GitHub. A 1,761-cue full-SRT test in CI uses only synthetic dialogue.

## Evidence and open gates

- New offline unit tests cover **20 synthetic cases**, including 1,761 cues→20 batches, strict SRT/VTT parity, forced cache corruption, unknown legacy manifest, no overwrite, separate destination and privacy-safe output.
- GitHub hosted CI: attach real run on the precise PR HEAD; local synthetic tests do not imply host install.
- Historical R3.1 original ZIP: **UNRECOVERED**. Exact legacy checkpoint schema + file locations: **UNVERIFIED**. Actual EN/VI user files: **NOT_AVAILABLE_IN_THIS_EXECUTION**. Private cache creation/real pair verification: **NOT_RUN**.
- R3.2 scheduler already source-merged PR #104 and CI 255/255; **not yet wired into a real provider**, and **3–5-minute full-film latency NOT PROVEN**. This rehydrator addresses *recovery of already completed subtitles*, not throughput for future translation.

**Next:** If real completed EN+VI remain available to a privately authorized Windows context, read-only verify their exact pair before any new cache creation. After safe recovery, implement a distinct version-pinned Antigravity provider adapter for future titles only (rights, quota, model identity and Work Owner gates); do not auto-replay a completed movie.
