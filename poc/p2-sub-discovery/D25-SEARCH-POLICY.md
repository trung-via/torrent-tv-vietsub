# D2.5 search policy — owner-informed release heuristics, bounded VI

**Source-only Draft for Issue #129, stacked on D2.5 Draft #126.**
Human accepted the strategy on 2026-11-14 after explaining practical release
matching experience. The owner historically matched release group and resolution;
**that observation is a practical heuristic, not a measured probability or
guarantee of time sync**. The owner has no movie-hash calculation tool.
Do NOT impose movie hash as a user prerequisite.

## Policy

| Setting | VI | EN | Intended use |
| --- | --- | --- | --- |
| `VI_FAST` **default** | max one metadata GET, 4 s per-socket timeout, no page 2 | up to 2 GET pages | Prefer strongly confirmed VI but switch quickly to EN |
| `EN_DIRECT` | no online VI GET | up to 2 GET pages | User explicitly prioritizes translation over online VI search |
| `VI_FULL` | up to 2 GET pages, legacy incomplete-coverage HOLD | after completed VI | Explicit exhaustive VI preference |

Always use a **trusted already available VI track or verified cached VI** before
running any online search; these inputs belong to the upstream media/session
integration and are NOT implemented by this isolated search module.

**VI-FAST behavior:** if page 1 has a *complete* provider response and the
existing D1 matcher finds one confident, unambiguous VI winner, route
`VI_READY`. Otherwise (none, weak/ambiguous, page incomplete), search EN
immediately, never fetching VI page 2 or prompting through weak VI releases.
One VI provider GET that returns a transient `API_NETWORK_ERROR` also falls
back to EN without a retry; errors `401/403/429`, malformed provider schema or
identity mismatches do NOT silently trigger EN requests. Socket timeout is
not a guaranteed total wall-clock deadline across DNS and redirects: monitor
measured `VI_SEARCH_ELAPSED_MS` on the real owner device before claiming a
hard end-to-end latency SLO.

**EN:** combine up to two pages, reject ambiguous/partial metadata for automatic
downloads. Strong exact-group + same title/year/source (or independently
verified real moviehash) allows the existing confidence gate to choose.
If EN metadata matches title/year/source/resolution/codec but the release group
is unknown, the CLI displays a **read-only EN shortlist** for Human review;
it does **not** grant automatic POST approval. Extra local selection/verified
real movie binding requires a separate explicit Human action/gate.

## What metadata actually proves

- **Release group:** substring such as `GROUP` at the end of an authorized
  video release filename. It usually names a *video release/encoder group*;
  it is NOT automatically a subtitle translator/translator group. Exact same
  group is a strong but fallible sync hint.
- **1080p:** helpful resolution/ranking tie-breaker, NOT timing/cut proof.
- **Source/cut:** BluRay vs WEB-DL vs IMAX are material release distinctions.
- **Codec:** `x264`/`x265` tells how video is encoded, not necessarily the
  editorial cut/timeline. Codec mismatch alone does not prove subtitle
  incompatibility.
- **Movie hash:** strongest when actually computed over **video bytes** with
  the provider's prescribed algorithm. It is not a torrent infohash, guess,
  title or string pasted by Human. This module does not calculate the hash
  or access the Windows video; it remains optional.

## Network/quota and project-lane boundary

Search calls are metadata GETs only. They have a bounded page count and do
not consume a subtitle download POST. Existing one-POST latch and owner
`DOWNLOAD ONE` consent remain enforced by D2; no paid Gemini, no subtitle
dialogue upload, no TV connection or APK/Windows modifications in this slice.
Enabling `EN_DIRECT` explicitly skips **online** VI only; it does not mean
ignoring an existing VI track in the active OMP session.

EN delivery continues through D3 Draft #128 into the **existing** P2 LEAN120
Gemini API Draft #118 (configurable provisional model profile), and then the
existing P4 signed receiver Draft #120/G2 Draft #115. No new translation
transport/TV listener or duplicate model code is authorized by this policy.

No real OpenSubtitles timing benchmark or new-download trial in this PR.
Mock tests establish routing and fail-closed behavior only.

## Acceptance benchmarks after merging (not implemented)

For lawful source fixtures and measured real provider response times, record
the number of GETs for VI and EN, per-stage elapsed times, `VI_PROBE_STATUS`,
final route, whether provider's result set was complete, manual intervention
count, and any *independently proven* media timing sync. Use several authorized
release combinations, including same group/different cut and same resolution/
different group. Do not publish local media paths, subtitle content or keys.
