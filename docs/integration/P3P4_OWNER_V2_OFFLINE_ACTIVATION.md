# Owner V2 offline source switch — separate gated phase

This script is **not** an automatic restart mechanism. It does not stop or
start the existing Owner Scheduled Task. Source and tests are Draft candidate
code only. Real Windows activation still requires an explicitly approved,
owner-interactive maintenance window, and a verified task/process stop.

## Observed preconditions (2026-11-15, Human screenshot)

- Owner SID and task identity: verified by preflight.
- Inert V2 staged files: `INERT_FILES_VERIFIED`.
- `event-*.json`: 0, Gemini `.inflight`: 0 at a single observed moment.
- The Owner task **was Running** at observation. These zeros do **not** prove
  no event can arrive later. V1 heartbeat READY is not a quiesce proof.

## Read-only installed-source identity (follow-up)

In default inspection mode, the corrected Owner-interactive tool compares all
three **installed** modules with the reviewed V1 canonical hashes or V2 exact
bytes, and checks the V2 telemetry module. It emits only
`TTV_OWNER_V2_INSTALLED_SOURCE=V1_SOURCE_EXACT|V2_PRE_R0_SOURCE_EXACT|V2_R0_SOURCE_EXACT|MIXED_OR_UNKNOWN`.
Mixed, missing or modified modules fail closed. The stage-only hash result must
never be interpreted as the installed version.

`TTV_OWNER_V2_LOADED_RUNTIME=NOT_ATTESTED` is always separate: even an exact
V2 on disk does **not** establish that a currently Running Owner Python process
loaded those bytes. A safe source switch still requires a disabled/stopped task,
a verified V1 recovery backup, and subsequent fresh PID-bound V2 diagnostic.
NetworkService HostOps cannot substitute for this Owner-interactive inspection.

## New offline installer contract

`hostops/setup/owner-p3p4-v2-offline-activation.ps1` is owner-only and
read-only by default. Its optional `-Backup` action copies the **three
original** V1 Python modules into a separate private recovery directory and
verifies their V1 #164 canonical raw SHA-256. It does not stop or start the
task and is safe while it is Running. A new backup ID is returned; the
backup remains private in OwnerBridge. If installed source differs from the
reviewed V1 baseline, it reports HOLD and performs no activation.
The original V1 bytes are kept verbatim in the backup, even if Windows Git
checkout converted the reviewed LF blob to CRLF. Hash comparisons normalize
valid UTF-8 CRLF solely for source identity; the recovery copy is byte-exact.

The separately opted `-ApplyOffline -BackupFolder <private absolute path>`
requires:

1. Same logged-in Windows Owner, interactive PowerShell 7 session and exact
   verified Scheduled Task identity.
2. Task **already disabled by the Owner** within a separately authorized
   maintenance window; old V1 heartbeat PID exited and no other identifiable
   Owner Python process alive. `Ready` is **not sufficient** because it does
   not prevent a Scheduler restart. It will **not** disable, stop or start
   the task, terminate a process, or declare V1 READY to be idle.
3. No pending `event-*.json` or Gemini `.inflight` markers. Existing durable
   provider claim files are preserved, never replayed or cleaned.
4. Owner-private V1 recovery folder and installed baseline exactly match
   reviewed #164 source SHA-256; all staged V2 files match #165 SHA-256.
5. Before and between file replacements, the task stays disabled. The only
   destination is three existing OwnerBridge/app runtime Python modules plus
   one new V2 telemetry module.

Existing files are replaced atomically on the same volume, with V1 backup
retained. The supervised Windows attempt on 2026-11-16 failed because
`[IO.File]::Replace` with `$null` backup was reported as an empty `path`
argument. The corrected code always supplies a unique, **nonempty**
Owner-private previous-content path for both V2 overlay and V1 restoration;
these forensic copies do not replace or erase the preexisting V1 recovery
directory. Failed destinations are registered for recovery **before** each
file operation so a mid-operation exception cannot escape rollback scope.
On apply failure, it attempts V1 restoration **only if the
maintenance lock still holds**, and verifies all three baseline hashes;
any failure is a manual recovery HOLD, never a license to restart. Only a
telemetry file added by this operation may be deleted during rollback.

Windows-hosted GitHub CI now exercises the **actual extracted replacement
helper** against synthetic temporary files, verifies original/updated/backup
bytes, injects a downstream failure and restores the original via the same
helper. This is source/runtime compatibility evidence only; CI cannot prove
Owner identity, private task quiescence or real V2 activation on the laptop.
The task is still Disabled following the failed, V1-rollback-verified apply.
Do **not** rerun the old downloaded activation bundle. A new owner-specific
maintenance authorization and verified packaged source are required for a
future retry; CI success alone is not authorization.

The installer deliberately **does not restart** the task or claim V2 live.
The subsequent restart must be separately authorized, and the fresh V2
diagnostic must be read in the **new matching Owner PID**, including real
HTTPS ingress counters, before P3 TV diagnosis resumes. No provider, TV,
TorrServer, ACL, firewall, secret or LAN settings change.

## Why there is no automatic stop here

The older V1 event consumer has no cooperative quiesce protocol. An external
counter snapshot cannot atomically lock out a new P3 signed per-film event.
The Human-reported inactive Vietsub AI and observed zero markers lower the
likelihood of an in-progress job, but **cannot** prove a race-free safe stop.
Owner must approve a maintenance stop separately, with a second immediate
inbox/inflight check and exact-process verification. Do not use a HostOps
`NETWORK_SERVICE` runner to cross into owner-private LOCALAPPDATA.
