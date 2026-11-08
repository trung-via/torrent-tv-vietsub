"""P2-AISUB.2h: source-bound Brain editorial review contract, offline.

Validates *authored* AI scoring artifacts against the original synthetic source
and exact exported translations. It DOES NOT assign scores, infer pronouns,
claim independent judgment, or alter the Human rating pipeline.
"""
from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
from statistics import mean
from typing import Any

CORPUS_SCHEMA = "P2-AISUB.2a-original-synthetic-context-v1"
EXPORT_SCHEMA = "P2-AISUB.2f-brain-input-v1"
REVIEW_SCHEMA = "P2-AISUB.2f-brain-editorial-score-v1"
REPORT_SCHEMA = "P2-AISUB.2h-brain-reviewed-contract-v1"
DIMENSIONS = ("semantic_accuracy", "vietnamese_naturalness",
              "relationship_pronouns", "tone_register", "subtitle_readability")
MAX_BYTES = 350_000


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for k, v in pairs:
        if k in result:
            raise ValueError("BRAIN2H_DUPLICATE_JSON_KEY")
        result[k] = v
    return result


def _no_constant(_value: str) -> Any:
    raise ValueError("BRAIN2H_NONFINITE_JSON_VALUE")


def _load(path: Path) -> tuple[bytes, Any]:
    raw = path.read_bytes()
    if not 0 < len(raw) <= MAX_BYTES:
        raise ValueError("BRAIN2H_INPUT_SIZE_INVALID")
    try:
        obj = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=_unique_pairs,
                         parse_constant=_no_constant)
    except (UnicodeError, json.JSONDecodeError) as e:
        raise ValueError("BRAIN2H_INPUT_UTF8_JSON_INVALID") from e
    return raw, obj


def _plain(value: Any, *, max_chars: int = 3000) -> bool:
    return (isinstance(value, str) and bool(value.strip()) and
            len(value) <= max_chars and not any(ch in value for ch in ("\x00", "\r", "<", ">")))


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def verify(corpus_raw: bytes, corpus: Any,
           export_raw: bytes, exported: Any,
           review_raw: bytes, reviewed: Any) -> dict[str, Any]:
    """Return metadata and statistics without copying private translations."""
    sha = hashlib.sha256(corpus_raw).hexdigest()
    _require(isinstance(corpus, dict) and corpus.get("corpus") == CORPUS_SCHEMA,
             "BRAIN2H_CORPUS_INVALID")
    cases = corpus.get("cases")
    _require(isinstance(cases, list) and len(cases) == 36, "BRAIN2H_CORPUS_COUNT")
    for i, case in enumerate(cases, 1):
        _require(isinstance(case, dict) and type(case.get("id")) is int and case["id"] == i and
                 all(_plain(case.get(k)) for k in (
                     "genre", "scene_context", "source_english", "risk_focus", "speaker")),
                 "BRAIN2H_CORPUS_CASE_INVALID")

    _require(isinstance(exported, dict) and exported.get("schema") == EXPORT_SCHEMA and
             exported.get("corpus_sha256") == sha and
             exported.get("blind_label") == "A" and
             exported.get("machine_readability_not_semantic_pass") is True,
             "BRAIN2H_EXPORT_SOURCE_OR_SCHEMA_MISMATCH")
    translations = exported.get("translations")
    _require(isinstance(translations, list) and len(translations) == 36,
             "BRAIN2H_EXPORT_COUNT_INVALID")
    for i, row in enumerate(translations, 1):
        _require(isinstance(row, dict) and set(row) == {"id", "vi"} and
                 type(row.get("id")) is int and row["id"] == i and
                 _plain(row.get("vi")), "BRAIN2H_EXPORT_CASE_INVALID")

    _require(isinstance(reviewed, dict) and reviewed.get("schema") == REVIEW_SCHEMA and
             reviewed.get("source_corpus_sha256") == sha and
             reviewed.get("input_export_sha256") == hashlib.sha256(export_raw).hexdigest() and
             reviewed.get("input_blind_label") == "A" and
             reviewed.get("input_schema") == EXPORT_SCHEMA,
             "BRAIN2H_REVIEW_SOURCE_MISMATCH")
    _require(reviewed.get("authorship") == "AI_BRAIN_AUTHORED_NOT_HUMAN" and
             reviewed.get("ratings_are_subjective") is True and
             reviewed.get("quality_certified") is False and
             reviewed.get("no_independent_model_review_performed") is True,
             "BRAIN2H_REVIEW_PROVENANCE_OR_CERTIFICATION_INVALID")
    rows = reviewed.get("case_reviews")
    _require(isinstance(rows, list) and len(rows) == 36,
             "BRAIN2H_REVIEW_COUNT_INVALID")

    totals: dict[str, list[int]] = defaultdict(list)
    genres: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(list))
    hallucinations: Counter[str] = Counter()
    priorities: Counter[str] = Counter()
    statuses: Counter[str] = Counter()
    exceptions: list[dict[str, Any]] = []
    reviewed_ids: list[int] = []

    for i, (source, translated, row) in enumerate(zip(cases, translations, rows), 1):
        _require(isinstance(row, dict) and type(row.get("id")) is int and row["id"] == i,
                 "BRAIN2H_REVIEW_ID_OR_ORDER_INVALID")
        for key, expected in (("genre", source["genre"]), ("scene_context", source["scene_context"]),
                              ("risk_focus", source["risk_focus"]), ("english", source["source_english"]),
                              ("vietnamese", translated["vi"])):
            _require(row.get(key) == expected, "BRAIN2H_REVIEW_CASE_BINDING_MISMATCH")
        scores = row.get("scores")
        _require(isinstance(scores, dict) and set(scores) == set(DIMENSIONS) and
                 all(type(scores[k]) is int and 1 <= scores[k] <= 5 for k in DIMENSIONS),
                 "BRAIN2H_REVIEW_SCORES_INVALID")
        h = row.get("hallucination_assessment")
        priority = row.get("priority")
        _require(h in ("true", "false", "uncertain") and
                 priority in ("high", "medium", "low") and
                 _plain(row.get("brain_reason")) and
                 _plain(row.get("suggested_revision")) and
                 isinstance(row.get("unresolved_context"), str) and
                 len(row["unresolved_context"]) <= 3000,
                 "BRAIN2H_REVIEW_DETAIL_INVALID")
        _require(isinstance(row.get("hypothetical_readability"), dict) and
                 row["hypothetical_readability"].get("real_timestamps_supplied") is False,
                 "BRAIN2H_REVIEW_TIMING_CLAIM_INVALID")
        for k in DIMENSIONS:
            totals[k].append(scores[k])
            genres[source["genre"]][k].append(scores[k])
        hallucinations[h] += 1
        priorities[priority] += 1
        reviewed_ids.append(i)

        context_pending = bool(row["unresolved_context"].strip()) or h == "uncertain"
        statuses["CONTEXT_PENDING" if context_pending else "AI_EDITORIAL_REVIEWED"] += 1
        # An advisory handoff, never an automatic Human obligation. Brain first
        # attempts metadata retrieval or independent source-grounded critique.
        if priority == "high" and context_pending:
            exceptions.append({
                "id": i, "genre": source["genre"], "reason": "HIGH_PRIORITY_CONTEXT_AMBIGUITY",
                "route": "BRAIN_CONTEXT_ENRICHMENT_FIRST",
                "human_decision_only_if_still_unresolved": True
            })

    # A mismatched authored summary cannot silently propagate into later reports.
    summary = reviewed.get("summary")
    _require(isinstance(summary, dict) and summary.get("total") == 36 and
             summary.get("quality_certified") is False and
             summary.get("all_ids_covered") is True,
             "BRAIN2H_REVIEW_SUMMARY_INVALID")
    for k in DIMENSIONS:
        actual = round(mean(totals[k]), 3)
        _require(abs(float(summary.get("score_means", {}).get(k, -1)) - actual) < 0.001,
                 "BRAIN2H_REVIEW_SUMMARY_TAMPERED")
    _require(summary.get("hallucination_assessment_counts", {}) == dict(hallucinations) and
             summary.get("priority_counts", {}) == dict(priorities),
             "BRAIN2H_REVIEW_AGGREGATE_TAMPERED")

    return {
        "schema": REPORT_SCHEMA,
        "source_corpus_sha256": sha,
        "input_export_sha256": hashlib.sha256(export_raw).hexdigest(),
        "input_review_sha256": hashlib.sha256(review_raw).hexdigest(),
        "reviewed_cases": len(reviewed_ids),
        "review_owner": "AI_BRAIN",
        "review_type": "SINGLE_SUBJECTIVE_EDITORIAL",
        "legacy_human_scores_unchanged": True,
        "independent_semantic_review": "NOT_PERFORMED",
        "real_timecodes_verified": False,
        "semantic_quality_certified": False,
        "quality_certified": False,
        "score_means": {k: round(mean(totals[k]), 3) for k in DIMENSIONS},
        "by_genre": {g: {"n": len(scores[DIMENSIONS[0]]),
                         "score_means": {k: round(mean(scores[k]), 3) for k in DIMENSIONS}}
                     for g, scores in sorted(genres.items())},
        "hallucination_assessment_counts": dict(hallucinations),
        "priority_counts": dict(priorities),
        "status_counts": dict(statuses),
        "exception_candidates": exceptions,
        "handoff_policy": "BRAIN_ENRICH_OR_INDEPENDENT_REVIEW_BEFORE_HUMAN_EXCEPTION",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify Brain-authored 36-case review OFFLINE; never score or upload")
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--export", type=Path, required=True)
    parser.add_argument("--brain-review", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="create new only; never overwrite")
    a = parser.parse_args()
    source, cases = _load(a.corpus)
    exported_raw, exported = _load(a.export)
    review_raw, review = _load(a.brain_review)
    report = verify(source, cases, exported_raw, exported, review_raw, review)
    with a.out.open("x", encoding="utf-8", newline="\n") as f:
        json.dump(report, f, ensure_ascii=False, indent=2, allow_nan=False)
        f.write("\n")
    print("P2_AISUB_BRAIN2H_VERIFIED cases=36 owner=AI_BRAIN quality_certified=False no_model_call")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
