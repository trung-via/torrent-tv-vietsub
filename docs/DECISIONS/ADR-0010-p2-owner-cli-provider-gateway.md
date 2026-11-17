# ADR-0010 — P2 owner-account CLI translation provider gateway

Status: **DECIDED BY HUMAN, SOURCE-ONLY CANDIDATE — NOT DEPLOYED** (2026-11-18)

## Decision and scope

The previous assumption that Torrent TV should translate English subtitles by
calling the Gemini Developer API with a separately enrolled key was incorrect.
Human explicitly withdrew that choice: **remove direct paid model API transport**.

The enabled translator is now the owner's existing, signed-in **Antigravity
CLI** on the Windows laptop. The P2-specific interface accepts one LEAN120
window plus a provider-agnostic profile and returns one `id -> Vietnamese text`
mapping. The rest of the chain remains unchanged:

1. OMP sends current selected media to OwnerBridge P3.
2. D1/D2 tries authorized Vietnamese timed text; on EN fallback it uses the
   existing cached/downloaded authorized subtitle.
3. P2 splits into at most 120 target cues / 6,500 characters with read-only
   context, sends a prompt as JSON **via CLI stdin** to `agy`, validates strict
   structured output and saves checkpoints for every batch.
4. Existing P4 signed, progressive LAN revisions remain available to OMP.

The program does **not** call `generativelanguage.googleapis.com`, accept a
`GEMINI_API_KEY`, use a Gemini direct HTTP transport, perform a Developer API
model GET, or fall back to a different billable provider.

**The OpenSubtitles API remains** as a separate service used for searching and
downloading subtitles. This decision removes **model translation API** billing,
not all HTTP networking or Antigravity's own remote model transport.

## Provider-neutral interface and future Codex

`poc/p2-aisub/translator_gateway.py` owns the replaceable backend registry:

```
translate_window(window, profile, glossary) -> dict[cue_id, vi_text]
```

Current registered backend: `antigravity`. A `codex` name is valid in an
editable profile but deliberately **not registered / not runnable**. Adding
Codex later requires one reviewed adapter plus a matching local auth/cost
preflight and explicit registration. Unknown provider, missing CLI, unavailable
personal account and any failed result **stop**, with no implicit fallback.

The active profile is `poc/p2-aisub/translator_profile.json`:

```
{"provider":"antigravity","model":"gemini-4-hydrogen-high","thinking_level":"high"}
```

Changing the model/profile changes the checkpoint job fingerprint. It must
never silently bypass an unfinished earlier provider call.
The Antigravity implementation now rejects a model alias whose final
`-low`, `-medium` or `-high` segment disagrees with the configured
`thinking_level`; it does not silently ignore that setting. This is only a
source-level consistency assertion. Verify actual CLI alias/flag support on
Windows before a live call; no undocumented `--thinking-level` flag is assumed.
The current runnable guide is
[`ANTIGRAVITY-OWNER-CURRENT.md`](../../poc/p2-aisub/ANTIGRAVITY-OWNER-CURRENT.md).

## Account/cost controls

- Run `agy` under the **same interactive Windows user** that signed into
  Antigravity CLI. It uses the owner's cached session, **not** the API key
  previously provided for a different account.
- Before a real request, reject `modelProvider: gemini` (key mode), non-personal
  `auth.type`, ADC configuration, and CI. Remove inherited API/Cloud key
  environment variables in the child process. This is a best-effort config
  check, not a guarantee about external billing or credits.
- Send subtitles only on stdin; never in process arguments, source control or
  error messages. Only approved owner-supplied/cached English text is eligible.
- A CLI timeout or an error with unknown effect keeps the batch `.inflight`.
  No automatic retry until the owner reconciles the previous request.

Antigravity subscription/credit limits and any optional overage charging are
external to the project. **Account authentication does not guarantee zero cost**.
Owner must verify their Antigravity plan and disallow paid overages if desired.

## Deployment and legacy data migration — blocked until reconciliation

Existing laptop evidence supplied by Human before this ADR:

- `R0_PERSONAL_INSTALL=VERIFIED_HASH` and Owner resumed (`PID=19968` then).
- One TV press resulted in `R0_DELTA_SELECTION_DISPATCHED=1`, with zero rejects.
- Following that attempt: `R0_EVENT_BLOCKED=1`, `R0_CLAIM_TOTAL=1`,
  `R0_PROVIDER_INFLIGHT_FILES=1`. These are **historic snapshots**, not a
  current live assertion.

**Do not deploy/restart or retry the translation now.** First inspect the
actual current Owner event/claim/block reason, the `*.inflight` and any matching
`batch-XXXX.json` checkpoint, as well as actual Antigravity owner login. Do not
blindly delete an `*.inflight` or claim to force a second model call. Preserve
the exact event ID/source digest and decide whether it completed or is safe to
abandon. Confirm task stopped/disabled and zero pending work before replacing
installed source. Preserve a copy of installed source for rollback.

For legacy credential removal after that reconciliation, use
`hostops/setup/p2-provider-switch-offline.ps1` **read-only** first. Its optional
`-RetireLegacyGeminiKey` deletes only the exact owner-local
`OwnerBridge\secrets\gemini.dpapi` ciphertext **after** task Disabled, zero Owner
Python process, zero pending events and zero provider inflight. Do not delete
the separately required `opensub.dpapi`.

Then install a reviewed exact source snapshot, verify the running Owner loaded
the new code and the personal Antigravity account, and perform **one** bounded
authorized EN test. Required receipts: `PROVIDER=antigravity`,
`DIRECT_MODEL_API_REQUESTS=0`, one provider invocation per new LEAN120 batch,
checkpoint completion and (separately) real OMP/P4 acceptance. No release or
real-device PASS is inferred from CI mocks.

## Verification in source-only branch

- Offline D2/Owner tests: `python -m unittest discover -s poc/p2-sub-discovery -p 'test_*.py' -q`.
- Offline P2 tests: `python -m unittest discover -s poc/p2-aisub -p 'test_*.py' -q`.
- P4 Kotlin interoperability gate needs `kotlinc` installed. Linux without
  that compiler cannot attest this native gate.
- Inspect legacy direct-model HTTP references in production Python/PS with
  `rg 'generativelanguage.googleapis.com|--execute-api|gemini.dpapi' poc`.

Rollback: keep current installed Owner unchanged while this branch is under
review. Restoring old model-API source after this Human decision is **not**
an authorized fallback; stop translation pending another explicit decision.
