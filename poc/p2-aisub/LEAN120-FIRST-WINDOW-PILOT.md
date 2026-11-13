# P2 LEAN120 first-window pilot: bounded, checkpointed, no TV

Tracking: Issue #132, source-stacked on composed Draft #134.

## Scope and contract

For the **already downloaded** English timed SRT, the owner can first run
the existing `owner_vietsub_pipeline.py` in read-only mode with its real
private-cache filename, SHA-256 and cue count. **No OpenSubtitles GET/POST**
or cloud API is needed for this integrity check.

The same CLI has three deliberately distinct behaviors:

| CLI options | Action | Charged/model windows | TV |
| --- | --- | --- | --- |
| none | Re-read existing EN cache, verify SHA/UTF-8/cue IDs/timeline | **0** | none |
| `--execute-api --authorize-cloud-upload` | **First LEAN120 window only** of this file | **at most 1** if not checkpointed | none |
| above + `--translate-all` | Continue full remaining film with same existing worker/checkpoints | additional windows, may incur quota | none |

The pilot uses the original P2 `AutomaticLean120Worker` implementation with
an optional **first-window-only cap**, not another translator. The first
window contains at most 120 target cues and 6,500 source characters (with
up to four read-only context cues on each side). The exact target count
may be **less than 120** if character limits apply. The translated prefix
is committed to the existing private `batch-0001.json` checkpoint after
strict cue/ID/timecode QA. Since it is an incomplete film, `vi-final.srt`
is NOT prematurely produced. No synthetic local-only media key or partial
revision is delivered to TV.

**Critical idempotency property:** invoking the **same first-window pilot
again** only replays `batch-0001.json` and does not proceed to batch 2 or
issue a second model request. A failed or uncertain first provider request
leaves the existing `batch-0001.inflight` and blocks an automatic retry.
Manually deleting state to force a second call is prohibited. Full-film
work must be a separately authorized operation (explicit `--translate-all`).

The owner previously authorized exactly one OpenSubtitles EN source download;
that approval is NOT a cloud subtitle-upload permission. **A real Gemini
pilot requires separate explicit owner permission**, a valid owner-held
`GEMINI_API_KEY`, and an owner-verified model profile. No actual provider
call is invoked from source authoring/CI. The existing Draft #118 provisional
profile selects `gemini-3.8-flash` at medium thinking; this is a candidate
configuration, NOT verified model availability or a claim of successful
live Gemini translation.

## Read-only user path

From the composed source checkout at an exact pinned commit:

```text
py -3 poc/p2-sub-discovery/owner_vietsub_pipeline.py \
  --cache-filename <owner-private-hex-name>.srt \
  --sha256 <owner-reported-original-srt-sha256> \
  --cues <owner-reported-count>
```

Expected: `P2_CACHED_EN_REVALIDATED=PASS`, exact expected cue count,
`OPEN_SUBTITLES_GET_POST=0`, `GEMINI_API_REQUESTS=0`,
`TV_DELIVERY=NOT_RUN`. No private SRT text, keys or Windows paths should
be posted to the PUBLIC GitHub issue.

## Independent evidence gates

- `SOURCE_IMPLEMENTED`: this patch on the independent PR branch, not main.
- `CI_PASS`: tests with synthetic English SRT and fake Gemini proving
  first-window cap, repeat-pilot zero new charge, checkpoint resume to
  full-film, wrong flag rejection, local CLI read-only, no D3/P4 side effects.
- `REAL_LOCAL_EN_READONLY`: waiting for owner machine output.
- `REAL_GEMINI_FIRST_WINDOW`: **NOT RUN** without separate cloud grant.
- `REAL_VIDEO_SYNC`, `P4_REDMITV_AUTOMATION`: NOT VERIFIED.

The existing verified D3+P4 pipeline stays independent for real TV delivery.
