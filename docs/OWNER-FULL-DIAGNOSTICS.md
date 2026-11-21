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

The existing HostOps service runs as `NETWORK_SERVICE`, not the logged-in
Owner, so its existing sanitized snapshot job cannot open the Owner-private
full log. An automated full-log reader requires a **one-time** Owner-context
read capability and a private transport. Copying the full file into a public
GitHub Actions job, issue or artifact is **not** part of this implementation;
doing so could publish passwords or API credentials. Until an appropriately
private route is configured, use the local file directly.

No real TV, provider, TorrServer or AGY calls are performed by this patch.
