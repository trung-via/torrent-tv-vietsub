# Current P2 translation operator guide — Antigravity CLI (2026-11-18)

**Current decision:** [ADR-0010](../../docs/DECISIONS/ADR-0010-p2-owner-cli-provider-gateway.md)
and Draft #173 supersede legacy Gemini Developer API instructions in older
Draft/PoC documents. Those documents remain useful for understanding the
original handoff, not for executing the old paid-model client.

## Exactly one translation backend

- P2 `translator_gateway.py` currently registers **Antigravity** only.
- A signed-in owner Windows account supplies the `agy` CLI session. P2 does
  not read a Gemini Developer API key and has no paid-API fallback.
- The checked-in `translator_profile.json` selects:

  ```json
  {"provider":"antigravity","model":"gemini-4-hydrogen-high","thinking_level":"high"}
  ```

  The Antigravity adapter accepts only aliases whose final `-low`, `-medium`,
  or `-high` segment agrees with `thinking_level`. That is a **local contract
  consistency check**, not proof that the installed CLI offers that alias or
  honors the level. Verify the actual CLI model list/help on the owner's
  Windows laptop before a real request. Do not invent an unverified CLI flag.

## Read-only preparation (no model call)

In a local PowerShell 7 terminal under the **same signed-in Windows user**:

```powershell
agy --version
agy --help
```

Confirm that the installed executable supports the exact source invocation
arguments `--input-format stream-json`, `--output-format stream-json`,
`--json-schema`, `--model`, `--print-timeout` and `--sandbox`. Also confirm
the advertised model alias before attempting any AI invocation. These are
read-only help commands; they do not prove sign-in, quota or service success.

To validate an **already cached**, authorized English SRT without any
OpenSubtitles or Antigravity request:

```powershell
py -3 poc/p2-sub-discovery/owner_vietsub_pipeline.py `
  --cache-filename <64-lowercase-hex>.srt `
  --sha256 <actual-owner-file-sha256> `
  --cues <actual-count>
```

Expected statuses include `P2_CACHED_EN_REVALIDATED=PASS`,
`ANTIGRAVITY_CLI_REQUESTS=0` and `TV_DELIVERY=NOT_RUN`.

## Authorized use — not a live acceptance claim

- Only after verifying installed CLI, owner account/quota, the exact subtitle
  source/media and any old `.inflight` state, a *deliberately* authorized
  cached-EN trial may append `--execute-provider --authorize-cloud-upload`
  to the read-only command above. The optional `--pilot-first-window`
  translates at most the first LEAN120 batch; full-film is the default.
- The separate `lean120_api.py` file-output CLI accepts `--execute-provider`
  with a user-supplied SRT/VTT, opaque media key and an empty output folder.
  It writes private cumulative revisions but **does not deliver to TV**.
- The owner foreground gateway
  `poc/p2-aisub/start_p4_auto_lean120_owner.ps1` requires an existing
  owner-private source manifest/profile, installed P4 TLS pairing and an
  explicit `-AuthorizeCloudTranslation` start. Do not start it to prove a
  source-only PR: a real authenticated TV activation can invoke the model.
- Keep original `.inflight` markers when provider effect is uncertain;
  automatic replays of completed checkpoints do not call the provider again.

## Unknown-effect `.inflight` reconciliation (source-only, not activated)

`hostops/setup/p2-inflight-reconcile-offline.ps1` provides an owner-local
inspection path for a stranded P2 batch. It performs **no modification** by
default, reports only an opaque batch number, marker SHA-256, checkpoint/lock
presence and Owner task/process/inbox counts. It does not read credentials or
emit subtitle text. Use the same interactive Windows account as Owner:

```powershell
pwsh -NoProfile -File .\hostops\setup\p2-inflight-reconcile-offline.ps1
```

If an independently checked provider result cannot be reconstructed and the
owner **explicitly accepts abandoning that one unknown result**, an offline
maintenance mode can preserve the exact marker bytes as
`batch-NNNN.quarantined` and create a `batch-NNNN.abandoned.json` no-retry
receipt. This is **not** evidence that the provider never ran; credits or quota
may already have been consumed. The source worker refuses to translate the
same job fingerprint after a tombstone, while a separately authorized new
job remains possible.

Before any quarantine, separately establish the old provider receipt status.
The operator must disable and stop the exact Owner Scheduled Task and verify
zero Owner Python workers, zero queued inbox events, zero active lock and no
completed checkpoint. The script also requires the actually installed Owner
worker's SHA-256 to match the reviewed source containing the no-retry
tombstone check, and the expected task launcher/principal identity. This
prevents an older Owner build from replaying the job after restart. Quarantine
requires an exact marker SHA-256 and both
`-ApplyQuarantine` and `-AcknowledgeUnknownEffect`. It refuses missing or
multiple markers, invalid marker bytes, concurrent Owner work or destination
collisions. **Never use this while the Owner task is Running.** No script here
stops a service, deletes any marker, retires a key, merges a PR or calls `agy`.

Apply mode remains an **untested Windows-owner deployment action** until a
real owner-session rehearsal verifies the task checks and file receipts; the
reviewed source and offline tests alone do not authorize it on the laptop.

## P2-F3 offline worker upgrade (candidate only)

`hostops/setup/p2-offline-worker-upgrade.ps1` is read-only by default. It
reports the raw SHA-256 of the installed worker and verifies that the reviewed
worker source has the expected canonical UTF-8/LF SHA-256. It does not modify
the Owner task or any P2 in-flight state.

```powershell
pwsh -NoProfile -File .\hostops\setup\p2-offline-worker-upgrade.ps1
```

The *separately authorized* `-InstallOffline -ExpectedInstalledSha256 <SHA>`
mode requires the task to be **Disabled**, all Owner Python workers stopped,
zero queued events and active locks, at most one preserved `.inflight` marker,
verified exact Owner task identity and exact SHA-256 equality with the
previously inspected installed worker. It also checks that all six direct
worker runtime dependencies and the selected Antigravity profile already
match the reviewed source. A stale legacy provider gateway therefore produces
`P2_F3_INSTALLED_GATEWAY_DEPENDENCIES_NOT_READY` with **no changes**; do not
replace only the worker in an incompatible old installation.

For a compatible installation, the script saves the *original bytes* and a
manifest in a unique owner-private backup folder, verifies the backup hash,
then stages and atomically replaces exactly
`app/poc/p2-aisub/automatic_lean120_worker.py`. It verifies installed bytes
again and leaves the Owner Disabled. The backup folder is printed for later
recovery. It neither resets the batch nor executes a provider. The explicitly
requested `-RestoreOffline -BackupFolder <owner-private-folder>` can restore
the original worker while still offline, but refuses rollback **after** any
unknown-effect batch has been quarantined or abandoned, because the old
worker might ignore no-retry tombstones. It preserves displaced bytes.

PowerShell parsing, file/ACL behavior and actual installed dependencies need
Windows owner-session inspection before any apply mode. No PR source or
synthetic unit test constitutes approval to modify an active Owner instance.

## Not proved by this Draft

Actual Windows Antigravity CLI flags/model availability, subscription or
overage pricing, semantic subtitle quality, deployed Owner module identity,
real P4/OMP no-picker acceptance and Redmi on-screen VI are all separate
gates. An Antigravity subscription is **not a guarantee of zero charges**.
Do not upload movie subtitles, Windows secrets or private media identities to
the public repository or CI.
