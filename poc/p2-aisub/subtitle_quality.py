"""P2-AISUB.2c: read-only, offline Vietnamese SRT/VTT readability signals.

No AI/model/provider calls, subtitle rewrite, audio, media access or TV actions.
Syntactic cue/timestamp validation belongs to cue_pipeline.py. Speed/line
limits are review heuristics, never proof of translation accuracy or good style.

Reference guidance: Netflix Vietnamese Timed Text Style Guide
https://partnerhelp.netflixstudios.com/hc/en-us/articles/220447048-
Vietnamese-Timed-Text-Style-Guide
42 characters per line, maximum two lines; 17 CPS adult / 13 CPS child.
This is only a useful default, not certification or a requirement for OMP.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import unicodedata
from typing import Any, Sequence

from cue_pipeline import Cue, parse_cues

PROFILE_CPS = {"adult": 17.0, "children": 13.0}
DEFAULT_MAX_LINE_CHARS = 42
DEFAULT_MAX_LINES = 2
CP437_MARKERS = frozenset("├┤║─╜╗╞╣⌐░▒┐")

# Deliberately does not claim any semantic speaker/pronoun/translation PASS.
HUMAN_REVIEW = (
    "semantic_fidelity",
    "speaker_and_character_identity",
    "vietnamese_pronouns_and_relationships",
    "emotion_tone_register",
    "idioms_and_humor",
)


def analyze_cues(
    cues: Sequence[Cue],
    *,
    profile: str = "adult",
    max_cps: float | None = None,
    max_line_chars: int = DEFAULT_MAX_LINE_CHARS,
    max_lines: int = DEFAULT_MAX_LINES,
) -> dict[str, Any]:
    """Calculate non-mutating, non-text-leaking quality warnings.

    CPS counts NFC Unicode code points, including spaces and punctuation but
    excluding line-break separators; no estimate of reading proficiency.
    """
    if profile not in PROFILE_CPS:
        raise ValueError("UNKNOWN_QUALITY_PROFILE")
    limit = float(PROFILE_CPS[profile] if max_cps is None else max_cps)
    if not (5.0 <= limit <= 40.0) or limit != limit:
        raise ValueError("QUALITY_CPS_LIMIT_INVALID")
    if type(max_line_chars) is not int or not (20 <= max_line_chars <= 80):
        raise ValueError("QUALITY_LINE_CHAR_LIMIT_INVALID")
    if type(max_lines) is not int or not (1 <= max_lines <= 3):
        raise ValueError("QUALITY_LINE_COUNT_LIMIT_INVALID")

    flags: list[dict[str, Any]] = []
    for c in cues:
        duration_ms = c.end_ms - c.start_ms
        if duration_ms <= 0:
            raise ValueError("QUALITY_INVALID_CUE_TIMING")
        normalized = unicodedata.normalize("NFC", c.text)
        lines = normalized.split("\n")
        counts = [len(line) for line in lines]
        chars = sum(counts)
        cps = (chars * 1000.0) / duration_ms

        reasons: list[str] = []
        if cps > limit + 1e-10:
            reasons.append("READING_SPEED")
        if any(n > max_line_chars for n in counts):
            reasons.append("LINE_TOO_LONG")
        if len(lines) > max_lines:
            reasons.append("TOO_MANY_LINES")
        if normalized != c.text:
            reasons.append("NON_NFC_TEXT")
        if any(ch in CP437_MARKERS for ch in c.text):
            reasons.append("CP437_MOJIBAKE_SUSPECTED")
        if any("  " in line or "\t" in line for line in lines):
            reasons.append("UNUSUAL_WHITESPACE")
        if not reasons:
            continue
        flags.append({
            "id": c.number,
            "codes": reasons,
            "duration_ms": duration_ms,
            "char_count": chars,
            "max_line_chars": max(counts),
            "line_count": len(lines),
            "cps_x10": (chars * 10000 + duration_ms // 2) // duration_ms,
        })

    return {
        "status": "QUALITY_REVIEW_REQUIRED" if flags else "READABILITY_HEURISTICS_PASS",
        "profile": profile,
        "cps_limit": limit,
        "max_line_chars": max_line_chars,
        "max_lines": max_lines,
        "total_cues": len(cues),
        "flagged_cues": len(flags),
        "flags": flags,
        "human_semantic_review": "REQUIRED",
        "human_review_dimensions": list(HUMAN_REVIEW),
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Inspect SRT/VTT readability OFFLINE; never edits or uploads subtitles."
    )
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--profile", choices=tuple(PROFILE_CPS), default="adult")
    parser.add_argument("--max-cps", type=float, default=None)
    parser.add_argument("--max-line-chars", type=int, default=DEFAULT_MAX_LINE_CHARS)
    parser.add_argument("--max-lines", type=int, default=DEFAULT_MAX_LINES)
    args = parser.parse_args()
    suffix = args.input.suffix.lower()
    if suffix not in (".srt", ".vtt"):
        parser.error("QUALITY_REQUIRES_SRT_OR_VTT")
    cues = parse_cues(args.input.read_bytes(), suffix[1:])
    report = analyze_cues(
        cues, profile=args.profile, max_cps=args.max_cps,
        max_line_chars=args.max_line_chars, max_lines=args.max_lines,
    )
    # Output is ASCII JSON and contains no subtitle lines, title or file path.
    print(json.dumps(report, ensure_ascii=True, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
