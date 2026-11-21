# Owner P2 batch-0015 fresh-start transaction — review/operation handoff

Status: **DRAFT, NOT ENROLLED OR EXECUTED** until a signed-in Owner runs the
one-time enrollment and the pinned HostOps task is explicitly dispatched.
This is a Windows Owner job, **not** an OMP/Android APK patch.

## Observed evidence (2026-11-21)

- Read-only HostOps run `44881471259`: Owner Running, TV `FRESH_OFF`.
- P2 `UNKNOWN_EFFECT_HOLD`, `batch-0015`, one `.inflight`, `active.lock=YES`,
  checkpoint 15 absent, and one pending event.
- P2 marker SHA-256 `4158f5ac6b0922e2eb58b5c1ecf5e5d40c85a6e69bb484e579c242c517478ab5`.
- The previously installed R2/P4 source patch and PowerShell 7 HostOps are
  verified separately. There is no provider-result or TV-render acceptance.

## Scope of this transaction

1. Require signed-in Windows Owner, PowerShell 7, original Owner Task identity,
   a fresh TV-OFF snapshot, exact marker hash/schema, and installed no-retry
   worker blob. The single pending V3 event must match a prior blocked event
   for the same private media identity. No private media name, ID, or subtitle
   text is copied into the repo or HostOps logs.
2. Create a one-attempt receipt. Disable/stop the original Owner Task; verify
   no Owner worker remains. Revalidate all P2 and event preconditions.
3. Move (do not delete) that complete P2 job folder to Owner-private
   `P2/recovery`, and move the one unclaimed pending event to Owner-private
   `OwnerBridge/recovery`. Keep old blocked events/claims untouched.
4. Verify the live P2 worker tree contains no `.inflight` or `active.lock`,
   and the inbox contains no pending event. Restart Owner and check a fresh
   READY heartbeat with a *new* PID.
5. A successful cleanup does **not** request provider translation or TV
   playback. A subsequent explicit **Bật Vietsub AI** on the current movie
   creates a new task with no old P2 checkpoints. Backend usage/cost is
   separately gated by that on-TV user request.

Failure after stop leaves Owner **DISABLED**, and the transaction must not be
retried. Inspect the private archive and receipt with the Owner before any
manual recovery. Do not re-trigger the old `R2-Checkpoint-Apply` task.

## Deployment handoff

1. Review the exact new branch/PR and PowerShell 7 syntax source check.
2. The signed-in Windows Owner may download the exact-commit enrollment script
   and helper, **verify the enrollment script checksum independently**, then
   run `pwsh -NoProfile -File <verified-enrollment-script> -Enroll -SourceCommit <reviewed-40-hex-commit>`.
   Enrollment creates a no-trigger Task and has **no P2 state side effect**.
3. The owner-authorized HostOps comment
   `/tv-hostops run <reviewed-40-hex-commit> owner-p2-batch15-fresh-start-dispatch`
   triggers exactly one execution and reads only a sanitized receipt.
4. Afterwards run fresh `owner-diagnostic-capture` and verify Owner RUNNING,
   P2 `CLEAR`, `inflight=0`, `pending=0`; then solicit a new on-TV user request
   and independently inspect real 120→240→final P4/Redmi evidence.

Rollback is **recoverable archive + manual Owner assessment**, not automatic
provider replay. The Windows HostOps service must never read Owner-private
job files, and this code must never be run under NETWORK_SERVICE.
