# R0 #174 — Owner-session diagnostics to dedicated Torrent TV HostOps

Status: **source candidate**, not Windows-enrolled, not an actual Redmi test.

## Data flow (one-way, read-only to HostOps)

1. Existing interactive `TorrentTV-Vietsub-OwnerAgent` calls its usual
   `owner_p3_p4_diagnostics.write_diagnostic()` callback once per tick.
2. When an *already enrolled* ProgramData diagnostics folder exists, the
   Owner Python process exports `owner-snapshot.json` atomically. It contains
   only fixed status enums, timestamps/ages and bounded ingress counts.
   It does not include media identifiers, network addresses, tokens, subtitles,
   event/claim IDs, source paths or secrets.
3. Dedicated `torrent-tv-vietsub-win` `NETWORK_SERVICE` runner uses the existing
   owner-comment HostOps #82 protocol, exact pin and fixed job
   `hostops/jobs/owner-diagnostic-snapshot.ps1`. The job only opens the
   ProgramData sanitized receipt, checks its schema/freshness and optionally
   reads the fixed scheduled-task state. It never opens `LOCALAPPDATA` or
   creates/changes private Owner files.
   If the service cannot enumerate the Task, task state remains `UNKNOWN`;
   that fact is reported independently from a fresh Owner-produced receipt.

### One-time setup — only if needed after reviewed source deployment

- An interactive, signed-in Windows Owner **with administrator elevation** runs
  `hostops/setup/enroll-owner-diagnostic-spool.ps1` in inspect mode first,
  then with `-Enroll` once. This creates ONLY the dedicated ProgramData
  `TorrentTVVietsub/OwnerBridge/Diagnostics` folder and grants the runner
  `NETWORK_SERVICE` **read-only** access to that folder and inherited receipt.
- No service privilege escalation, no Owner-private access, no Task restart,
  no firewall/network changes, no provider calls, no TV interaction.
- `-Disable` revokes the reader grant without deleting saved Owner/TV state.
  Stop the test before changing the folder while an existing Owner may write.
- If setup/enrollment is absent, the HostOps job reports
  `HOSTOPS_SETUP_REQUIRED` and **does not claim Owner live PASS**.

### Source activation and review

The Owner's **installed** app must be upgraded to a reviewed, pinned snapshot
that includes `owner_hostops_snapshot.py`, with installed SHA/provenance checked.
No host-side install or restart is performed merely by merging a PR.

### One-time P2 inspection while the old Owner runtime is still running

If the existing Owner runtime cannot yet be upgraded because one P2 provider
effect is uncertain, the interactive signed-in **Owner**, not NETWORK_SERVICE,
may run the fixed `hostops/setup/owner-p2-snapshot-once.ps1` source candidate.
It downloads three immutable, SHA-256-checked Python diagnostic modules from
the reviewed PR #175 commit, then exports one sanitized V2 receipt to the
**already enrolled** ProgramData folder. It does not need a Git checkout or
Administrator elevation, and never changes the Task, queue, inflight marker,
provider, LAN or TV. Do not rerun it to erase uncertainty: each invocation is
an independent read-only point-in-time capture.

The trusted `owner-diagnostic-snapshot` HostOps consumer now reports V2/P2
counts and HOLD enums for a receipt at most 900 seconds old, **independent of
P3 runtime freshness**. It labels capture age and always states that Owner
restart or P2 replay is not authorized. P3 counters still require a fresh
running Owner tick. An old/missing receipt remains `NOT_OBSERVED`, never CLEAR.
Only stage/use the reviewed HostOps job at its exact trusted branch SHA;
source candidate alone is not a live enrollment or acceptance.
For a future reviewed HostOps read-only run, create the trusted
`hostops/owner-diagnostic-snapshot` branch at the exact audited commit and
submit owner-authored comment to Issue #82:

`/tv-hostops run <exact-40hex-reviewed-head> owner-diagnostic-snapshot`

The existing #82 gate still requires a genuine owner comment. A ChatGPT model
or a GitHub PR comment cannot impersonate that provenance.

### Acceptance scope

- `OWNER_SNAPSHOT_STATUS=READY_FRESH` and bounded counts from a current
  Owner tick; different statuses for MISSING, INVALID_SCHEMA, STALE,
  PID_MISMATCH and OWNER_NOT_RUNNING.
- HostOps does not promote old counters when the receipt or Task is stale.
- This observes the already existing P3 ingress only; it **does not** prove
  `POST /torrents` metadata, a real TV press, P4 subtitle rendering or a
  provider call. Follow-up R0 one-enqueue and E2E proof are separate.
- Preserve blocked events, claims, and `*.inflight`. Never auto-replay.
