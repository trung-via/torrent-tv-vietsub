# Owner full diagnostics — one private PC log (2026-11-21)

The same interactive Windows Owner process captures the complete console
output, original exception messages and Python tracebacks of its integrated
P3 HTTPS ingress, P2 discovery/translation and P4 paired HTTPS endpoint.

## Owner-local output

`%LOCALAPPDATA%\TorrentTVVietsub\OwnerBridge\diagnostics\owner-full.log`

- Installation: `owner_p3_p4_entrypoint.py --start-lan` activates the single
  append-only log once for each Owner process lifetime. `--preflight-only`
  never starts logging. No new listener, provider client, worker, polling loop
  or HTTP endpoint is introduced.
- The log is **unredacted** on the owner's PC, as explicitly requested.
  Media titles, session identifiers, paths, provider responses and even
  exception text containing secrets may appear. Keep the file owner-local.
- P2 captures the full traceback even when the existing public-safe console
  marker is `OWNER_BRIDGE_BLOCK_REASON=UNCLASSIFIED`. The event and original
  no-retry claim remain untouched.
- Owner stdout/stderr continue to reach their original streams. Existing
  HostOps aggregate V3 snapshots stay wire-compatible and **do not** include
  raw log contents.
- Existing F6 translator/provider implementation hashes remain unchanged.
  This patch enables its existing stage emit callback from the owner process.

## HostOps and installation contract

Source-only CI must not be represented as an installed Windows Owner. This
change touches `owner_p3_p4_entrypoint.py`, `owner_session_bridge.py` and
`p3_p4_shared_https_route_r0.py`; installed source hashes must be checked
against the current exact commit before replacement.

Installation on the Owner PC requires one approved **stopped/idle** maintenance
of the existing scheduled task, backing up the old three files and rolling back
if the new Owner fails to produce a fresh heartbeat. Never replay `*.blocked`,
`*.inflight` or previous model/provider requests while deploying diagnostics.

The November 21 Owner attempt rolled back successfully but the earlier
installer hid its original exception. Owner remained `Running`/`READY` on
the old three hashes and `owner-full.log` was not created, so the underlying
failure is **not yet identified**. The corrected installer performs a local
offline import of the newly installed modules before starting the task,
reports the exact failed phase and exception *before* rollback, and saves
the original failure to the Owner-private backup folder as
`maintenance-failure.log` (plus `offline-import-smoke.log`). The latter logs
are separate from the unified P3/P2/P4 runtime log, which exists only after
the new Python entrypoint starts. No raw log is sent to GitHub/HostOps.

The subsequent actual Owner receipt identified the original failure as
`REPLACE_FILES` / `.NET File.Replace` / `The path is empty`. Both forward
replacement and rollback previously passed a null third (backup) argument.
The repaired revision provides explicit owner-private backup paths for both
operations, preserving the same atomic replacement and rollback design.
This is source correction, not proof of a successful live upgrade.

The exact pinned one-time script is
`hostops/setup/owner-full-diagnostics-maintenance-once.ps1`:
inspect with no flags and install with `-Apply` in the logged-in Windows Owner
session. It downloads/verifies only the three source blobs from `627f452`,
stops and restarts only `TorrentTV-Vietsub-OwnerAgent`, and checks a new
heartbeat plus appended full-log startup marker. It does not restart a
translator batch. A failed startup restores the original three source files.

The existing HostOps service runs as `NETWORK_SERVICE`, not the logged-in
Owner, so its existing sanitized snapshot job cannot open the Owner-private
full log. An automated full-log reader requires a **one-time** Owner-context
read capability and a private transport. Copying the full file into a public
GitHub Actions job, issue or artifact is **not** part of this implementation;
doing so could publish passwords or API credentials. Until an appropriately
private route is configured, use the local file directly.

No real TV, provider, TorrServer or AGY calls are performed by this patch.
