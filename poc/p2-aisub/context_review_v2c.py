"""P2-AISUB v2c: offline annotation-based continuity and timing review.

This module does NOT parse Vietnamese to infer pronouns or generate translations.
The observation and any alternate text must be manually supplied. The tool
only compares marked observed terms against v2b scene-effective directed
address rules and computes readability using the *original cue timestamps*.
No model, network, implicit edits, semantic certification or TV effect.
"""
from __future__ import annotations

import argparse
from dataclasses import replace
import json
from pathlib import Path
import unicodedata
from typing import Any

from context_engine_v2 import (
    CP437_MARKERS, _fields, _format, _metadata_file, _plain, _source_cues,
    _strict_json, apply_translations,
)
from context_memory_v2b import _stable_digest, create_memory_plan, inspect_memory
from subtitle_quality import analyze_cues

SCHEMA = "P2-AISUB.review-v2c-annotations-v1"
REPORT_SCHEMA = "P2-AISUB.review-v2c-report-v1"
CONFIRM = "PREPARE_ORIGINAL_SYNTHETIC_REVIEW_V2C"
STATES = ("unchecked", "omitted", "explicit")


def _exact_translations(source: bytes, fmt: str, context: Any, memory: Any,
                        translations: Any):
    """Uses canonical cue-ID validator and v2b's actual QA/UTF-8 gates."""
    inspect_memory(source, fmt, context, memory, translations)
    cues = _source_cues(source, fmt)
    return cues, apply_translations(cues, translations)


def build_review_template(source: bytes, fmt: str, context: Any,
                          memory: Any, translations: Any) -> dict[str, Any]:
    """Produce blank, source/manifest/memory/translation-bound human checklist."""
    plan = create_memory_plan(source, fmt, context, memory)
    cues, _ = _exact_translations(source, fmt, context, memory, translations)
    return {
        "schema": SCHEMA,
        "provenance": plan["provenance"],
        "source_sha256": plan["source_sha256"],
        "base_context_sha256": plan["base_context_sha256"],
        "memory_sha256": plan["memory_sha256"],
        "translation_sha256": _stable_digest(translations),
        "rows": [{
            "id": cue.number,
            "self_use": {"status": "unchecked", "term": None},
            "other_use": {"status": "unchecked", "term": None},
            "candidate_vi": None,
            "candidate_meaning_reviewed": None,
        } for cue in cues],
        "instructions": (
            "Human marks each pronoun use as unchecked, omitted or explicit; "
            "an explicit status requires the exact observed term. This tool "
            "CANNOT identify terms automatically. Candidate_vi is optional "
            "human-authored alternate wording, NEVER an automatic rewrite. "
            "Candidate_meaning_reviewed is a claimed human assessment only; "
            "even True is NOT a certified semantic pass."
        ),
    }


def _check_pronoun_cell(cell: Any) -> None:
    _fields(cell, {"status", "term"}, "REVIEW_PRONOUN_CELL_SHAPE_INVALID")
    state, term = cell["status"], cell["term"]
    if state not in STATES:
        raise ValueError("REVIEW_PRONOUN_STATUS_INVALID")
    if state != "explicit":
        if term is not None:
            raise ValueError("REVIEW_NONEXPLICIT_TERM_MUST_BE_NULL")
        return
    if (not _plain(term, max_chars=30) or term != term.strip()
        or "\n" in term or "\t" in term
        or unicodedata.normalize("NFC", term) != term
        or any(ch in CP437_MARKERS for ch in term)):
        raise ValueError("REVIEW_PRONOUN_TERM_INVALID")
    try:
        term.encode("utf-8", errors="strict")
    except UnicodeError as exc:
        raise ValueError("REVIEW_PRONOUN_UTF8_INVALID") from exc


def _check_candidate(candidate: Any, meaning: Any) -> None:
    if candidate is None:
        if meaning is not None:
            raise ValueError("REVIEW_MEANING_CLAIM_WITHOUT_CANDIDATE")
        return
    if (not isinstance(candidate, str) or not candidate.strip()
        or len(candidate) > 2000
        or any(ch in candidate for ch in ("\x00", "\r", "<", ">"))
        or any(ch in CP437_MARKERS for ch in candidate)):
        raise ValueError("REVIEW_CANDIDATE_TEXT_INVALID")
    if meaning is not None and type(meaning) is not bool:
        raise ValueError("REVIEW_CANDIDATE_MEANING_TYPE_INVALID")
    try:
        candidate.encode("utf-8", errors="strict")
    except UnicodeError as exc:
        raise ValueError("REVIEW_CANDIDATE_UTF8_INVALID") from exc


def analyze_review(source: bytes, fmt: str, context: Any, memory: Any,
                   translations: Any, review: Any) -> dict[str, Any]:
    """Read-only warning IDs and numeric quality metrics; NEVER publishes text."""
    template = build_review_template(source, fmt, context, memory, translations)
    _fields(review, set(template), "REVIEW_ENVELOPE_SHAPE_INVALID")
    for key in ("schema", "provenance", "source_sha256",
                "base_context_sha256", "memory_sha256", "translation_sha256"):
        if review[key] != template[key]:
            raise ValueError("REVIEW_PROVENANCE_OR_CONTENT_DRIFT")
    if review["instructions"] != template["instructions"]:
        raise ValueError("REVIEW_INSTRUCTIONS_CHANGED")
    rows = review["rows"]
    if not isinstance(rows, list) or len(rows) != len(template["rows"]):
        raise ValueError("REVIEW_ROWS_INCOMPLETE")
    cues, translated_cues = _exact_translations(
        source, fmt, context, memory, translations)
    plan = create_memory_plan(source, fmt, context, memory)
    by_id = {
        target["id"]: target
        for scene in plan["scenes"] for batch in scene["batches"]
        for target in batch["target"]
    }
    base_qa = analyze_cues(translated_cues)
    report_rows: list[dict[str, Any]] = []
    mismatch_cues = 0
    unreviewed_fields = 0
    candidate_count = 0
    for row, expected, cue, translated in zip(
            rows, template["rows"], cues, translated_cues):
        _fields(row, {"id", "self_use", "other_use", "candidate_vi",
                      "candidate_meaning_reviewed"}, "REVIEW_ROW_SHAPE_INVALID")
        if type(row["id"]) is not int or row["id"] != expected["id"]:
            raise ValueError("REVIEW_ROW_ID_ORDER_INVALID")
        _check_pronoun_cell(row["self_use"])
        _check_pronoun_cell(row["other_use"])
        proposal, human_claim = row["candidate_vi"], row["candidate_meaning_reviewed"]
        _check_candidate(proposal, human_claim)
        target = by_id[cue.number]
        rule = target["address"]
        codes: list[str] = list(target["context_warnings"])
        mismatch = False
        for role, cell in (("SELF", row["self_use"]), ("OTHER", row["other_use"])):
            state = cell["status"]
            if state == "unchecked":
                codes.append(role + "_PRONOUN_UNCHECKED")
                unreviewed_fields += 1
            elif state == "omitted":
                codes.append(role + "_PRONOUN_OMITTED_NEEDS_HUMAN_CONTEXT")
            elif rule is None:
                codes.append(role + "_DECLARED_WITHOUT_CONFIRMED_RULE")
            elif cell["term"].casefold() != rule["self" if role == "SELF" else "other"].casefold():
                codes.append(role + "_PRONOUN_MISMATCH_REVIEW")
                mismatch = True
        candidate_metrics = None
        if proposal is not None:
            candidate_count += 1
            alternative = apply_translations(
                (cue,), {str(cue.number): proposal})[0]
            before = analyze_cues((translated,))
            after = analyze_cues((alternative,))
            old_chars = _char_count(translated.text)
            new_chars = _char_count(alternative.text)
            if new_chars >= old_chars:
                codes.append("CANDIDATE_NOT_SHORTER")
            if after["flagged_cues"]:
                codes.append("CANDIDATE_READABILITY_WARNING")
            codes.append("CANDIDATE_MEANING_REVIEW_REQUIRED")
            candidate_metrics = {
                "original_char_count": old_chars,
                "candidate_char_count": new_chars,
                "original_cps_x10": _cps_x10(old_chars, cue.end_ms-cue.start_ms),
                "candidate_cps_x10": _cps_x10(new_chars, cue.end_ms-cue.start_ms),
                "original_readability_codes": _quality_codes(before),
                "candidate_readability_codes": _quality_codes(after),
                "shorter": new_chars < old_chars,
                "human_meaning_claim": human_claim,
                "human_meaning_claim_not_verified": True,
                "never_auto_applied": True,
            }
        if mismatch:
            mismatch_cues += 1
        if codes or candidate_metrics is not None:
            report_rows.append({
                "id": cue.number,
                "codes": codes,
                "candidate_metrics": candidate_metrics,
                "semantic_truth_not_machine_tested": True,
            })
    return {
        "schema": REPORT_SCHEMA,
        "source_sha256": plan["source_sha256"],
        "base_context_sha256": plan["base_context_sha256"],
        "memory_sha256": plan["memory_sha256"],
        "translation_sha256": template["translation_sha256"],
        "total_cues": len(cues),
        "baseline_readability": base_qa,
        "warning_cues": len(report_rows),
        "explicit_pronoun_mismatch_cues": mismatch_cues,
        "unchecked_pronoun_fields": unreviewed_fields,
        "human_draft_candidate_count": candidate_count,
        "rows": report_rows,
        "human_semantic_review": "REQUIRED",
        "quality_certified": False,
        "subtitle_rewritten": False,
        "model_or_network_call": False,
    }


def _char_count(text: str) -> int:
    return sum(len(line) for line in unicodedata.normalize("NFC", text).split("\n"))


def _cps_x10(chars: int, duration_ms: int) -> int:
    return (chars * 10000 + duration_ms // 2) // duration_ms


def _quality_codes(report: dict[str, Any]) -> list[str]:
    return report["flags"][0]["codes"] if report["flags"] else []


def main() -> int:
    p = argparse.ArgumentParser(
        description="P2-AISUB v2c offline authored-pronoun and candidate readability QA")
    sub = p.add_subparsers(dest="cmd", required=True)
    prep = sub.add_parser("prepare", help="create BLANK human review template")
    ins = sub.add_parser("inspect", help="inspect completed/partial human review read-only")
    for cmd in (prep, ins):
        cmd.add_argument("--input", type=Path, required=True)
        cmd.add_argument("--context", type=Path, required=True)
        cmd.add_argument("--memory", type=Path, required=True)
        cmd.add_argument("--translations", type=Path, required=True)
    prep.add_argument("--out", type=Path, required=True)
    prep.add_argument("--confirm", required=True)
    ins.add_argument("--review", type=Path, required=True)
    args = p.parse_args()
    source = args.input.read_bytes()
    fmt = _format(args.input)
    context = _metadata_file(args.context)
    memory = _strict_json(args.memory.read_bytes(), max_bytes=80_000)
    translations = _strict_json(args.translations.read_bytes(), max_bytes=256_000)
    if (context.get("provenance") != "original_synthetic"
        or memory.get("provenance") != "original_synthetic"):
        p.error("REVIEW_V2C_CLI_ORIGINAL_SYNTHETIC_ONLY")
    if args.cmd == "prepare":
        if args.confirm != CONFIRM:
            p.error("REVIEW_V2C_EXPLICIT_CONFIRM_REQUIRED")
        paths = [x.resolve() for x in (
            args.input, args.context, args.memory, args.translations, args.out)]
        if len(paths) != len(set(paths)) or args.out.exists():
            p.error("REVIEW_V2C_NEW_DISTINCT_OUTPUT_REQUIRED")
        template = build_review_template(source, fmt, context, memory, translations)
        with args.out.open("x", encoding="utf-8", newline="\n") as f:
            json.dump(template, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"CONTEXT_V2C_REVIEW_TEMPLATE_PREPARED cues={len(template['rows'])} human_fields_unchecked no_model_call")
    else:
        review = _strict_json(args.review.read_bytes(), max_bytes=256_000)
        result = analyze_review(source, fmt, context, memory, translations, review)
        print(json.dumps(result, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
