# P2-AISUB.2h — Brain-owned editorial QA and Human exception-only

**Scope:** Offline source-only validator of a Brain-authored 36-case semantic review. It does not generate scores, call a model or certify linguistic truth.

## Authority / ownership

Human decision 2026-11-08: Brain owns the language assessment and proposed corrections. Human handles only genuinely unresolved character/artistic/product decisions and release, never 36×6 rubric entries. The prior Batch1 Human scores remain separate and unmodified.

The validator reads the original benchmark_synthetic.json corpus, the exact 36-item sanitized Brain export, and the authored Brain review JSON. It validates corpus SHA256, **raw export byte SHA256**, all ordered source English/context/risk/genre/VI bindings, five subjective integer 1–5 dimensions, individual rationales, hallucination uncertainty, priorities and recomputed means. It does **not** independently verify linguistic correctness or reviewer independence.

Review authorship must be AI_BRAIN_AUTHORED_NOT_HUMAN; no_independent_model_review_performed=true; quality_certified=false. Old benchmark36.py and benchmark36_human.py Human-scoring contracts must not be forged or changed.

## Offline use

Save the private Brain review JSON from ChatGPT on the local Windows machine alongside the existing exported file. Use the pinned repo checkout. One long PowerShell command:

    $root = "$env:LOCALAPPDATA\TorrentTVVietsub\Benchmark36"
    $out = Join-Path $root ("brain2h-summary-" + (Get-Date -Format "yyyyMMddHHmmssfff") + ".json")
    python poc/p2-aisub/brain_semantic_review_v2h.py --corpus poc/p2-aisub/benchmark_synthetic.json --export (Join-Path $root "brain36-export-20261108-134358-646152.json") --brain-review (Join-Path $root "p2_aisub_brain36_review_20261108.json") --out $out

A fresh output path is required (no overwrite). Output contains IDs, scores summary, provenance hashes, and exception route codes, NOT original dialogue/translation, filenames, token usage or private Human scorecards.

## Decision and exception route

- AI_EDITORIAL_REVIEWED: Brain authored a single subjective report with no recorded uncertainty.
- CONTEXT_PENDING: missing actor/recipient/title context or uncertain inference; Brain gathers source-grounded metadata and independent critique first.
- exception_candidates: only high-priority unresolved cases, with route BRAIN_CONTEXT_ENRICHMENT_FIRST. These are candidate exceptions, not automatic Human duties.
- HUMAN_EXCEPTION_APPROVED is never emitted by machine; requires a separate real Human decision.
- Independent semantic review remains NOT_PERFORMED until distinctly evidenced.

## Compatibility / strict boundaries

v2a context_engine_v2.py retains explicit source/scene/turn and directed address rules. v2b context_memory_v2b.py retains event provenance and forward-only temporal scope. v2c context_review_v2c.py retains historical *Human* pronoun annotations; Brain scores must not silently be converted to human_reviewed. v2g brain36_context_gate.py remains an independent deterministic readability/context-warning gate.

The 36 synthetic cases have no real timecodes. This tool does not measure real subtitle timing, check media, use OMP/TorrServer/Redmi or alter a player; 2.5s speed assumptions are hypothetical.

## Tests

    python -m unittest discover -s poc/p2-aisub -p "test_brain_semantic_review_v2h.py" -v

No private original translated model text or scores should be committed to GitHub.
