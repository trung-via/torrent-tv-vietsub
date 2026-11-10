# P2-AISUB — Thor Brain v0.4 blinded bilingual semantic score gate (source-only)

Status: **REVIEW TOOL READY, INDEPENDENT SCORES NOT SUBMITTED, V0.4 NOT PROMOTED**.

## Scope / boundary

`blind_semantic_gate.py` is Python-stdlib-only tooling for the **90-ID / 270-rating, source-pinned** Thor experiment. It validates a PRIVATE, anonymous A/B/C scoring sheet and PRIVATE reviewer JSON; optional unblinding gives **sanitized aggregate score counts only**. It does **not** grade translations, call ChatGPT/Gemini, authenticate human identity, publish media, accept a faster model, change plugin default, or control any TV / Windows host. Source SHA-256 and three 160-cue window ranges are pinned; this version is intentionally not a general benchmark for arbitrary films.

**Inputs are owner-private**: the user-supplied original timed text, bilingual blind sheet, unblinding key, reviewer submissions and candidate subtitle patches must never enter the repository, PR comments, CI logs or GitHub artifacts. Only this source-only script, synthetic tests and process document belong on GitHub.

## Expected private assets

- 90 chosen original source IDs, **30 each** from W01 `181–340`, W02 `561–720`, W03 `1081–1240` on a single SHA-pinned English source (1,761 total original cues).
- An owner-pinned anonymous sheet JSON in schema `torrent-tv-v04-blind-90-v1`, with exactly 90 ordered unique ID rows, original source English, timestamps and masked A/B/C Vietnamese alternatives (270 entries total). A/B/C mapping changes by window.
- A reviewer-filled score JSON, scaffolded by `prepare`, schema `torrent-tv-v04-blind-review-score-v1`, with one score 0/1/2/3/? for every anonymized candidate, 2/3/? accompanied by a note, reviewer ID/qualification/date/method and a truthfully made nonexposure declaration.
- The ORIGINAL private mapping **must not** be provided to a reviewer. The unblinding command accepts it only when the scores are complete and pinned to the same masked-sheet SHA.

## CLI (paths are PRIVATE examples; not CI commands)

```console
python blind_semantic_gate.py prepare --blind PRIVATE_BLIND_SHEET.json --scores PRIVATE_BLANK_SCORES.json
python blind_semantic_gate.py validate --blind PRIVATE_BLIND_SHEET.json --scores PRIVATE_COMPLETED_SCORES.json --expected-blind-sha OWNER_PINNED_MASKED_SHEET_SHA256 --out PRIVATE_VALIDATION_RECEIPT.json
python blind_semantic_gate.py unblind --blind PRIVATE_BLIND_SHEET.json --scores PRIVATE_COMPLETED_SCORES.json --expected-blind-sha OWNER_PINNED_MASKED_SHEET_SHA256 --key OWNER_PRIVATE_UNBLIND_MAP.json --out PRIVATE_SANITIZED_SCORE_COUNTS.json
```

- `validate` can return `INCOMPLETE`; its `reviewer_attestation=DECLARED_NOT_INDEPENDENTLY_VERIFIED` is **not** proof of independent review, identity, authority or competence.
- `unblind` fails closed until all 270 scores are complete, exact 90 IDs and SHA match; invalid label mappings and unannotated high-risk scores are rejected.
- Low severity scores **do not** imply whole-film semantic PASS because the sample is risk-enriched and only 90 of 1,761 cues were reviewed.
- A scoring result cannot alone authorize promotion: blind assessment, adjudicated corrections and repeatedly measured quality-adjusted total wall times with at least 20% improvement over FAST120 remain separate gates.

## Unit tests

```console
python -m unittest -v test_blind_semantic_gate
```

20 synthetic tests cover exact source/sheet/ID pins, missing values, spoofed reviewer mode declarations, corrupt/changed rows, wrong mappings and withheld-until-complete unblinding. All test dialogue is synthetic; the real Thor translations are not included.

**Default remains Brain v0.3.5 FAST120**; Gemini is not invoked, original VI on Redmi is untouched, and G4 is not planned.
