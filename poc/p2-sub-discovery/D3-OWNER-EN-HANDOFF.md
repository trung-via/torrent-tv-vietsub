# D3-A: EN subtitle source → existing P2 verified manifest

Tracking: [D3 Issue #127](https://github.com/trung-via/torrent-tv-vietsub/issues/127).
Candidate stacked on **D1 #122 → D2 #124 → D2.5 #126 → search policy #130**. Existing API
translator and P4 TV transport remain in **Draft #118 and Draft #120**.
This is a source-only **trusted OWNER handoff boundary**, not D3 E2E.

## Why this slice exists

OpenSubtitles `owner_vi_en_trial.py` intentionally uses a synthetic
`owner-fallback-unverified` identity and release metadata. It must NOT be
automatically promoted to the live P2 media map. P2 #118 already knows how
to translate an exact validated private EN source via automatic LEAN120 and
publish cumulative revisions into P4. D3 must only produce the pre-existing
`TTV-P2-OWNER-MATCHED-EN-V1` schema, not a duplicate translator/receiver.

## Required independently trusted evidence

The future owner-local adapter (NOT written by this PR) must record:
- Actual TorrServer profile/torrent hash/file index and selected media;
- Correct opaque active OMP `media.<64hex>` observed after **P4 HMAC** auth;
- One confident, complete D1/D2/D2.5 EN decision with the exact file ID;
- Actual downloaded SRT bytes/cues/hash kept in the owner's private cache;
- Explicit owner confirmation that source/release/synchronization match that
  particular OMP video, and that the intended material is authorized.

A checked box or boolean in `OwnerBinding` is only a **caller attestation**,
NOT proof that a TV handshake, moviehash or real video sync actually occurred.
No backend here creates or signs that evidence. Do not instantiate it
automatically from a release filename, a manual search, untrusted network
data or the synthetic trial script. Until a real proof-producing adapter
exists, classify this as `SOURCE_IMPLEMENTED / REAL_BINDING_NOT_RUN`.

## Behavior of the function

`stage_confirmed_en_manifest(media, route, asset, cached_file, private_root,
binding)` rejects unverified/synthetic media, VI-first and ambiguous routes,
cross-media/file ID, tampered/invalid EN SRT, changed local cache, incomplete
attestations and existing manifests. On a trusted call it creates exactly one
owner-private, non-overwriting JSON file named `verified-en-manifest.json`
using the **same schema** already consumed by #118. It performs no REST API,
model translation, download, ADB, filesystem exploration outside the selected
private root, network listener or background operation.

Before **any** Gemini call, owner separately authorizes source rights and
cloud upload, configures the private model profile (the Thor pilot selected
`gemini-4-hydrogen` / `high`) and local key, then uses **existing #118
`start_p4_auto_lean120_owner.ps1`** in foreground. No global model default
change. Do not post real subtitle contents, local paths, media IDs or secrets
to this PUBLIC repository.

## Explicitly NOT done

- No real TorrServer→OMP binding verifier or OpenSubtitles API call.
- No real P2 Gemini 4 Hydrogen request or semantics/price evidence.
- No D3-VI direct-to-P4 adapter. **VI must never masquerade as EN** to
  bypass #118's EN-only contract.
- No joined source composition with #118 or real Redmi progressive result.
- No merge, install, Windows service, firewall/router or G4 release.

Synthetic offline test command from the stacked #126 source:
`python -m unittest discover -s poc/p2-sub-discovery -p 'test_*.py' -q`.
The tests are source-level only. Rollback by closing the Draft PR; no private
owner file is created until the owner explicitly calls the function locally.

## Search-policy precedence (VI_FAST / EN_DIRECT / VI_FULL)

This D3 revision reconciles the source route from the reviewed VI search
policy in Draft #130. **Do not judge VI authority solely from the isolated
`route.vi.decision.status`**: in `VI_FAST`, an incomplete single VI page may
contain a provisional `VI_MATCH`, but that cannot prove the missing rows lack
a better or conflicting VI candidate. The owner-approved policy chooses to
continue EN in that situation, rather than scanning VI page two.

- `VI_FAST` with `INCOMPLETE` or transient VI `NETWORK_ERROR_FALLBACK` may
  pass a *separately confident* and fully reviewed EN route after all trusted
  binding, source, SRT and owner/sync requirements. `VI_FAST` with
  `COMPLETE` and confident VI still blocks EN.
- `EN_DIRECT` requires `SKIPPED` plus empty VI discovery. This mode skips
  **online VI only**; a verified local/embedded VI track must be checked
  upstream, not by this manifest writer.
- `VI_FULL` requires completed VI coverage with no confident VI winner.
  Unknown/malformed policy or probe states stop before manifest writes.

The owner-private manifest remains **EN-only** and uses the same existing P2
schema `TTV-P2-OWNER-MATCHED-EN-V1`. No new Gemini client or TV receiver is
introduced; #118 and #120 remain the shared consumer branches.
