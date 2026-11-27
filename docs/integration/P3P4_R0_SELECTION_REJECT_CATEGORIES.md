# P3/P4 R0 — classified selection rejection (source-only candidate)

## Reconciled authority and scope, 2026-11-17

- Human decision: [Issue #170](https://github.com/trung-via/torrent-tv-vietsub/issues/170), FLAT, personal single owner, one existing Windows Owner runtime and one on-TV **Bật Vietsub AI** action.
- Source dependency: integrated Draft #162 → #164–#167 → one-tap Draft #168 head `d93504bcd6941c078f230ae14fd4ba3d7988ec65` → Owner V1/V2 attestation Draft #169 head `7851fd46ce006163c5a3db4fd2c8240f1dd89b48`.
- Reported live counters: `P3_HTTPS_STATE_ACCEPTED=352`, `P3_HTTPS_SELECTION_REJECTED=59`, `P3_HTTPS_SELECTION_DISPATCHED=0`, `P3_STATE_FRESH=FRESH_REQUESTED`, `TORRSERVER_READER_READY=TCP_REACHABLE_METADATA_UNTESTED`. These are earlier owner observations, **not** a causal diagnosis and not a new live measurement.
- This R0 candidate changes the existing P3/P4 HTTPS handler's fixed, owner-local counters. No additional endpoint, server, translator, event queue, API, APK, Windows operation, payment or media is introduced.

## Exactly one category for every rejected selection

The existing `selection_rejected` aggregate remains. Each rejection now increments **one** of the following bounded counters, with fixed names and no raw request, filename, hash, secret, IP or error string in the receipt:

| Category | Source gate examples | Next check |
| --- | --- | --- |
| `BAD_WIRE` | Signed TV message invalid/tampered/replayed | Verify signed request and time/replay at paired sender |
| `CURRENT_TV_OR_TORRSERVER_UNAVAILABLE` | Trusted current selection reader failed/incomplete/stale | Verify owner reader and real selected-file metadata |
| `MEDIA_MISMATCH` | TV current film, session, hash or file index differs | Compare authenticated current TV choice with owner TorrServer file |
| `OWNER_POLICY` | Explicit request/rights/owner mode/track policy refused | Read selected-film policy and OFF/OTHER state |
| `ENQUEUE` | Existing owner inbox write failed | Inspect the one owner inbox and its error status locally |
| `HTTP_FORMAT` | Wrong Content-Type/body length/header format | Compare TV HTTP request format to current endpoint contract |
| `UNKNOWN` | Any unexpected or unmapped failure | Inspect sanitized local diagnostics; do not guess cause |

No category is included in the HTTP rejection sent to TV. The original state-rejection counters remain separate. `P3_HTTPS_SELECTION_REJECTED_*` fields are visible only when a new matching Owner PID has actually emitted the fresh private diagnostic.

## Source consistency and runtime safety

- Changed existing `p3_ingress_telemetry.py`, `p3_p4_shared_https_route.py`, `owner_p3_p4_diagnostics.py` with explicit source hashes in the existing staging/activation scripts. Runtime diagnostic identity becomes `P3P4-INTEGRATED-DIAGNOSTIC-V2-R0`. The old V2 file set remains individually recognizable as `V2_PRE_R0_SOURCE_EXACT`, not misreported as the new candidate.
- `Inspect` still reports `LOADED_RUNTIME=NOT_ATTESTED` from disk source alone. `Backup`/`ApplyOffline` still require the exact supported V1 starting point and cannot silently upgrade a running old V2 process. Changing reviewed pins is **not** an installation, restart or authorization to perform it.
- Read-only triage with aggregate rejects but no categories requests a new categorized measurement; multiple accumulated categories require a fresh, isolated one-tap measurement rather than an invented single root cause.
- Synthetic test acceptance: one valid signed current `REQUESTED` enqueues once; Play/Next never enqueues; invalid/replayed/mismatched, OFF/OTHER, failed Owner read or inbox do not enqueue. Keep P4 existing route, signed payload, and private listener unchanged.

## Remaining R0 real acceptance (NOT RUN)

1. Prove installed source vs loaded Owner PID and exact active TV APK/branch version; preserve owner data and current TV app.
2. Verify actual localhost TorrServer `POST /torrents` selected file hash + index + filename; TCP reachability alone is insufficient.
3. After a deliberately authorized, reversible upgrade when the exact installed source is known, observe **new** categorized counters from one signed on-TV `VIEWER_VIETSUB_REQUESTED` for the current film. Exactly one enqueue; OFF/OTHER/duplicates produce none.
4. Separately prove live OpenSubtitles/Gemini and P4 no-picker VI on Redmi, including cumulative 120→240 cues. CI/mock success does not prove these gates.

**Gate:** `SOURCE_IMPLEMENTED / TARGETED_OFFLINE_PASS` is allowed after code/tests. `LIVE_OWNER_PASS`, `LIVE_PROVIDER_PASS`, `REAL_REDMi_PASS`, `MERGED` and `RELEASE_PASS` remain unproven until exact evidence exists.
