"""P2-AISUB FULL-SRT: offline, read-only EN/VI timed subtitle pair audit.

This is *not* translation or a semantic quality certification. No network,
provider, media playback, user-file writes or output of subtitle text/paths.
Both input files remain private to the caller's local workstation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from cue_pipeline import parse_cues
from subtitle_quality import analyze_cues


def audit_pair(source: bytes, translated: bytes, *, source_format: str = "srt",
               translated_format: str = "srt", profile: str = "adult") -> dict:
    """Refuse incomplete/misaligned outputs; report private-file-safe metrics."""
    original = parse_cues(source, source_format)
    vietnamese = parse_cues(translated, translated_format)
    if len(original) != len(vietnamese):
        raise ValueError("P2_PAIR_CUE_COUNT_MISMATCH")
    for before, after in zip(original, vietnamese):
        if (before.number, before.start_ms, before.end_ms) != (
            after.number, after.start_ms, after.end_ms
        ):
            raise ValueError("P2_PAIR_CUE_TIMESTAMP_MISMATCH")

    unchanged = [before.number for before, after in zip(original, vietnamese)
                 if before.text == after.text]
    readability = analyze_cues(vietnamese, profile=profile)
    return {
        "status": "STRUCTURE_PASS_TRANSLATION_UNVERIFIED",
        "original_format": source_format,
        "translated_format": translated_format,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "translated_sha256": hashlib.sha256(translated).hexdigest(),
        "cue_count": len(original),
        "first_start_ms": original[0].start_ms,
        "last_end_ms": original[-1].end_ms,
        "cue_timestamp_parity": "PASS",
        "unchanged_source_text_cues": len(unchanged),
        "unchanged_source_text_ids": unchanged[:40],
        "unchanged_ids_truncated": len(unchanged) > 40,
        "readability_status": readability["status"],
        "readability_flagged_count": readability["flagged_cues"],
        "readability_flags": readability["flags"],
        "semantic_fidelity": "NOT_REVIEWED",
        "character_and_pronoun_consistency": "NOT_REVIEWED",
        "real_redmi_playback": "NOT_RUN",
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Offline EN/VI subtitle pair audit. Outputs sanitized JSON; never prints subtitle lines."
    )
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--translated", required=True, type=Path)
    parser.add_argument("--profile", choices=("adult", "children"), default="adult")
    args = parser.parse_args()

    try:
        source_format = args.source.suffix.lower().lstrip(".")
        translated_format = args.translated.suffix.lower().lstrip(".")
        if source_format not in ("srt", "vtt") or translated_format not in ("srt", "vtt"):
            raise ValueError("P2_PAIR_SRT_VTT_ONLY")
        if args.source.resolve() == args.translated.resolve():
            raise ValueError("P2_PAIR_DISTINCT_SOURCE_AND_OUTPUT_REQUIRED")
        report = audit_pair(
            args.source.read_bytes(), args.translated.read_bytes(),
            source_format=source_format, translated_format=translated_format,
            profile=args.profile,
        )
    except (OSError, UnicodeError, ValueError) as exc:
        # Keep paths, subtitle/dialogue and provider responses out of stdout/stderr.
        allowed = {
            "P2_PAIR_SRT_VTT_ONLY", "P2_PAIR_DISTINCT_SOURCE_AND_OUTPUT_REQUIRED",
            "P2_PAIR_CUE_COUNT_MISMATCH", "P2_PAIR_CUE_TIMESTAMP_MISMATCH",
        }
        code = str(exc) if isinstance(exc, ValueError) and str(exc) in allowed else (
            "P2_PAIR_INPUT_OR_STRUCTURE_INVALID"
        )
        print(json.dumps({"status": "BLOCKED", "error_code": code}, sort_keys=True))
        return 2
    print(json.dumps(report, sort_keys=True, ensure_ascii=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
