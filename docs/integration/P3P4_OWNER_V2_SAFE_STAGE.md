# P3/P4 Owner V2 — inert owner-only stage, no restart

## Why this step exists

The verified Windows Owner V1 task may be `Running` and its private heartbeat
may say `READY`. In the current event loop, `READY` is written **before**
`poll_private_events()` and is not an atomic indication that a provider job is
idle. A queued event can become billable after any external status check, and
an interrupted `.claim`/`.inflight` must never be silently replayed.

Therefore the existing HostOps `NETWORK_SERVICE` account is **not** an
acceptable process restart/deployment actor. It cannot read owner-private
`LOCALAPPDATA`, independently prove no in-flight provider call, or safely
control the Owner process. Neither one live LAN listener nor a fresh heartbeat
proves that a restart is safe.

## Reviewed source candidate

The 4 runtime files staged by
`hostops/setup/stage-owner-p3p4-v2.ps1` are byte-pinned to Draft PR #165,
`f7fdb02404660ced8e3834a6a621ccdfb8de63cd`:

- `owner_p3_p4_diagnostics.py`
- `p3_owner_state_wiring.py`
- `p3_p4_shared_https_route.py`
- `p3_ingress_telemetry.py`

The script validates those four SHA-256 hashes, the current interactive
Windows Owner identity, the already-installed OwnerBridge tree and the
**exact existing** Scheduled Task principal/action using existing source
guards. It does not read pairing keys or private subtitle/media bytes.

Source-only checks do **not** constitute independent Brain approval to merge,
source-to-runtime parity or proof that the new Python modules are loaded.

## Two strictly separate steps

Run from a source checkout containing this script and its pinned #165 runtime
modules, **in PowerShell 7 as the logged-in Windows Owner**:

```powershell
./hostops/setup/stage-owner-p3p4-v2.ps1
```

This default command is read-only. On an exact owner/source/task match it
prints `TTV_OWNER_V2_STAGE=READ_ONLY_PREFLIGHT_PASS`. An unexpected account,
task, source hash or reparse point produces `HOLD_*` and no staging.

After reviewing that preflight, the owner can perform the independent inert
stage with:

```powershell
./hostops/setup/stage-owner-p3p4-v2.ps1 -Stage
```

This creates/verifies copies of four `.py` files only under the existing
owner-private `OwnerBridge/staged-releases/p3p4-ingress-v2-f7fdb024` tree.
The running `OwnerBridge/app` code, launcher, task, service, Windows ACLs,
TV/ADB and provider are **untouched**. The stage is idempotent only if all
existing staged files match their pinned hashes; otherwise it holds.

Expected successful stage markers:

```
TTV_OWNER_V2_STAGE=INERT_FILES_VERIFIED
TTV_OWNER_V2_INSTALLED_RUNTIME=UNCHANGED
TTV_OWNER_V2_ACTIVATION=HOLD_UNTIL_SAFE_IDLE_OWNER_STOP_AND_REVIEW
```

**No restart in this step**. V2 counters remain unavailable until a future,
independently authorized offline installation into the actual OwnerBridge app
and subsequent interactive task start.

## Separate activation gate (not provided by this staging script)

Before a subsequent change can activate V2, require all of the following:

1. Exact Windows owner/task/process identity, expected installed source
   baseline and rollback copy verified in that private Windows session.
2. A race-free owner-cooperative quiesce proof or an already naturally stopped
   owner task with no leftover owner runtime process. The V1 `READY`
   heartbeat and an empty private inbox are **insufficient**.
3. Uncertain `.claim` or provider `.inflight` state reconciled, not deleted
   or automatically replayed. Pending requests cannot be silently dropped.
4. Independent Brain source/CI review and individually authorized activation.
5. After a *safe* task start, a fresh same-PID V2 heartbeat+diagnostic and
   bounded P3 HTTPS counters from the actual process; then separate real TV
   ingress/selection and P4 delivery validation. No model or subtitle
   translation request merely to prove a diagnostic version.

This gate intentionally keeps the present live Owner V1 process operational.
