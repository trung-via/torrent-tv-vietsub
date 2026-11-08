# P2-AISUB.2i — Nine-case Brain context challenge (offline gate)

**Issue:** #86. **Status:** SOURCE IMPLEMENTATION; not real translation acceptance.
**Upstream:** merged PR #84 / P2-AISUB.2h. OMP, TorrServer and TV are untouched.

## Why a separate gate
The 36 original synthetic scenes do not contain actual film/episode timestamps.
A Brain-authored subjective review identified 19 `CONTEXT_PENDING` and nine
high-priority cases: **2, 5, 7, 8, 20, 26, 27, 28, 33** (historical source-bound
local observation; not recomputed without the private files). The objective is to
challenge those nine with source-grounded character/relationship facts and to
propose improvements without asking Human to annotate 36×5 rating cells.

This is a **deterministic validator**, not another AI model, not a semantic judge,
not an independent reviewer and not an engine that translates dialogue. Its test
fixtures are fictional; unit/CI PASS cannot certify Vietnamese style or accuracy.

## Work boundary / inputs
The local Windows machine owns the private Brain export, Brain editorial review,
and newly authored context challenge JSON. **Never commit or paste private
translations, file paths or reports to the PUBLIC repository.** A Brain/reviewer
must first inspect the original private translations in an authorized local
session. This script does not access ChatGPT, Antigravity, Gemini, the network,
TorrServer, TV, or Windows service configuration.

Files read:
- `benchmark_synthetic.json`: public original source, pinned LF SHA
  `3e367c1544c2614b44b2a99e6d083ddd61272ab0d773c5410cc9b40914476a31`.
- `--export`: exact user-exported 36 VI items, pinned raw SHA
  `efe7a7fdc518303095cb720469e913087132cb967032163bdd7d3a396587cee4`.
- `--brain-review`: exact previous Brain subjective review; v2h must validate.
- `--challenge`: new private `P2-AISUB.2i-brain-context-challenge-v1` authored after
  source-grounded analysis of the nine prioritized cases.

Each of nine challenge rows is in ascending ID order with the three per-case
UTF-8 SHA256 hashes of source English, selected Vietnamese and previous Brain
reason; explicit `decision`, `route`, `risk_tags`, `evidence_fields`,
`unknowns`, `brain_reason`, optional `candidate_revision`, flags
`recipient_verified`, `independent_review`, `human_approved`,
`quality_certified` and optional `exception_rationale`.

Root manifest must state `authorship=AI_BRAIN_SINGLE_REVIEW`,
`quality_certified=false`, `independent_semantic_review=NOT_PERFORMED`,
`real_timecodes_verified=false`, `human_approval_claimed=false` and the
exact source LF/export/review hashes. See synthetic tests for the strict schema.

**Allowed outcomes**: `CONTEXT_PENDING`, `BRAIN_ASSESSED`, `BLOCKED`.
Routing: `BRAIN_CONTEXT_ENRICHMENT_FIRST`, `INDEPENDENT_REVIEW_PENDING`,
or `HUMAN_EXCEPTION_DECISION` only with an actual Brain assessment, candidate
revision, evidence and explanation. A future Human may choose a creative
trade-off; this tool never claims that Human has approved anything.

**Important:** The original source does *not* establish recipient identity for
all cases. Never mark `recipient_verified=true` based on genre, guessed
gender, speaker labels or `risk_focus`. Explicit `unknowns` are preferable
to invented character facts.

## Local CLI (after private inputs are available and Brain authored challenge)

Run from a pinned checkout of the merged/reviewed branch:

```powershell
$root = Join-Path $env:LOCALAPPDATA 'TorrentTVVietsub\Benchmark36'
python poc/p2-aisub/context_challenge_v2i.py `
  --corpus poc/p2-aisub/benchmark_synthetic.json `
  --export (Join-Path $root 'brain36-export-20261108-134358-646152.json') `
  --brain-review (Join-Path $root 'p2_aisub_brain36_review_20261108.json') `
  --challenge (Join-Path $root 'brain2i-private-challenge.json') `
  --out (Join-Path $root ('brain2i-receipt-' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.json'))
```

The output is an **exclusive-create, redacted receipt** containing case IDs,
risk/unknown codes, routes, decision counts and SHA identities, not the actual
English/VI dialogue, correction candidates or private analysis notes. A
machine-readable `BRAIN_ASSESSED` only proves that a Brain-authored candidate
exists; it does not prove that the candidate is a good translation.

## Acceptance boundary
- **SOURCE / CI:** nine cases strictly bound to one original corpus, original
  exact export, exact previous review and per-case source/VI hashes; negative tests.
- **BRAIN EDITORIAL:** must be separately authored from actual private inputs,
  not synthesized by the deterministic script.
- **INDEPENDENT BILINGUAL:** remains `NOT_PERFORMED` without a distinct, evidenced
  reviewer. The validator must not self-certify independence.
- **HUMAN EXCEPTION:** a genuine explicit Human decision, never emitted by this script.
- **P2-AISUB.3 TIMED SRT / P4 TV:** separate work; no mock/CI result replaces them.

If the source files are unavailable, report `PRIVATE_INPUT_NOT_AVAILABLE` and
stop; do not invent English-to-Vietnamese comparisons or ask Human to score
fictional contexts. The next dependency is secure local Brain review of the nine.
