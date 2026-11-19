# R2 — Owner P2 LEAN120 to existing P4 rolling source candidate

Status: **SOURCE_ONLY** on Draft PR #175; no Windows Owner/Redmi/provider
deployment or release is implied by these files or their offline tests.

## Single existing pipeline

1. P3 authenticated per-film `VIEWER_VIETSUB_REQUESTED` enqueues the same V3
   owner event. Legacy P2 no-retry claims and unknown-effect quarantine stay
   unchanged.
2. Verified V3 checks live signed TV, Owner-local TorrServer selected media,
   owner consent, VI inventory and exact session **before** the existing
   `AutomaticVietsubFlow` starts discovery or translation.
3. VI-fast sources still register their completed cached output through the
   original `P3OwnerReadyRegistry`/`VerifiedVietsubReady` path.
4. For EN, the original `AutomaticLean120Worker` and checkpoint files are
   reused. An R2 subclass wraps its existing revision callback without
   changing the pinned F6 source. **After** each committed 120-cue batch,
   Owner rechecks current media/session and cached EN source, verifies the
   cumulative VI cue/timeline/hash, and publishes to the **same** P4 signer.
5. P4 `/p4/activate` may succeed after the first verified batch, not after
   `vi-final.srt`. It creates the existing signed `SessionRevisionFeed` and
   gives the TV its existing source digest/session key. Subsequent 240/360…
   revisions update that feed. A later activation can subscribe to the latest
   already committed cumulative revision without invoking P2 again.

The P2 internal `media.<digest>` is deliberately different from the P4
exact-file media key. The R2 registry independently verifies the source and
rebinds **only the signed delivery envelope**, never its subtitle payload,
to the actual P4 key derived from the authenticated TorrServer identity.

## Failure and regression contracts

- OFF/OTHER, closed/changed TV, wrong selected TorrServer file or changed
  owner-private EN cache: **no new P4 publication**.
- P4 delivery error after a P2 checkpoint: preserve completed P2 work and
  **never retry a quota-bearing model call just to deliver subtitles**.
- A provider failure or uncertain `*.inflight`: retain the original P2
  `NO_RETRY`/manual-reconciliation behavior; no clearing or automatic replay.
- V2 SHA-pinned Owner route/policy/wiring and F6 worker/helper remain
  unmodified. R2 selects additive modules through the next Owner entrypoint.
- No new endpoint, HTTP listener, TV picker, translator or provider.

## Source checks and physical rollout

Run only offline Python tests for the new rolling contract, existing P3/P4
integration and pinned-script regression. The synthetic 120→240/125 test
requires exactly two model **mock** windows and observes a P4 feed before
the full-film `vi-final.srt` exists. This is **not** evidence of real
Antigravity/Redmi subtitle delivery.

For a controlled Owner upgrade on Windows, first prove the installed module
hashes, Owner Scheduled Task/PID, no active provider job/lock, and legacy P2
unknown-effect preservation from an independently authorized read-only
HostOps receipt. Stage the exact new modules privately with rollback; never
run generic repo copies on a live Owner. A real test requires the user's
single button press on Redmi plus sanitized HostOps P3→Owner→P2→P4 counters,
first VI cue visible, continued 120→240 and seek/OFF/media-change checks.

Rollback: restore the prior reviewed Owner entrypoint/wiring, without
deleting private P2 checkpoints or restarting uncertain work. Android APK
reinstallation is not required for this Python-only source candidate; actual
TV compatibility still requires device evidence.

## Reusable HostOps → interactive Owner release staging (source candidate)

The owner's 2026-11-20 approval permits **one-time enrollment** of a fixed
`TorrentTV-Vietsub-Owner-Release-Stage` Scheduled Task. This is deliberately
distinct from `OwnerAgent` and the already enrolled read-only diagnostic
capture task. No existing task action, runtime/PID or private P2 data is
modified by merely enrolling it.

- `hostops/setup/enroll-owner-release-stage.ps1` is run **once** by the signed-in
  Windows Owner. Its `-Enroll -SourceCommit <exact-reviewed-40hex-SHA>` mode
  downloads `owner-release-stage-helper.ps1`, verifies the immutable pinned
  helper SHA-256, registers a no-trigger/`IgnoreNew` limited-interactive task,
  and grants `NETWORK_SERVICE` read+execute on **that task only**. Its only
  file write permission is in a bounded **ProgramData request** folder; a
  separate sanitized receipt folder is **read-only** for the service. It
  never grants the service `LOCALAPPDATA` access. Default mode inspects;
  `-Revoke` unregisters only this task, preserving the private stage.
- A trusted owner-authored Issue #82 comment with exact branch-tip SHA for
  `owner-release-stage-dispatch` runs the fixed HostOps job. It validates the
  task/runner identity, pins the exact Git source commit, stages a short
  ProgramData request and triggers the Owner release task **once**. It never
  starts/stops the main OwnerAgent. A matching sanitized Owner receipt is
  required before it reports `STAGED_VERIFIED_INSTALLED_UNCHANGED`.
- The fixed Owner helper downloads a narrowly scoped manifest and at most 32
  `.py` modules from **that exact commit**, validates manifest and file SHA-256,
  request age and identity, and copies them only into an Owner-private
  `staged-releases` folder. Repeated exact bytes are idempotent; changed
  pre-existing staged bytes cause HOLD. Its accepted manifest mode is
  **`STAGE_ONLY`**. It does not replace installed app files, call providers,
  touch TV/APK or restart Owner.
- The initial exact R2 candidate is
  `hostops/releases/owner-r2-stage-v1.json`: 14 additive/replacement modules
  with hashes from PR #175 R2 reviewed source tree
  `b9e42ef91be1c5c347f418e4e4a6133e2a963366`. The generic task may stage
  a future separately reviewed exact-SHA Python manifest with the same schema
  without further enrollment. It does **not** grant automatic permission to
  install or execute an arbitrary new release.

**Hard rollout boundary:** staging is only phase one. Replacing installed
Owner files still requires a separate, reviewed Owner-context **offline apply**
with exact installed baseline hashes, pending/inflight/active-provider guards,
stopped/disabled task verification, private backup and rollback. The R2
`STAGE_ONLY` receipt is **not** an Owner R2 activation or a real TV PASS.
After staging/controlled apply, a physical Redmi button press and actual P3→P2→P4
receipt remain required.

## Offline R2 apply — source candidate (not enrolled or run)

The new hostops/setup/owner-r2-release-offline-apply.ps1 adds a narrowly scoped
Owner-interactive -ApplyOffline file transition; without the switch it only
inspects the 14 staged hashes, destination types and original task identity.
It pins the successful R2 stage commit and every staged Python SHA. It does
not use arbitrary user-supplied paths or execute repository Python.

The offline mode requires the **main** Owner Scheduled Task already disabled
and every Owner Python process stopped, with zero private pending event,
batch-*.inflight or active.lock. It captures actual prior bytes for all
existing destinations into an Owner-private recovery directory, records
missing destination paths, and verifies every backup before replacing
anything. Existing modules use same-directory atomic replacement; new modules
are atomically moved. Each new installed hash is verified; any failure attempts
reverse restoration with exact original hashes while Owner stays disabled.
It never deletes checkpoints or ambiguous no-retry markers.

This is deliberately **source-only** until a separate fixed Owner-context
maintenance task is enrolled and guarded HostOps orchestration is reviewed.
The existing HostOps release-stage helper remains immutable and STAGE_ONLY;
the service runner cannot apply this script using its current permissions.
The offline script itself never stops, enables or starts Owner, invokes
OpenSubtitles/Gemini, or touches Redmi. A verified stopped/installed Owner still
requires a separately controlled startup and fresh heartbeat/TV proof.
The same reviewed script also has an explicit -RollbackOffline -BackupId
mode: it checks every installed R2 byte and the exact Owner-private pre-R2
ledger/backup before reversing all 14 paths while the Owner remains disabled.
Files originally absent are removed only if they still match this release.
The rollback never starts Owner or touches the P2 provider/checkpoints.

## One-time interactive R2 activation entrypoint (source candidate)

The Owner-only hostops/setup/owner-r2-maintenance-once.ps1 is a convenience
entrypoint when reusable HostOps STAGE_ONLY access cannot replace installed
files. It pins/downloads the exact offline applier (SHA-256), defaults to
inspect-only and requires explicit -ApplyR2 to transition a Windows Owner.
It checks Owner task identity and absence of pending/inflight/active P2 jobs
before disabling/stopping the main task, then runs the guarded offline apply
and restarts the main Owner. It requires a fresh READY heartbeat with a new
PID. If new startup fails, it stops Owner again, verifies and restores the
original source via -RollbackOffline, then attempts to restart the old Owner.
An uncertain file transition or rollback leaves Owner stopped for recovery.

The task has not been run on the real PC, and the one-time entrypoint is not
a HostOps service privilege grant. It must pass Windows source parsing and
be explicitly invoked by the interactive Owner in a maintenance window;
real P3/P2/P4 and Redmi subtitle acceptance remain separate gates.

If the Windows Scheduler stops its PowerShell task but leaves an Owner Python
child alive, the entrypoint may terminate only a bounded set (at most four)
of exact-path, same-owner-SID, same-PID/creation-time Owner Python workers.
It first rechecks that the Owner task is Disabled and that no pending P3
event, uncertain P2 batch or active P2 lock exists. Any unverified process
causes HOLD with no deletion, replay or file installation. The explicit
-ApplyR2 -ResumeAfterStoppedTaskHold mode accepts an already-Disabled task
only after the previous reported pre-apply hold, with no R2 recovery backup
yet present; it must never silently resume a partial install. This mode
addresses the supervised Windows HOLD of 2026-11-20, before any APPLY.
