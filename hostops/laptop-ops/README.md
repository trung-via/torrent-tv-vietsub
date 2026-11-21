# Laptop HostOps: one Owner session transport, routine source-pinned actions

This is the first implementable slice of the 2026-11-21 Human decision to
delegate ordinary PC operations to HostOps, while retaining personal approval
for four sensitive groups. It is **not** proof of installation or permission
on Windows. Issue #82 remains the owner-authenticated HostOps entrypoint.

## Routine by default

- Software maintenance, user-owned files, dev/test, app build, logs, diagnostics,
  safe Task/process control, local TorrServer/P2/P3/P4/Redmi inspection.
- Owner-context operations run as the logged-in owner with **Limited** runlevel;
  the existing NETWORK_SERVICE runner is a transport, not an admin shell.
- An operation must be an exact-commit script under
  `hostops/laptop-ops/operations/` with its SHA-256 in a checked-in manifest;
  the owner helper downloads the exact bytes, verifies them and logs full
  stdout/stderr in owner-private storage. The runner sees only fixed status.
- Adding another routine operation means adding a manifest and source-pinned
  script on the trusted branch. No re-enrollment of the fixed helper is needed.
  A public issue comment cannot inject commands, paths or arguments.

## Never automatically delegated (four Human-approved exceptions)

1. Passwords, credentials, private keys and account/login changes.
2. Payments, financial transactions or previously unapproved spending.
3. Irrecoverable deletion or transmission of private Owner data to an external
   recipient.
4. Admin/security privilege changes, operating-system protections, or exposing
   private services to the Internet.

These categories are rejected by the routine operation contract. Do not
mislabel a sensitive script as routine to bypass this requirement. The helper
is not a comprehensive static analyzer of PowerShell: the owner-authenticated
source PR review remains necessary for each new operation. Paid provider
requests, replaying ambiguous P2 batches and TV installation are **not**
included in the inaugural operation.

## Installation and recovery

The interactive Owner registers one reusable `TorrentTV-Vietsub-Laptop-HostOps`
task using `hostops/setup/enroll-owner-laptop-ops.ps1 -Enroll` with a pinned
helper SHA-256 and commit. The task has no trigger; NETWORK_SERVICE only gets
read/execute on that task and ProgramData request-write/receipt-read. Owner
Agent's existing task and private data are unaffected by enrollment.

Trusted `/tv-hostops run <commit> owner-laptop-ops-dispatch` can then dispatch
a manifest from the exact HostOps branch. The first action is the existing
guarded Owner full diagnostics installer; it checks idle work, hashes three
modules, backs up originals and rolls back on failure. It does not replay
P2 jobs. Failure produces a private full log and a public-safe receipt.

This bridge initially supports Torrent TV's own HostOps channel. Other
projects require their own authenticated dispatch routes and explicit source
ownership; it does not borrow AI Commerce credentials or runner identity.
