"""P2-AISUB.2g: offline, source-bound Brain-review preflight for 36 synthetic cases.

Detects measurable subtitle length and possible ungrounded contextual
choices. NOT a semantic judge, rewrite engine, human scorer, provider client
or real-timed SRT/TV test. It prints no original/translated dialogue.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import unicodedata
from typing import Any, Mapping

CORPUS_SCHEMA = "P2-AISUB.2a-original-synthetic-context-v1"
EXPORT_SCHEMA = "P2-AISUB.2f-brain-input-v1"
REPORT_SCHEMA = "P2-AISUB.2g-context-gate-v1"
CONTEXT_SENSITIVE_FOCUS = frozenset({
    "pronoun", "relationship", "honorific", "hierarchy", "ambiguity", "register"
})
TITLE_TERMS = ("phu nhân", "quý cô", "tiểu thư", "lệnh bà")
PEJORATIVE_TERMS = ("hắn", "mụ", "ả")
MAX_JSON_BYTES = 250_000


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    obj: dict[str, Any] = {}
    for key, value in pairs:
        if key in obj:
            raise ValueError("BRAIN36_JSON_DUPLICATE_KEY")
        obj[key] = value
    return obj


def _reject_nonfinite(_value: str) -> Any:
    raise ValueError("BRAIN36_JSON_NONFINITE_NUMBER")


def _load(path: Path) -> tuple[bytes, Any]:
    raw = path.read_bytes()
    if not 0 < len(raw) <= MAX_JSON_BYTES:
        raise ValueError("BRAIN36_JSON_SIZE_INVALID")
    try:
        obj = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=_unique_pairs,
                         parse_constant=_reject_nonfinite)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError("BRAIN36_JSON_UTF8_OR_SYNTAX_INVALID") from exc
    return raw, obj


def _validate(corpus_raw: bytes, corpus: Any, exported: Any) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    if not isinstance(corpus, dict) or corpus.get("corpus") != CORPUS_SCHEMA:
        raise ValueError("BRAIN36_CORPUS_SCHEMA_INVALID")
    cases = corpus.get("cases")
    if (not isinstance(cases, list) or len(cases) != 36 or
            any(not isinstance(c, dict) or type(c.get("id")) is not int or c["id"] != i
                for i, c in enumerate(cases, 1))):
        raise ValueError("BRAIN36_CORPUS_IDS_INVALID")
    if any(not isinstance(c, dict) or not all(isinstance(c.get(k), str) and c[k].strip() for k in ("genre", "scene_context", "speaker", "source_english", "risk_focus")) for c in cases):
        raise ValueError("BRAIN36_CORPUS_CASE_INVALID")
    sha = hashlib.sha256(corpus_raw).hexdigest()
    if not isinstance(exported, dict) or exported.get("schema") != EXPORT_SCHEMA or exported.get("corpus_sha256") != sha:
        raise ValueError("BRAIN36_EXPORT_PROVENANCE_INVALID")
    if exported.get("blind_label") != "A" or exported.get("machine_readability_not_semantic_pass") is not True:
        raise ValueError("BRAIN36_EXPORT_LABEL_OR_STATUS_INVALID")
    rows = exported.get("translations")
    if not isinstance(rows, list) or len(rows) != 36:
        raise ValueError("BRAIN36_EXPORT_COUNT_INVALID")
    for i, row in enumerate(rows, 1):
        if (not isinstance(row, dict) or set(row) != {"id", "vi"} or type(row["id"]) is not int or
            row["id"] != i or not isinstance(row["vi"], str) or not row["vi"].strip() or
            len(row["vi"]) > 1500 or any(c in row["vi"] for c in ("\x00", "\r", "\t", "<", ">"))):
            raise ValueError("BRAIN36_EXPORT_ROW_INVALID")
    return cases, rows, sha


def _contains_term(text: str, terms: tuple[str, ...]) -> bool:
    return any(re.search(r"(?<!\w)" + re.escape(term) + r"(?!\w)", text, re.IGNORECASE) for term in terms)


def audit(corpus_raw: bytes, corpus: Mapping[str, Any], exported: Mapping[str, Any], *, assumed_seconds: float = 2.5) -> dict[str, Any]:
    if not isinstance(assumed_seconds, (int, float)) or type(assumed_seconds) is bool or not (0.1 <= assumed_seconds <= 60):
        raise ValueError("BRAIN36_ASSUMED_DURATION_INVALID")
    cases, rows, sha = _validate(corpus_raw, corpus, exported)
    # Bind audit results to the *contents* of the input, not only the corpus.
    # Stable regardless of JSON whitespace/key ordering; CLI additionally pins raw bytes.
    canonical_input = json.dumps(exported, ensure_ascii=False, sort_keys=True,
                                 separators=(",", ":"), allow_nan=False).encode("utf-8")
    totals: Counter[str] = Counter()
    checks: list[dict[str, Any]] = []
    for case, row in zip(cases, rows):
        text = unicodedata.normalize("NFC", row["vi"])
        lines = text.split("\n")
        n = sum(len(line) for line in lines)
        exact_cps = n / assumed_seconds
        cps = round(exact_cps, 2)
        flags: list[str] = []
        if exact_cps > 17.0:
            flags.append("HYPOTHETICAL_SPEED_OVER_17_CPS")
        if max(map(len, lines)) > 42:
            flags.append("LINE_OVER_42_CHARS")
        if len(lines) > 2:
            flags.append("OVER_TWO_LINES")
        if text != row["vi"]:
            flags.append("UNICODE_NOT_NFC")
        if case["risk_focus"] in CONTEXT_SENSITIVE_FOCUS and not case.get("recipient_metadata_verified"):
            flags.append("CHARACTER_CONTEXT_REVIEW")
        if _contains_term(text, TITLE_TERMS) and not case.get("recipient_title_verified"):
            flags.append("TITLE_ASSUMPTION_REVIEW")
        if _contains_term(text, PEJORATIVE_TERMS):
            flags.append("PEJORATIVE_REGISTER_REVIEW")
        if (case["risk_focus"] in ("relationship", "pronoun") and
                _contains_term(text, ("anh", "chị", "em", "cậu", "tớ")) and
                not case.get("recipient_pronoun_verified")):
            flags.append("RELATIONAL_PRONOUN_REVIEW")
        totals.update(flags)
        checks.append({"id": row["id"], "genre": case["genre"], "flags": flags,
                       "visible_nfc_characters": n, "hypothetical_cps": cps,
                       "line_count": len(lines), "max_line_chars": max(map(len, lines))})
    return {
        "schema": REPORT_SCHEMA, "source_corpus_sha256": sha, "blind_label": "A",
        "input_export_canonical_sha256": hashlib.sha256(canonical_input).hexdigest(),
        "evaluated_cases": 36, "source": "LOCAL_OFFLINE_STRUCTURAL_HEURISTIC_ONLY",
        "assumed_seconds_per_case": assumed_seconds, "real_timecodes_verified": False,
        "semantic_quality_certified": False, "quality_certified": False,
        "score_provenance": "NO_AI_OR_HUMAN_SCORES_USED",
        "flag_counts": dict(sorted(totals.items())), "cases": checks,
    }


def main() -> int:
    p = argparse.ArgumentParser(description="Offline Brain36 readability/context REVIEW flags; no model call or raw dialogue output")
    p.add_argument("--corpus", type=Path, required=True)
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--assumed-seconds", type=float, default=2.5)
    p.add_argument("--out", type=Path, required=True, help="new-only report path (never overwrites)")
    a = p.parse_args()
    corpus_raw, corpus = _load(a.corpus)
    export_raw, exported = _load(a.input)
    result = audit(corpus_raw, corpus, exported, assumed_seconds=a.assumed_seconds)
    result["input_export_file_sha256"] = hashlib.sha256(export_raw).hexdigest()
    with a.out.open("x", encoding="utf-8", newline="\n") as fh:
        json.dump(result, fh, indent=2, ensure_ascii=False, allow_nan=False)
        fh.write("\n")
    print("BRAIN36_CONTEXT_GATE_REPORT cases=36 semantic_quality_certified=False real_timecodes_verified=False")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
