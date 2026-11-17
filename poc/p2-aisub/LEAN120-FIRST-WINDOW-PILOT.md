# P2 LEAN120 one-run full film with optional first-window diagnostic

Tracking: Issue #132, source-stacked on composed Draft #134.

**Current operator route (Draft #173):** [Antigravity owner guide](ANTIGRAVITY-OWNER-CURRENT.md).
Earlier Gemini Developer API authorization/profiles in #132 are historical,
not commands to execute in the current source.

## Scope and contract

For the **already downloaded** English timed SRT, the owner can first run
the existing `owner_vietsub_pipeline.py` in read-only mode with its real
private-cache filename, SHA-256 and cue count. **No OpenSubtitles GET/POST**
or cloud API is needed for this integrity check.

The same CLI has three deliberately distinct behaviors:

| CLI options | Action | Charged/model windows | TV |
| --- | --- | --- | --- |
| none | Re-read existing EN cache, verify SHA/UTF-8/cue IDs/timeline | **0** | none |
| `--execute-provider --authorize-cloud-upload` | **Full English SRT → Vietsub in one foreground run**, internally checkpointed LEAN120 windows | as many as required, may consume account quota | none |
| above + `--pilot-first-window` | Optional diagnostic: first window only | at most one for that source; repeated pilots never advance | none |

The full-film mode uses the **existing** `AutomaticLean120Worker`: internally
divide into at most 120 target cues / 6,500 source characters per batch,
with bounded read-only context. There is **no per-batch human prompt** and
completed batches are committed in owner-private checkpoints.
Only after the entire film completes is `vi-final.srt` written. The
`--pilot-first-window` diagnostic is optional and never the default.
No local-only media key or subtitle is sent to TV from this CLI.

**Idempotency and quota safety:** a rerun in full-film mode replays completed
checkpoints without issuing duplicate Antigravity calls; any uncertain `.inflight`
marker blocks an automatic retry and requires owner-side review. The
optional first-window diagnostic likewise never proceeds to window two on
repeat. Do not delete or edit a checkpoint to force a provider re-bill.

The current source selects the owner-account Antigravity CLI gateway with
`model=gemini-4-hydrogen-high`, `thinking_level=high`. A locally signed-in
CLI account, matching alias and adequate account quota must be checked before
a real call. No developer API key is required by this translator. Historical
authorization for a previous Gemini API trial is **not** proof of a new live
Antigravity invocation; first reconcile the old uncertain `.inflight` state.

## Read-only user path

From the composed source checkout at an exact pinned commit:

```text
py -3 poc/p2-sub-discovery/owner_vietsub_pipeline.py \
  --cache-filename <owner-private-hex-name>.srt \
  --sha256 <owner-reported-original-srt-sha256> \
  --cues <owner-reported-count>
```

Expected: `P2_CACHED_EN_REVALIDATED=PASS`, exact expected cue count,
`OPEN_SUBTITLES_GET_POST=0`, `ANTIGRAVITY_CLI_REQUESTS=0`,
`TV_DELIVERY=NOT_RUN`. No private SRT text, keys or Windows paths should
be posted to the PUBLIC GitHub issue.

## Independent evidence gates

- `SOURCE_IMPLEMENTED`: this patch on the independent PR branch, not main.
- `CI_PASS`: tests with synthetic English SRT and fake Antigravity output proving
  full-film default, optional first-window cap, checkpoint resume,
  model profile and local CLI authorization, no D3/P4 side effects.
- `REAL_LOCAL_EN_READONLY`: HUMAN_REPORTED_PASS, 1,761 cues.
- `REAL_ANTIGRAVITY_FULL_SOURCE`: **NOT RUN** until local owner executes it.
- `REAL_VIDEO_SYNC`, `P4_REDMITV_AUTOMATION`: NOT VERIFIED.

The existing verified D3+P4 pipeline stays independent for real TV delivery.
