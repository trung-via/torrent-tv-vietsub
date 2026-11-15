# Owner P3/P4 private runtime diagnostic (V2 Draft, source only)

## Purpose and evidence boundary

The Windows `NETWORK_SERVICE` GitHub runner cannot inspect the logged-in
Owner's private process command line or `LOCALAPPDATA` files. This change
does **not** change Windows ACLs, copy private data into ProgramData, expose
an unauthenticated LAN route, restart a scheduled task or infer current code
from an installed source file. The **running Owner Python agent** produces
its own fixed-enum receipt on its existing loop; the owner account alone
reads it.

The separate `agent-health.json` heartbeat remains at schema V1 and is
required to be fresh **and have the same process PID** before the diagnostic
is reported as live. This prevents a recent diagnostic from an exited P3/P4
process being mistaken for a newly started legacy owner task. When absent,
stale, malformed or stopped, `OWNER_RUNTIME_MODE=NOT_OBSERVED` (never a
claim that the old or new bridge is running).

The V2 diagnostic adds **process-local, fixed-vocabulary P3 HTTPS ingress
counters**, fed by the *same* authenticated P3/P4 handler. It does not add
an endpoint, listener, log of requests, privilege, task, retry, provider or
media read. V2 is a protocol upgrade: a V2 observer intentionally reports
`NOT_OBSERVED` while an older V1 process is still running. Do not restart an
active owner session merely to upgrade telemetry.

## What the fields mean

| Field | Evidence / limitation |
| --- | --- |
| `OWNER_RUNTIME_MODE` | `INTEGRATED_P3_P4` only if a fresh receipt produced by the integrated runtime and fresh owner heartbeat coexist. |
| `OWNER_RUNTIME_VERSION` | Loaded diagnostic protocol build marker, not a Git commit hash or APK version. |
| `P3_STATE_FRESH` | Non-identifying P3 state choice sampled from the signed in-memory TV cache. Remaining TTL is rounded **down** and checked again on read; stale never counts as fresh. `FRESH_OFF` means TV disabled this film and is not a provider authorization. |
| `TORRSERVER_READER_READY` | TCP handshake to configured `127.0.0.1` high port; `TCP_REACHABLE_METADATA_UNTESTED` explicitly does **not** prove a `/torrents` HTTP response, exact file match or downloaded subtitle. |
| `OWNER_HEARTBEAT` | Fresh private `agent-health.json` heartbeat required. |
| `P3_HTTPS_INSTRUMENTED` | `YES` means counters come from the live composed handler; `NO` means the reader is not instrumented. Both are conditional on a fresh Owner heartbeat. |
| `P3_HTTPS_STATE_ACCEPTED` | Number of HMAC-verified `/p3/state` requests accepted since this Owner process started. |
| `P3_HTTPS_STATE_REJECTED` | Requests to that path rejected before/at verification (bad HTTP format, signature, replay, stale clock, etc.). **Never** proof the genuine TV was the client. |
| `P3_HTTPS_SELECTION_DISPATCHED` | Signed per-film `/p3/selection` events actually enqueued to the existing private Owner inbox. Does not prove subtitle ready or TV playback. |
| `P3_HTTPS_SELECTION_SKIPPED` | Signed selection events accepted but not requesting work (e.g., ordinary Play/Next). |
| `P3_HTTPS_SELECTION_REJECTED` | Requests rejected before enqueue, including invalid signed event or failed safety gate. |

All counts are nonnegative integers saturated at 1,000,000 and reset on an
Owner process restart. They are not cumulative across sessions, may include
unauthenticated *rejected* traffic, and do not prove that a Windows Owner
task is serving the **same APK** currently installed on the Redmi. The
source `P3_STATE_FRESH` remains the authoritative freshness view.

### Pinpointing `P3_STATE_FRESH=MISSING`

| V2 owner-private observation | What it supports | What it does **not** prove |
| --- | --- | --- |
| `STATE_ACCEPTED > 0` | At least one HMAC-valid status reached the running handler | Current session is still fresh, TorrServer file was verified, subtitle generated |
| `STATE_REJECTED > 0`, accepted `0` | HTTP reached the P3 state route but no valid status has been accepted | Whether the sender is the Redmi; the precise private reason (HTTP, HMAC, clock, replay) |
| Both status counters `0` | No `/p3/state` request reached this handler since process start | Whether P3 is toggled off, player does not sample, TV cannot connect, or TLS failed before HTTP |
| `SELECTION_DISPATCHED > 0` | An explicit verified viewer request was enqueued | The worker completed or P4 delivered VI to Redmi |
| `SELECTION_REJECTED > 0` | A selection request reached this route but was refused | A permission to bypass safety checks or resend blindly |

Only when `P3_HTTPS_INSTRUMENTED=YES` and `OWNER_HEARTBEAT=READY_FRESH`
may these counts guide debugging. A failing or absent diagnostic cannot
authorize an OpenSubtitles/Gemini call, TV install or service restart.

No torrent hash, file index, filename, LAN bind, movie title, pairing token,
provider/API key or private filesystem path is written or printed.

## Read-only owner-side check after separately reviewed installation

From **PowerShell in the logged-in Windows Owner account**, with the existing
Owner task left running:

```powershell
$ownerRoot = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\OwnerBridge'
$diagScript = Join-Path $ownerRoot 'app\poc\p2-sub-discovery\owner_p3_p4_diagnostics.py'
python $diagScript --owner-root $ownerRoot
```

Expected read-only footer: `TTV_P3P4_DIAG=READ_ONLY_COMPLETE`. A missing,
old or not-yet-restarted agent reports `NOT_OBSERVED`, not PASS. After a
reviewed source installation while task is already running, its loaded
Python code remains unchanged until the **separately authorized** next
interactive task start. Do not stop a translation or restart the task just
to make a diagnostic appear.

## Verification gates

1. Offline synthetic tests for atomic owner-only receipt, no secret/movie
   leakage, symlink rejection, malformed/stale/status-STOPPED refusal.
2. Existing integrated P3/P4 runtime and P3 signed-state regression tests.
3. Independently reviewed exact PR head/base; no production merge/install
   implied by offline CI.
4. Synthetic HTTPS tests confirm 204/403/413/415 counters, legacy P4
   isolation, signed-state and per-film enqueue contract, without exposing
   request content. A zero counter cannot observe an earlier TLS handshake.
5. Only after reviewed owner-side deployment: live read-only receipt +
   separate actual TV/TorrServer exact-file proof. No real provider call or
   TV subtitle acceptance is part of this change.
