# P2-AISUB SPEED R3.2 — Continuous queue seam (SOURCE-ONLY)

**Parent:** [Issue #89](https://github.com/trung-via/torrent-tv-vietsub/issues/89) / [FULL-SRT #88](https://github.com/trung-via/torrent-tv-vietsub/issues/88). **Target model:** Human-selected **Antigravity Gemini 3.8 Flash High**, no silent model fallback or paid API. **Actual provider test:** NOT_RUN. **Legacy R3.1 private ZIP:** not present in this checkout; do not pretend this source-only scheduler is already integrated into that private Windows helper.

## Purpose

R2 scheduled batches in fixed parallel *waves*, waiting for all workers before dispatching the next wave. R3.2 uses a bounded continuous queue: when any worker finishes, a new batch may start immediately, while other workers are still running. Concurrency defaults to 3, bounded 1–4. No retry after quota/provider failure, no replay of a completed checkpoint, and no model switch.

The reusable implementation is `r3_2_continuous_queue.py`. It imports only standard-library concurrency primitives and **cannot** read private films, send prompts, call Antigravity, create/change checkpoints, manage the Windows OS lock, publish files, invoke ADB or change TV state. Its tests are synthetic only.

## Private R3.1 integration contract (NOT IMPLEMENTED HERE)

The private `full_srt_trial_r3.py` and `work/` cannot be overwritten without reading the exact current R3.1 version and confirming its SHA, checkpoint format and active provider processes. A future adapter MUST call `run_continuous` **inside the existing R3.1 Work Owner OS lock**, held across the whole full-story context + translation + assemble + QA, not just for this scheduler. The callback `owner_guard` must validate the caller's already-held lock; a bare constant `True` is acceptable in synthetic tests ONLY.

| Required callback/argument | Required consumer behavior |
| --- | --- |
| `expected_ids` | Strict ordered 1..N **batch IDs**, not source cue IDs; keep existing R2 90-cue manifest identity when resuming |
| `cached_ids` + `verify_cached(id)` | Read-only checksum/source/manifest/size/timestamp and checkpoint integrity proof; fail closed on corrupt cached item **before** any new model call |
| `invoke_provider(id)` | One bounded, explicitly approved AGY Gemini 3.8 Flash High call for this batch, with whole-story context and R3.1 privacy-safe telemetry; no built-in retry/fallback |
| `verify_result(id, raw)` | Enforce actual final provider success/JSON + exact target cue IDs/order/count, text/UTF-8, timestamps owned by canonical parser |
| `commit_checkpoint(id, validated)` | Atomic private checkpoint write + readback/hash, return exactly `True` only for durable verified checkpoint; no old checkpoint overwrite |
| `owner_guard()` | Verify R3.1 OS Work Owner lock really held, not merely that an `.r3_1_owner.lock` file exists |
| `max_workers` | 1–4 (default 3), never exceed actual quota/caller limit |

**On failure:** no new batch is submitted once the failure is observed. Already-in-flight calls are allowed to finish and valid results may be committed, minimizing lost quota usage. `QueueBlocked` contains only constant error code and numeric `QueueReport` with `submitted`, `committed`, `failed`, `unsubmitted`, `reused`; provider exception text is not surfaced. No auto replay of failed calls on the same invocation; resume requires explicit subsequent run and revalidation.

## Evidence gates

- `R32_OFFLINE_QUEUE_TESTS`: 13 local synthetic tests PASS at authoring, including a slow worker while a third batch starts, cached 8-of-20, fail-closed provider and corrupted cache, independent/no-replay, strict Work Owner callback.
- `R32_HOSTED_CI`: pending live GitHub Actions run at PR creation.
- `R32_PRIVATE_R3_1_ADAPTER`: NOT_INTEGRATED. The earlier R3.1 private ZIP is not a versioned file in this public repo; source interface compatibility is not verified.
- `R32_REAL_WINDOWS_AGY_QUOTA`: NOT_RUN.
- `R32_REAL_FILM_1761_CUES`: NOT_RUN.
- `R32_SPEED_3_TO_5_MIN`: NOT_PROVEN.
- `R32_BRAIN_SEMANTIC_REVIEW`: NOT_RUN.

The original and translated subtitles, checkpoints, provider prompts/responses, paths and model receipts must stay in private owner-controlled storage, not the PUBLIC GitHub repo. Stage no new paid provider, G4 release signing, Windows services, TorrServer, device install or APK. The already installed Redmi Debug Font v3 is untouched.

**Next engineering step:** inspect/prove the exact R3.1 private source and current Work Owner lock without starting another model call; prepare a narrowly bounded local adapter and test all-cached resume first. Then obtain real authorized Windows model-call latency p50/p95 before claiming any 3–5-minute improvement.
