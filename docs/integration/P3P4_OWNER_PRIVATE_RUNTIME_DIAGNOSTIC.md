# Owner P3/P4 private runtime diagnostic (Draft, source only)

## Purpose and evidence boundary

The Windows `NETWORK_SERVICE` GitHub runner cannot inspect the logged-in
Owner's private process command line or `LOCALAPPDATA` files. This change
does **not** change Windows ACLs, copy private data into ProgramData, expose
an unauthenticated LAN route, restart a scheduled task or infer current code
from an installed source file. The **running Owner Python agent** produces
its own fixed-enum receipt on its existing loop; the owner account alone
reads it.

The separate `agent-health.json` heartbeat remains at schema V1 and is
required to be fresh before the diagnostic is reported as live. When absent,
stale, malformed or stopped, `OWNER_RUNTIME_MODE=NOT_OBSERVED` (never a
claim that the old or new bridge is running).

## What the fields mean

| Field | Evidence / limitation |
| --- | --- |
| `OWNER_RUNTIME_MODE` | `INTEGRATED_P3_P4` only if a fresh receipt produced by the integrated runtime and fresh owner heartbeat coexist. |
| `OWNER_RUNTIME_VERSION` | Loaded diagnostic protocol build marker, not a Git commit hash or APK version. |
| `P3_STATE_FRESH` | Non-identifying P3 state choice sampled from the signed in-memory TV cache. Remaining TTL is rounded **down** and checked again on read; stale never counts as fresh. `FRESH_OFF` means TV disabled this film and is not a provider authorization. |
| `TORRSERVER_READER_READY` | TCP handshake to configured `127.0.0.1` high port; `TCP_REACHABLE_METADATA_UNTESTED` explicitly does **not** prove a `/torrents` HTTP response, exact file match or downloaded subtitle. |
| `OWNER_HEARTBEAT` | Fresh private `agent-health.json` heartbeat required. |

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
4. Only after reviewed owner-side deployment: live read-only receipt +
   separate actual TV/TorrServer exact-file proof. No real provider call or
   TV subtitle acceptance is part of this change.
