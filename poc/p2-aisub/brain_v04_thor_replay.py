"""Thor 2017 Brain FastPath benchmark replay guard, offline source-only.

The archived v0.3.4 data below is HISTORY, not a new translation, model
invocation, speed certification, or independently blinded bilingual QA.
The real user-provided English SRT must be accessible AND sha-pinned before
calling the separate v0.4 experiment planner. This module contains no captions.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Callable

from cue_pipeline import parse_cues

SOURCE_SHA256 = "76b857688ed6ab1f279190d23c54e3d5697eb91870178637342fd0874996ea8a"
SOURCE_CUES = 1761
RANGES = "181-340,561-720,1081-1240"
WINDOWS = ((181, 340), (561, 720), (1081, 1240))
HISTORICAL = {
    "QUALITY_60": (78.552, 76.987, 72.968),
    "FAST_120": (66.091, 85.538, 74.610),
    "EXP_160": (63.348, 82.465, 79.167),
}
V04_ARMS = ("BASE120", "LEAN120", "ADAPTIVE")


class ThorReplayBlocked(Exception):
    """Public safe error codes only; never subtitle dialogue or local paths."""


def baseline() -> dict[str, Any]:
    return {
        "status": "HISTORICAL_REFERENCE_ONLY",
        "title": "THOR_RAGNAROK_2017",
        "source_sha256": SOURCE_SHA256,
        "source_cue_count": SOURCE_CUES,
        "source_window_ranges": [list(pair) for pair in WINDOWS],
        "v035_control": "FAST120_PROVISIONAL",
        "historical_v034_initial_wall_seconds": {
            arm: {"per_window": list(times), "three_window_total": round(sum(times), 3)}
            for arm, times in HISTORICAL.items()
        },
        "historical_measurement_scope": "CHAT_SESSION_START_TO_INITIAL_STRUCTURAL_QA_NOT_POST_REPAIR",
        "v04_required_arms": list(V04_ARMS),
        "v04_new_generation": "NOT_RUN",
        "independent_bilingual_review": "NOT_RUN",
        "speed_winner": "NONE",
        "default_change_authorized": False,
        "film_text_embedded": False,
    }


def inspect_source(raw: bytes, *, expected_sha: str = SOURCE_SHA256,
                   expected_count: int = SOURCE_CUES) -> dict[str, Any]:
    if hashlib.sha256(raw).hexdigest() != expected_sha:
        raise ThorReplayBlocked("THOR_EN_EXACT_SHA_REQUIRED")
    try:
        cues = parse_cues(raw, "srt")
    except (ValueError, UnicodeError):
        raise ThorReplayBlocked("THOR_EN_STRUCTURAL_PARSE_FAILED") from None
    if len(cues) != expected_count:
        raise ThorReplayBlocked("THOR_EN_CUE_COUNT_MISMATCH")
    if expected_count < max(end for _, end in WINDOWS):
        raise ThorReplayBlocked("THOR_EN_MISSING_BENCHMARK_WINDOWS")
    for a, b in WINDOWS:
        if [c.number for c in cues[a-1:b]] != list(range(a, b + 1)):
            raise ThorReplayBlocked("THOR_EN_WINDOW_ID_MISMATCH")
    return {
        "status": "THOR_EXACT_SOURCE_VERIFIED",
        "source_sha256": expected_sha,
        "cue_count": len(cues),
        "windows": [list(x) for x in WINDOWS],
        "translation_performed": False,
    }


def prepare_plan(source: Path, private_workdir: Path,
                 *, glossary: Path | None = None,
                 planner: Callable[..., dict[str, Any]] | None = None,
                 expected_sha: str = SOURCE_SHA256,
                 expected_count: int = SOURCE_CUES) -> dict[str, Any]:
    if source.suffix.lower() != ".srt":
        raise ThorReplayBlocked("THOR_EN_SRT_REQUIRED")
    try:
        data = source.read_bytes()
    except OSError:
        raise ThorReplayBlocked("THOR_EN_SOURCE_UNAVAILABLE") from None
    inspect_source(data, expected_sha=expected_sha, expected_count=expected_count)
    if private_workdir.exists():
        raise ThorReplayBlocked("THOR_REPLAY_WORKDIR_ALREADY_EXISTS")
    if planner is None:
        from brain_fastpath_v04_experiment import plan as planner
    try:
        result = planner(source, private_workdir, RANGES, glossary)
    except Exception:
        # No path, prompt text or accidental private model output in public stdout.
        raise ThorReplayBlocked("THOR_V04_PRIVATE_PLAN_FAILED") from None
    if (not isinstance(result, dict) or result.get("trials") != 9
            or result.get("model_calls") != 0):
        raise ThorReplayBlocked("THOR_V04_PLAN_NOT_VERIFIED")
    return {
        "status": "THOR_V04_PRIVATE_PLAN_CREATED_NO_TRANSLATION",
        "source_sha256": expected_sha,
        "historical_reference": "V034_THREE_WINDOW_3X3_INITIAL_QA_ONLY",
        "windows": [list(pair) for pair in WINDOWS],
        "v04_trial_count": 9,
        "brain_v035_default": "UNCHANGED",
        "v04_real_translation": "NOT_RUN",
        "speed_winner": "NONE",
        "model_calls": 0,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="OFFLINE THOR historical benchmark pin (NO model calls)")
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("baseline")
    p = sub.add_parser("precheck")
    p.add_argument("--source", type=Path, required=True)
    p = sub.add_parser("plan")
    p.add_argument("--source", type=Path, required=True)
    p.add_argument("--workdir", type=Path, required=True)
    p.add_argument("--glossary", type=Path)
    args = ap.parse_args(argv)
    try:
        if args.command == "baseline":
            report = baseline()
        elif args.command == "precheck":
            try:
                blob = args.source.read_bytes()
            except OSError:
                raise ThorReplayBlocked("THOR_EN_SOURCE_UNAVAILABLE") from None
            report = inspect_source(blob)
        else:
            report = prepare_plan(args.source, args.workdir, glossary=args.glossary)
        print(json.dumps(report, ensure_ascii=True, sort_keys=True))
        return 0
    except ThorReplayBlocked as error:
        print(json.dumps({"status": "BLOCKED", "error_code": str(error)}, sort_keys=True))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
