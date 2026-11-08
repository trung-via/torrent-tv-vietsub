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


def extract_translations(receipt: bytes) -> tuple[dict[str, str], dict[str, int]]:
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

    # The canonical parser checks exact coverage, non-empty plain UTF-8 values,
    # no script/HTML tags, and safely rejects lone surrogate characters.
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
    args = parser.parse_args()

    if args.mode == "prepare":
        path = args.prompt_out
        if path.resolve() == FIXTURE.resolve():
            parser.error("PROMPT_CANNOT_OVERWRITE_FIXTURE")
        with path.open("x", encoding="utf-8") as file:
            file.write(prepare_prompt())
        print("AGY_SYNTHETIC_PROMPT_PREPARED cues=12 no_provider_call")
        return 0

    if args.confirm != CONFIRM:
        parser.error("EXPLICIT_SYNTHETIC_OUTPUT_CONFIRMATION_REQUIRED")
    if args.output.resolve() in (FIXTURE.resolve(), args.agy_json.resolve()):
        parser.error("OUTPUT_MUST_BE_DISTINCT")
    receipt = args.agy_json.read_bytes()
    translations, usage = extract_translations(receipt)
    data = render(apply_translations(fixture_cues(), translations), "srt")
    with args.output.open("xb") as file:
        file.write(data)
    # Never print translated text, user paths, receipt, or CLI conversation ID.
    metrics = " ".join(f"{k}={v}" for k, v in sorted(usage.items()))
    print("AGY_SYNTHETIC_12_CUE_IMPORT_PASS no_provider_call_by_script "
          + metrics)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
