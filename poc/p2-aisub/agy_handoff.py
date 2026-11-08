"""Attended P2-AISUB Antigravity CLI handoff for ONE ORIGINAL 12-cue fixture.

No subprocess/Antigravity invocation, provider call, network, API key, film file
or user subtitle input. Human runs `agy -p` manually and supplies its local JSON
receipt. This is NOT a general Antigravity backend or OMP integration.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from cloud_contract import build_gemini_request, partition_cues
from cue_pipeline import apply_translations, parse_cues, render

FIXTURE = Path(__file__).with_name("fixtures") / "agy_scene12_en.srt"
CONFIRM = "MANUAL_SYNTHETIC_12_CUE"
REPAIR_CONFIRM = "RECOVER_CP437_SYNTHETIC_12_CUE"
# OEM CP437 decoded UTF-8 produces forms such as "kh├┤ng", "sß║╜", "─æ".
# Detect the box drawing evidence rather than guessing from lack of accents.
CP437_MOJIBAKE_MARKERS = frozenset("├┤║─╜╗╞╣⌐░▒┐")
MAX_RECEIPT_BYTES = 256_000

SCENE = (
    "Original synthetic film scene. At a rainy train station, former lovers "
    "Linh (woman, younger) and Minh (man, older) confront a painful separation. "
    "Odd-numbered subtitle cues are spoken by Linh to Minh (em -> anh). "
    "Even-numbered cues are spoken by Minh to Linh (anh -> em). "
    "The scene moves from hurt and mistrust to a tentative reconciliation. "
    "Preserve the nuance and consistent Vietnamese address terms, not robotic "
    "word-for-word phrasing. No dialogue is from an actual film."
)


def fixture_cues():
    cues = parse_cues(FIXTURE.read_bytes(), "srt")
    if len(cues) != 12:
        raise ValueError("SYNTHETIC_FIXTURE_MUST_HAVE_12_CUES")
    return cues


def prepare_prompt() -> str:
    cues = fixture_cues()
    batch = partition_cues(cues, batch_size=12, context_size=0)[0]
    request = build_gemini_request(
        batch, synopsis=SCENE, glossary={"Linh": "Linh", "Minh": "Minh"},
    )
    return (
        "SYNTHETIC LICENSE-FREE TEST ONLY; no actual film/subtitle data.\n"
        + request["systemInstruction"]["parts"][0]["text"]
        + "\nThe response MUST be exactly one JSON object shaped "
        + '{"translations":[{"id":1,"vi":"..."}, ...,{"id":12,"vi":"..."}]}. '
        + "Every cue must be translated; omit all extra narration.\n"
        + request["contents"][0]["parts"][0]["text"]
    )


def _unique_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, val in pairs:
        if key in result:
            raise ValueError("DUPLICATE_JSON_KEY")
        result[key] = val
    return result


def _strict_json(s: str) -> Any:
    try:
        return json.loads(s, object_pairs_hook=_unique_pairs)
    except (json.JSONDecodeError, UnicodeError) as exc:
        raise ValueError("INVALID_AGY_JSON") from exc


def _looks_cp437_mojibake(text: str) -> bool:
    """Recognize characteristic UTF-8 bytes decoded as Windows OEM CP437."""
    return any(ch in CP437_MOJIBAKE_MARKERS for ch in text)


def _repair_cp437_text(text: str) -> str:
    """Undo exactly one provable UTF-8→CP437 misdecode, never guess accents."""
    try:
        recovered = text.encode("cp437", errors="strict").decode("utf-8", errors="strict")
    except UnicodeError as exc:
        raise ValueError("AGY_CP437_MOJIBAKE_UNRECOVERABLE") from exc
    if recovered == text or not any(ord(ch) > 127 for ch in recovered):
        raise ValueError("AGY_CP437_MOJIBAKE_UNRECOVERABLE")
    return recovered


def _check_or_repair_text(result: dict[str, str], *, repair_cp437: bool) -> dict[str, str]:
    updated: dict[str, str] = {}
    repaired = 0
    for key, value in result.items():
        if not isinstance(value, str):
            raise ValueError("AGY_TRANSLATION_TEXT_REQUIRED")
        if _looks_cp437_mojibake(value):
            if not repair_cp437:
                raise ValueError("AGY_CP437_MOJIBAKE_DETECTED")
            value = _repair_cp437_text(value)
            repaired += 1
        try:
            value.encode("utf-8", errors="strict")
        except UnicodeError as exc:
            raise ValueError("AGY_TRANSLATION_UTF8_INVALID") from exc
        updated[key] = value
    if repair_cp437 and repaired == 0:
        raise ValueError("AGY_CP437_REPAIR_NOT_NEEDED")
    return updated


def extract_translations(receipt: bytes, *, repair_cp437: bool = False) -> tuple[dict[str, str], dict[str, int]]:
    """Validate outer Antigravity CLI --output-format json and exact 12 IDs.

    Accept its observed {"1":"..."} inner form, and preferred
    {"translations":[{"id":1,"vi":"..."}, ...]} shape.
    """
    if not 0 < len(receipt) <= MAX_RECEIPT_BYTES:
        raise ValueError("AGY_RECEIPT_SIZE_INVALID")
    try:
        outer = _strict_json(receipt.decode("utf-8-sig"))
    except UnicodeError as exc:
        raise ValueError("AGY_RECEIPT_UTF8_REQUIRED") from exc
    if not isinstance(outer, dict) or outer.get("status") != "SUCCESS":
        raise ValueError("AGY_STATUS_NOT_SUCCESS")
    if outer.get("num_turns") != 1 or type(outer["num_turns"]) is not int:
        raise ValueError("AGY_SINGLE_TURN_REQUIRED")
    response = outer.get("response")
    if not isinstance(response, str) or len(response) > MAX_RECEIPT_BYTES:
        raise ValueError("AGY_RESPONSE_REQUIRED")
    inside = _strict_json(response)
    expected = [str(i) for i in range(1, 13)]

    if isinstance(inside, dict) and set(inside) == {"translations"}:
        items = inside["translations"]
        if not isinstance(items, list) or len(items) != len(expected):
            raise ValueError("AGY_TRANSLATION_COUNT_MISMATCH")
        result: dict[str, str] = {}
        for number, item in enumerate(items, start=1):
            if (not isinstance(item, dict) or set(item) != {"id", "vi"}
                or type(item["id"]) is not int or item["id"] != number):
                raise ValueError("AGY_TRANSLATION_ID_OR_ORDER_MISMATCH")
            result[str(number)] = item["vi"]
    elif isinstance(inside, dict) and list(inside) == expected:
        result = inside
    else:
        raise ValueError("AGY_RESPONSE_SCHEMA_MISMATCH")

    # A UTF-8-valid JSON response can still contain mojibake ("kh├┤ng").
    # Refuse silent corruption. Repair is opt-in and reversible, not automatic.
    result = _check_or_repair_text(result, repair_cp437=repair_cp437)
    apply_translations(fixture_cues(), result)

    usage: dict[str, int] = {}
    info = outer.get("usage")
    if isinstance(info, dict):
        for field in ("input_tokens", "output_tokens", "total_tokens"):
            val = info.get(field)
            if type(val) is int and val >= 0:
                usage[field] = val
    return result, usage


def main() -> int:
    parser = argparse.ArgumentParser(description="Attended synthetic Antigravity 12-cue test")
    sub = parser.add_subparsers(dest="mode", required=True)
    prepare = sub.add_parser("prepare", help="write synthetic prompt (no AI calls)")
    prepare.add_argument("--prompt-out", type=Path, required=True)
    ingest = sub.add_parser("ingest", help="read one manually captured agy JSON receipt")
    ingest.add_argument("--agy-json", type=Path, required=True)
    ingest.add_argument("--output", type=Path, required=True)
    ingest.add_argument("--confirm", required=True)
    ingest.add_argument("--repair-cp437", action="store_true",
                        help="explicit one-time repair of proven CP437 mojibake")
    inspect = sub.add_parser("inspect", help="read-only ASCII status of 12-cue SRT")
    inspect.add_argument("--srt", type=Path, required=True)
    args = parser.parse_args()

    if args.mode == "prepare":
        path = args.prompt_out
        if path.resolve() == FIXTURE.resolve():
            parser.error("PROMPT_CANNOT_OVERWRITE_FIXTURE")
        with path.open("x", encoding="utf-8") as file:
            file.write(prepare_prompt())
        print("AGY_SYNTHETIC_PROMPT_PREPARED cues=12 no_provider_call")
        return 0

    if args.mode == "inspect":
        actual = parse_cues(args.srt.read_bytes(), "srt")
        expected = fixture_cues()
        if len(actual) != 12 or (
            [(c.number, c.start_ms, c.end_ms) for c in actual] !=
            [(c.number, c.start_ms, c.end_ms) for c in expected]
        ):
            raise ValueError("AGY_SRT_NOT_THE_12_CUE_SYNTHETIC_FIXTURE")
        status = ("CP437_MOJIBAKE_SUSPECTED" if any(
            _looks_cp437_mojibake(c.text) for c in actual
        ) else "NO_CP437_MOJIBAKE_FOUND")
        print("AGY_SYNTHETIC_SRT_ENCODING_STATUS=" + status)
        return 0

    needed = REPAIR_CONFIRM if args.repair_cp437 else CONFIRM
    if args.confirm != needed:
        parser.error("EXPLICIT_SYNTHETIC_OUTPUT_CONFIRMATION_REQUIRED")
    if args.output.resolve() in (FIXTURE.resolve(), args.agy_json.resolve()):
        parser.error("OUTPUT_MUST_BE_DISTINCT")
    receipt = args.agy_json.read_bytes()
    translations, usage = extract_translations(receipt, repair_cp437=args.repair_cp437)
    data = render(apply_translations(fixture_cues(), translations), "srt")
    with args.output.open("xb") as file:
        file.write(data)
    # Never print translated text, user paths, receipt, or CLI conversation ID.
    metrics = " ".join(f"{k}={v}" for k, v in sorted(usage.items()))
    marker = ("AGY_SYNTHETIC_12_CUE_CP437_RECOVERY_PASS"
              if args.repair_cp437 else "AGY_SYNTHETIC_12_CUE_IMPORT_PASS")
    print(marker + " no_provider_call_by_script " + metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
