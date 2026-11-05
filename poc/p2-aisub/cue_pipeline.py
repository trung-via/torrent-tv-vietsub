"""P2-AISUB.1: local-only timed SRT/VTT cue QA and translated-text import.

No model/provider call, ASR, network, background processing or APK/TV effects.
A separate opt-in translator must create the cue-indexed JSON. This module
validates and imports only, preserving exact source timestamps and ordering.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass, replace
import json
from pathlib import Path
import re

MAX_CUES = 2000
MAX_BYTES = 1_000_000
SRT_TIME = re.compile(r"^(\d{2}):(\d{2}):(\d{2}),(\d{3})$")
VTT_TIME = re.compile(r"^(?:(\d{2}):)?(\d{2}):(\d{2})\.(\d{3})$")
ARROW = re.compile(r"^(\S+) --> (\S+)(.*)$")


@dataclass(frozen=True)
class Cue:
    number: int
    start_ms: int
    end_ms: int
    text: str
    identifier: str = ""
    settings: str = ""


def _decode(data: bytes) -> str:
    if len(data) > MAX_BYTES:
        raise ValueError("INPUT_TOO_LARGE")
    try:
        s = data.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise ValueError("UTF8_REQUIRED") from e
    if "\x00" in s:
        raise ValueError("BINARY_INPUT_NOT_ALLOWED")
    return s.replace("\r\n", "\n").replace("\r", "\n")


def _time_ms(s: str, fmt: str) -> int:
    m = (SRT_TIME if fmt == "srt" else VTT_TIME).fullmatch(s)
    if not m:
        raise ValueError("MALFORMED_TIMESTAMP")
    parts = m.groups()
    if fmt == "srt":
        h, minute, sec, ms = (int(v) for v in parts)
    else:
        h = int(parts[0] or 0)
        minute, sec, ms = (int(x) for x in parts[1:])
    if minute > 59 or sec > 59:
        raise ValueError("INVALID_TIME_RANGE")
    return ((h * 60 + minute) * 60 + sec) * 1000 + ms


def _time_text(ms: int, fmt: str) -> str:
    hours, rem = divmod(ms, 3600000)
    minutes, rem = divmod(rem, 60000)
    seconds, millis = divmod(rem, 1000)
    if hours > 99:
        raise ValueError("HOURS_OUT_OF_RANGE")
    separator = "," if fmt == "srt" else "."
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}{separator}{millis:03d}"


def parse_cues(data: bytes, fmt: str) -> tuple[Cue, ...]:
    if fmt not in ("srt", "vtt"):
        raise ValueError("UNSUPPORTED_FORMAT")
    s = _decode(data).strip("\n")
    blocks = re.split(r"\n[ \t]*\n+", s)
    if fmt == "vtt":
        if not blocks or not re.fullmatch(r"WEBVTT[^\n]*", blocks[0]):
            raise ValueError("VTT_HEADER_REQUIRED")
        blocks = blocks[1:]
    if not blocks or not blocks[0] or len(blocks) > MAX_CUES:
        raise ValueError("NO_CUES_OR_TOO_MANY")
    cues: list[Cue] = []
    prev_start = -1
    for i, block in enumerate(blocks, 1):
        lines = block.split("\n")
        identifier = ""
        if fmt == "srt":
            if len(lines) < 3 or lines[0] != str(i):
                raise ValueError("SRT_SEQUENCE_REQUIRED")
            timing, content = lines[1], lines[2:]
        else:
            if lines[0].startswith(("NOTE", "STYLE", "REGION")):
                raise ValueError("VTT_UNSUPPORTED_BLOCK")
            if " --> " in lines[0]:
                timing, content = lines[0], lines[1:]
            else:
                if len(lines) < 3 or not lines[0].strip():
                    raise ValueError("VTT_IDENTIFIER_OR_CUE_INVALID")
                identifier, timing, content = lines[0], lines[1], lines[2:]
        if not content or not all(t.strip() for t in content):
            raise ValueError("EMPTY_CUE_TEXT")
        m = ARROW.fullmatch(timing)
        if not m:
            raise ValueError("TIMING_ARROW_REQUIRED")
        start, end = _time_ms(m[1], fmt), _time_ms(m[2], fmt)
        settings = m[3]
        if fmt == "srt" and settings:
            raise ValueError("SRT_SETTINGS_INVALID")
        if end <= start or start < prev_start:
            raise ValueError("INVALID_CUE_DURATION_OR_ORDER")
        prev_start = start
        cues.append(Cue(i, start, end, "\n".join(content), identifier, settings))
    return tuple(cues)


def apply_translations(cues: tuple[Cue, ...], translations: dict[str, str]) -> tuple[Cue, ...]:
    if not isinstance(translations, dict):
        raise ValueError("TRANSLATION_MAP_REQUIRED")
    wanted = {str(c.number) for c in cues}
    if set(translations) != wanted:
        raise ValueError("MISSING_OR_EXTRA_TRANSLATED_CUE")
    out: list[Cue] = []
    for c in cues:
        text = translations[str(c.number)]
        if (not isinstance(text, str) or not text.strip()
            or len(text) > 2000 or any(ch in text for ch in ("\x00", "<", ">"))
            or "\r" in text):
            raise ValueError("PLAIN_UTF8_TRANSLATION_REQUIRED")
        out.append(replace(c, text=text.strip()))
    return tuple(out)


def render(cues: tuple[Cue, ...], fmt: str) -> bytes:
    if fmt not in ("srt", "vtt"):
        raise ValueError("UNSUPPORTED_FORMAT")
    sections = []
    for c in cues:
        line = f"{_time_text(c.start_ms, fmt)} --> {_time_text(c.end_ms, fmt)}"
        if fmt == "vtt":
            line += c.settings
            if c.identifier:
                line = c.identifier + "\n" + line
        else:
            line = str(c.number) + "\n" + line
        sections.append(line + "\n" + c.text)
    header = "WEBVTT\n\n" if fmt == "vtt" else ""
    return (header + "\n\n".join(sections) + "\n").encode("utf-8")


def main() -> int:
    p = argparse.ArgumentParser(description="Offline cue translation import; no AI calls")
    p.add_argument("--input", type=Path, required=True)
    p.add_argument("--translations", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--confirm", required=True)
    args = p.parse_args()
    if args.confirm != "LOCAL_OFFLINE_ONE_FILE":
        p.error("EXPLICIT_ONE_FILE_CONSENT_REQUIRED")
    if args.input.suffix.lower() not in (".srt", ".vtt") or args.output.suffix.lower() != args.input.suffix.lower():
        p.error("SAME_SRT_OR_VTT_FORMAT_REQUIRED")
    paths = [x.resolve() for x in (args.input, args.translations, args.output)]
    if len(set(paths)) != 3 or args.output.exists():
        p.error("OUTPUT_MUST_BE_NEW_AND_DISTINCT")
    fmt = args.input.suffix.lower()[1:]
    cues = parse_cues(args.input.read_bytes(), fmt)
    translations = json.loads(_decode(args.translations.read_bytes()))
    data = render(apply_translations(cues, translations), fmt)
    with args.output.open("xb") as f:
        f.write(data)
    print(f"LOCAL_CUE_QA_PASS format={fmt} cues={len(cues)} no_cloud_or_tv_effect")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
