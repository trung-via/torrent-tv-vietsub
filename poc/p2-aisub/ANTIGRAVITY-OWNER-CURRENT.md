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

## Not proved by this Draft

Actual Windows Antigravity CLI flags/model availability, subscription or
overage pricing, semantic subtitle quality, deployed Owner module identity,
real P4/OMP no-picker acceptance and Redmi on-screen VI are all separate
gates. An Antigravity subscription is **not a guarantee of zero charges**.
Do not upload movie subtitles, Windows secrets or private media identities to
the public repository or CI.
