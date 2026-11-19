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
