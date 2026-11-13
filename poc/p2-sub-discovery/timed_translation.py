"""EN timed-SRT -> Vietnamese translation orchestration, API-neutral and opt-in.

No built-in cloud SDK/network, account credentials, dialogue logging or file I/O.
Inject a separately authorized translation adapter (Brain/manual or paid API).
The returned VI SRT preserves source ordinal/timestamps. Deterministic QA is
structural ONLY; human bilingual/sync review remains required.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re
from typing import Callable, Mapping

from opensubtitles import Asset, SubtitleApiError, validate_timed_text

_START_END = re.compile(
    r"^\d{2}:\d{2}:\d{2},\d{3}\s*-->\s*\d{2}:\d{2}:\d{2},\d{3}(?:\s+.*)?$")
_SPLIT_BLOCKS = re.compile(r"\n[ \t]*\n")
MAX_CUES_PER_BATCH = 120
MAX_SOURCE_CHARS_PER_BATCH = 6500
CONTEXT_CUES = 4


@dataclass(frozen=True)
class Cue:
    ordinal: int
    timeline: str
    text: str


@dataclass(frozen=True)
class Batch:
    # Source IDs are immutable; ±4 context cues are READ-ONLY.
    source: tuple[Cue, ...]
    before: tuple[Cue, ...]
    after: tuple[Cue, ...]


@dataclass(frozen=True)
class Translated:
    contents: bytes
    source_sha256: str
    output_sha256: str
    cue_count: int
    qa_status: str = "STRUCTURAL_PASS_SEMANTIC_UNVERIFIED"


# The adapter must return exactly one VI text per source ordinal. It may call
# an API, but never receives credentials from this module.
Translator = Callable[[Batch], Mapping[int, str]]


def parse_srt(contents: bytes) -> tuple[Cue, ...]:
    validate_timed_text(contents, "srt")
    text = contents.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n").strip()
    result: list[Cue] = []
    last = 0
    for block in _SPLIT_BLOCKS.split(text):
        lines = block.split("\n")
        if len(lines) < 3 or not re.fullmatch(r"\d{1,9}", lines[0].strip()):
            raise SubtitleApiError("INVALID_SOURCE_CUE_STRUCTURE")
        ordinal = int(lines[0].strip())
        if ordinal <= last or not _START_END.fullmatch(lines[1].strip()):
            raise SubtitleApiError("INVALID_SOURCE_CUE_STRUCTURE")
        content = "\n".join(lines[2:]).strip()
        if not content:
            raise SubtitleApiError("INVALID_SOURCE_CUE_STRUCTURE")
        result.append(Cue(ordinal, lines[1].strip(), content))
        last = ordinal
    if not result:
        raise SubtitleApiError("EMPTY_SUBTITLE")
    return tuple(result)


def iter_batches(cues: tuple[Cue, ...]) -> tuple[Batch, ...]:
    if not cues:
        raise SubtitleApiError("EMPTY_SUBTITLE")
    blocks: list[Batch] = []
    index = 0
    while index < len(cues):
        end = index
        source_chars = 0
        while end < len(cues) and end - index < MAX_CUES_PER_BATCH:
            size = len(cues[end].text)
            if size > MAX_SOURCE_CHARS_PER_BATCH:
                raise SubtitleApiError("TRANSLATION_SOURCE_CUE_TOO_LONG")
            if end > index and source_chars + size > MAX_SOURCE_CHARS_PER_BATCH:
                break
            source_chars += size
            end += 1
        blocks.append(Batch(
            source=cues[index:end],
            before=cues[max(0, index - CONTEXT_CUES):index],
            after=cues[end:min(len(cues), end + CONTEXT_CUES)],
        ))
        index = end
    return tuple(blocks)


def _validate_translation_text(value: str) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 1800:
        raise SubtitleApiError("INVALID_TRANSLATION_TEXT")
    if "\r" in value or "\0" in value or "<script" in value.casefold():
        raise SubtitleApiError("INVALID_TRANSLATION_TEXT")
    if "\n" in value:
        # The ID|VI contract uses literal backslash+n for a line break.
        raise SubtitleApiError("INVALID_TRANSLATION_TEXT")
    text = value.replace("\\n", "\n").strip()
    if not text or any(ord(c) < 32 and c != "\n" for c in text):
        raise SubtitleApiError("INVALID_TRANSLATION_TEXT")
    return text


def translate_en_to_vi(source: Asset, translator: Translator, *,
                       source_rights_confirmed: bool = False,
                       outbound_content_approved: bool = False,
                       api_cost_approved: bool = False) -> Translated:
    """Accept source EN only; all external-model decisions are explicit.

    Provider's run limits/quota, provider choice, and any data processing
    remain outside this module. No network call happens unless all flags are
    True and an injected translator actually sends a request.
    """
    if not (source_rights_confirmed is True
            and outbound_content_approved is True
            and api_cost_approved is True):
        raise SubtitleApiError("TRANSLATION_CONSENT_REQUIRED")
    if source.language != "en" or source.fmt != "srt":
        raise SubtitleApiError("TRANSLATION_SOURCE_MUST_BE_EN_SRT")
    if source.sha256 != hashlib.sha256(source.contents).hexdigest():
        raise SubtitleApiError("SOURCE_DIGEST_MISMATCH")
    cues = parse_srt(source.contents)
    if len(cues) != source.cues:
        raise SubtitleApiError("SOURCE_CUE_COUNT_MISMATCH")

    vi_text_by_id: dict[int, str] = {}
    for batch in iter_batches(cues):
        result = translator(batch)
        expected = {cue.ordinal for cue in batch.source}
        if (not isinstance(result, Mapping)
                or len(result) != len(expected)
                or set(result) != expected
                or any(type(key) is not int for key in result)):
            raise SubtitleApiError("TRANSLATION_ID_COVERAGE_MISMATCH")
        for cue in batch.source:
            text = _validate_translation_text(result[cue.ordinal])
            if cue.ordinal in vi_text_by_id:
                raise SubtitleApiError("DUPLICATE_TRANSLATION_ID")
            vi_text_by_id[cue.ordinal] = text

    output = "\n\n".join(
        f"{cue.ordinal}\n{cue.timeline}\n{vi_text_by_id[cue.ordinal]}"
        for cue in cues
    ).encode("utf-8")
    if validate_timed_text(output, "srt") != len(cues):
        raise SubtitleApiError("TRANSLATION_QA_FAILED")
    if any((a.ordinal != b.ordinal or a.timeline != b.timeline)
           for a, b in zip(cues, parse_srt(output))):
        raise SubtitleApiError("TRANSLATION_TIMELINE_CHANGED")
    return Translated(output, source.sha256, hashlib.sha256(output).hexdigest(),
                      len(cues))
