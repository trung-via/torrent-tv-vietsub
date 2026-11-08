"""P2-AISUB.2i: local, source-bound contextual challenge handoff.

This checks provenance and completeness of Brain-authored assessments. It is
NOT a language model, independent bilingual reviewer or subtitle certification.
Private translation/review/challenge contents must never be pushed to GitHub.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
from typing import Any

from brain_semantic_review_v2h import _load, verify as verify_v2h

SCHEMA = "P2-AISUB.2i-brain-context-challenge-v1"
REPORT_SCHEMA = "P2-AISUB.2i-challenge-receipt-v1"
ORIGINAL_EXPORT_SHA256 = "efe7a7fdc518303095cb720469e913087132cb967032163bdd7d3a396587cee4"
TARGET_IDS = (2, 5, 7, 8, 20, 26, 27, 28, 33)
SOURCE_FIELDS = frozenset(("genre", "scene_context", "speaker", "source_english", "risk_focus"))
RISK_TAGS = frozenset((
    "MEANING", "PRONOUN", "RELATIONSHIP", "HONORIFIC",
    "REGISTER", "TONE", "HALLUCINATION", "READABILITY", "UNKNOWN_RECIPIENT"
))
UNKNOWN_CODES = frozenset((
    "RECIPIENT", "RELATIONSHIP", "AGE", "HONORIFIC",
    "INTENT", "SCENE_CONTINUITY", "OTHER"
))
DECISIONS = frozenset(("BRAIN_ASSESSED", "CONTEXT_PENDING", "BLOCKED"))
ROUTES = frozenset((
    "BRAIN_CONTEXT_ENRICHMENT_FIRST",
    "INDEPENDENT_REVIEW_PENDING",
    "HUMAN_EXCEPTION_DECISION"
))


def _require(ok: bool, code: str) -> None:
    if not ok:
        raise ValueError(code)


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _text(value: Any, *, cap: int = 1600) -> bool:
    return (isinstance(value, str) and 0 < len(value.strip()) <= cap and
            not any(c in value for c in ("\x00", "\r", "<", ">")))


def _code_list(value: Any, allowed: frozenset[str], *, allow_empty: bool = False) -> bool:
    return (isinstance(value, list) and
            (bool(value) or allow_empty) and
            len(value) <= len(allowed) and
            len(value) == len(set(map(str, value))) and
            all(isinstance(item, str) and item in allowed for item in value))


def validate(corpus_raw: bytes, corpus: Any, export_raw: bytes, exported: Any,
             review_raw: bytes, reviewed: Any, challenge_raw: bytes,
             challenge: Any, *, enforce_original: bool = True) -> dict[str, Any]:
    """Validate the private Brain handoff; publish only a redacted receipt."""
    upstream = verify_v2h(corpus_raw, corpus, export_raw, exported,
                          review_raw, reviewed,
                          require_original_source=enforce_original)
    if enforce_original:
        _require(_sha(export_raw) == ORIGINAL_EXPORT_SHA256,
                 "BRAIN2I_ORIGINAL_EXPORT_PIN_MISMATCH")
    expected = tuple(entry["id"] for entry in upstream["exception_candidates"])
    _require(expected == TARGET_IDS, "BRAIN2I_PRIOR_EXCEPTION_SET_CHANGED")
    _require(isinstance(challenge, dict) and challenge.get("schema") == SCHEMA,
             "BRAIN2I_SCHEMA_INVALID")
    _require(challenge.get("authorship") == "AI_BRAIN_SINGLE_REVIEW" and
             challenge.get("quality_certified") is False and
             challenge.get("independent_semantic_review") == "NOT_PERFORMED" and
             challenge.get("real_timecodes_verified") is False and
             challenge.get("human_approval_claimed") is False,
             "BRAIN2I_PROVENANCE_OR_FALSE_PASS")
    _require(challenge.get("source_corpus_canonical_lf_sha256") ==
             upstream["source_corpus_canonical_lf_sha256"] and
             challenge.get("input_export_sha256") == _sha(export_raw) and
             challenge.get("input_review_sha256") == _sha(review_raw),
             "BRAIN2I_SOURCE_IDENTITY_MISMATCH")
    rows = challenge.get("case_challenges")
    _require(isinstance(rows, list) and len(rows) == len(TARGET_IDS),
             "BRAIN2I_CHALLENGE_COUNT")
    receipt_rows = []
    decisions: Counter[str] = Counter()
    routes: Counter[str] = Counter()
    for expected_id, row in zip(TARGET_IDS, rows):
        _require(isinstance(row, dict) and type(row.get("id")) is int and
                 row["id"] == expected_id, "BRAIN2I_ID_ORDER_MISMATCH")
        idx = expected_id - 1
        source, translated, prior = (
            corpus["cases"][idx], exported["translations"][idx], reviewed["case_reviews"][idx]
        )
        _require(row.get("source_english_sha256") ==
                 _sha(source["source_english"].encode("utf-8")) and
                 row.get("vietnamese_sha256") ==
                 _sha(translated["vi"].encode("utf-8")) and
                 row.get("prior_brain_reason_sha256") ==
                 _sha(prior["brain_reason"].encode("utf-8")),
                 "BRAIN2I_CASE_BINDING_MISMATCH")
        decision, route = row.get("decision"), row.get("route")
        _require(decision in DECISIONS and route in ROUTES,
                 "BRAIN2I_DECISION_ROUTE_INVALID")
        _require(_code_list(row.get("risk_tags"), RISK_TAGS) and
                 _code_list(row.get("evidence_fields"), SOURCE_FIELDS) and
                 _code_list(row.get("unknowns"), UNKNOWN_CODES, allow_empty=True),
                 "BRAIN2I_CONTEXT_EVIDENCE_INVALID")
        _require(_text(row.get("brain_reason")) and
                 (row.get("candidate_revision") is None or
                  _text(row["candidate_revision"])),
                 "BRAIN2I_REASON_OR_REVISION_INVALID")
        _require(row.get("recipient_verified") is False or
                 (row.get("recipient_verified") is True and
                  source.get("recipient_metadata_verified") is True and
                  _text(source.get("recipient"))),
                 "BRAIN2I_UNGROUNDED_RECIPIENT")
        _require(row.get("independent_review") == "NOT_PERFORMED" and
                 row.get("human_approved") is False and
                 row.get("quality_certified") is False,
                 "BRAIN2I_FABRICATED_REVIEW_OR_APPROVAL")
        if decision == "BRAIN_ASSESSED":
            _require(_text(row.get("candidate_revision")),
                     "BRAIN2I_ASSESSED_WITHOUT_REVISION")
        if decision != "BRAIN_ASSESSED":
            _require(route != "HUMAN_EXCEPTION_DECISION",
                     "BRAIN2I_PREMATURE_HUMAN_ROUTING")
        if route == "HUMAN_EXCEPTION_DECISION":
            _require(_text(row.get("exception_rationale")) and
                     len(row["evidence_fields"]) >= 2,
                     "BRAIN2I_HUMAN_EXCEPTION_NOT_JUSTIFIED")
        else:
            _require(row.get("exception_rationale") is None,
                     "BRAIN2I_UNROUTED_HUMAN_EXCEPTION")
        if decision == "CONTEXT_PENDING":
            _require(bool(row["unknowns"]),
                     "BRAIN2I_PENDING_REQUIRES_EXPLICIT_UNKNOWN")
        if decision == "BLOCKED":
            _require(route == "BRAIN_CONTEXT_ENRICHMENT_FIRST",
                     "BRAIN2I_BLOCKED_ROUTE_INVALID")
        decisions[decision] += 1
        routes[route] += 1
        receipt_rows.append({
            "id": expected_id, "decision": decision, "route": route,
            "risk_tags": row["risk_tags"], "unknown_codes": row["unknowns"],
            "independent_review": "NOT_PERFORMED",
            "human_exception_approved": False
        })
    return {
        "schema": REPORT_SCHEMA,
        "source_corpus_canonical_lf_sha256": upstream["source_corpus_canonical_lf_sha256"],
        "input_export_sha256": _sha(export_raw),
        "input_review_sha256": _sha(review_raw),
        "input_challenge_sha256": _sha(challenge_raw),
        "review_owner": "AI_BRAIN",
        "case_count": len(TARGET_IDS),
        "decision_counts": dict(decisions),
        "route_counts": dict(routes),
        "case_receipts": receipt_rows,
        "independent_semantic_review": "NOT_PERFORMED",
        "quality_certified": False,
        "real_timed_media_verified": False,
        "tv_verified": False,
        "human_exception_approved": False
    }


def write_receipt_new(path: Path, report: dict[str, Any]) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=False, allow_nan=False)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Offline 9-case Brain contextual review provenance gate; no model/network calls"
    )
    parser.add_argument("--corpus", required=True, type=Path)
    parser.add_argument("--export", required=True, type=Path)
    parser.add_argument("--brain-review", required=True, type=Path)
    parser.add_argument("--challenge", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    corpus_raw, corpus = _load(args.corpus)
    export_raw, exported = _load(args.export)
    review_raw, reviewed = _load(args.brain_review)
    challenge_raw, challenge = _load(args.challenge)
    report = validate(corpus_raw, corpus, export_raw, exported,
                      review_raw, reviewed, challenge_raw, challenge)
    write_receipt_new(args.out, report)
    print("P2_AISUB_2I_SOURCE_REVIEW_RECEIPT nine_cases=9 quality_certified=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
