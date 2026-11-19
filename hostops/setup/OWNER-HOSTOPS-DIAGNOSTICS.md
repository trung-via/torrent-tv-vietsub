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

### Repeatable read-only Owner capture without restarting the live P3/P4 process

`hostops/setup/enroll-owner-diagnostic-capture.ps1 -Enroll` is an **Owner-only,
one-time** enrollment candidate. The Owner must be signed in. It checks the
original `TorrentTV-Vietsub-OwnerAgent` identity, downloads an immutable,
SHA-256-verified copy of the existing `owner-p2-snapshot-once.ps1` helper,
stores that exact helper in the already private `OwnerBridge/Maintenance`, and
registers the separate **no-trigger**
`TorrentTV-Vietsub-Owner-Diagnostic-Capture` task under the same interactive
Owner. The sole `NETWORK_SERVICE` grant is READ+EXECUTE on **this task only**.
No Owner profile, P2/provider, TV, LAN or original task permissions change.
The original Owner task stays Running throughout enrollment.

After one-time enrollment, exact-source trusted HostOps
`owner-diagnostic-capture` triggers the fixed read-only helper and reads the
V2 sanitized ProgramData snapshot using the existing strict consumer. The
helper captures **current P2 aggregates**, plus whichever P3 diagnostic was
actually published privately by the existing Owner process. If that older
runtime's P3 heartbeat is stale, P3 remains `UNKNOWN`; capture success **does
not** imply P3 DISPATCH, P2 provider or P4 TV rendering success. HostOps may
capture again after a *new* TV press without asking the Owner to run scripts.
Use `-Revoke` from the exact reviewed entry script to unregister only this
dedicated task (the private helper is preserved, never executed during revoke).

Enrollment is `HOSTOPS_SETUP_REQUIRED` until an actual Owner-task read/execute
grant and a new HostOps post-enrollment capture are verified. Source-only CI
must never be represented as live deployment.

### Explicitly approved P2 `batch-0001` preservation-first recovery

The Owner approved a **single** `UNKNOWN_EFFECT_NO_RETRY` quarantine on
2026-11-19. Existing HostOps #82 runs under `NETWORK_SERVICE`, not the signed-in
Owner, and cannot stop the two uninspectable Owner Python processes or write
Owner-private P2 files. This is `HOSTOPS_SETUP_REQUIRED` for future native
fixed Owner-session maintenance; the service may still collect preflight and
postflight read-only receipts. Do not grant the service access to LOCALAPPDATA.

`hostops/setup/owner-p2-quarantine-once.ps1` is the bounded interactive
Owner-only **source candidate** for this one approved batch. It requires the
exact prior `batch-0001` marker SHA, checks the existing reviewed no-retry
worker and absence of pending events/checkpoint/lock, and fetches only its
dependencies from immutable commit `cac462c1dd854a7b19fd0eb02018c9bd1aebb7fe`
with SHA-256 verification. Only after all preflight checks pass does it
disable and stop `TorrentTV-Vietsub-OwnerAgent`, invoke the existing offline
reconciler to write the tombstone **before** preserving the marker as
`.quarantined`, and export a fresh sanitized HostOps snapshot. It deliberately
leaves the Task disabled even on success, for separate installed-source,
worker/PID and no-replay review before a controlled new-film restart.

This script is **not** a HostOps service operation, has **not** been executed
on Windows, and does not call Antigravity, OpenSubtitles, TV or LAN. If source
download, identity, marker, task state or stop fails, no quarantine is
authorized. Any failure after Task disable leaves it disabled; do not
attempt to force a retry or silently re-enable it. Windows hosted CI only
parses/tests source; it cannot certify the future live maintenance effect.

### One-time HostOps permission enrollment (approved 2026-11-19)

An Owner-interactive, **separate on-demand** Windows Scheduled Task is used
for the existing approved `batch-0001` preservation transaction. This is not
another resident OwnerAgent: the existing `TorrentTV-Vietsub-OwnerAgent`
stays running with its original launcher and `IgnoreNew` policy.

- One-time signed-in Owner executes the **source-pinned**
  `hostops/setup/enroll-owner-p2-quarantine-task.ps1` from an exact reviewed
  PR commit, with the entry script's SHA-256 verified before execution.
  The entry script itself fetches the immutable already reviewed one-shot
  helper from commit `50f282a484dd6ad6104587a914b753e1ed467972` and
  verifies SHA-256
  `a21ff672e15db0b2efca20909ae88b35957193f99a52a83a3000dfa65f3d7cb3`.
  No repository checkout or private API key is needed.
- Enrollment validates the **existing** Owner Task principal and original
  action, copies the helper only into Owner-private `OwnerBridge/Maintenance`,
  and registers **no-trigger** `TorrentTV-Vietsub-P2-Quarantine-Once` under
  `InteractiveToken` / `Limited` for that same Owner. It is on-demand only,
  has an execution timeout, and is permitted to run on laptop battery.
- Windows Task Scheduler DACL grants only the dedicated `NETWORK_SERVICE`
  identity **generic read and execute** for that single maintenance task.
  It does not grant service admin, Owner profile, file or task-write access.
  Owner must be signed in. If the Windows DACL grant is rejected, enrollment
  fails; never fall back to changing the runner service account.
  On 2026-11-19, the live signed-in Owner and subsequent dedicated HostOps
  read-only probe agreed on **one** `AccessAllowed` ACE for `NETWORK_SERVICE`,
  with Windows-mapped mask `0x001200A9` (specific READ + EXECUTE), rather
  than the submitted generic `GRGX` mask `0xA0000000`. The first enrollment
  script incorrectly rejected this valid readback and reported
  `OWNER_P2_ENROLL_NETWORKSERVICE_RX_NOT_VERIFIED` **after registering** the
  task. The source now accepts exactly these two read/execute encodings;
  no Owner re-enrollment or permission broadening is needed to correct the
  false-negative check.
- The trusted owner-comment command `/tv-hostops run <exact-SHA>
  owner-p2-quarantine-dispatch` uses the fixed HostOps job and requires the
  corresponding reviewed `hostops/owner-p2-quarantine-dispatch` branch to
  equal that exact commit. The job checks both scheduled task identities,
  that the main Owner Task is Running, the no-trigger fixed maintenance
  action, and **no previous task execution**. It calls only
  `Start-ScheduledTask` on the dedicated task. Its receipt is
  `TRIGGERED_NOT_VERIFIED` until the Owner task and fresh sanitized P2
  after-snapshot actually prove the preservation completed.
- After a successful or failed attempt, do not automatically re-run. The
  helper preserves the unknown-effect marker bytes as `.quarantined` and
  disables the original OwnerAgent. No automatic Owner Task restart or
  Antigravity/TV/provider call is authorized here. The next controlled
  restart requires a fresh review of the Owner result and installed code.
- 2026-11-19 actual execution receipt: trusted [HostOps #44556216328]
  (https://github.com/trung-via/torrent-tv-vietsub/actions/runs/44556216328)
  confirmed `OWNER_TASK_TRIGGERED_NOT_VERIFIED`. Read-only [probe #44557217955]
  (https://github.com/trung-via/torrent-tv-vietsub/actions/runs/44557217955)
  then confirmed the original Owner Task `DISABLED`, dedicated maintenance
  `READY` and `PRIOR_ATTEMPT`. Read-only [snapshot #44557340702]
  (https://github.com/trung-via/torrent-tv-vietsub/actions/runs/44557340702)
  still saw a stale P2 capture (`NOT_OBSERVED`, ~5341s old). **Quarantine
  completion and marker preservation are NOT VERIFIED.** The service-side
  probe now emits Task Scheduler's last process exit code for diagnosis,
  explicitly not as proof of the private Owner transaction. Do not retry.
- To revoke unused permission, the same authenticated Owner runs
  `enroll-owner-p2-quarantine-task.ps1 -Revoke` from exact verified source.
  It unregisters only the dedicated maintenance task after validating its
  original action. It does **not** delete Owner P2 state or change the
  normal OwnerAgent task. Revoke while the maintenance task is running is
  prohibited: wait for completion and investigate its receipt first.

This is `SOURCE_IMPLEMENTED` and `OWNER_ENROLLED` with a single live
dispatch attempt, but **NOT `LIVE_QUARANTINED`** until a fresh independent
Owner-private preservation receipt proves the transaction. Hosted Windows CI
checks only parsing and fixtures.

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
