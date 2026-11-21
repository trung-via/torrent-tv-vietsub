"""P2/P4 progressive subtitle handoff, pure and OFFLINE.

Turns validated, ID-indexed mock/API *results* into immutable, cumulative
SRT/VTT revisions. No provider SDK, HTTP, file I/O, TV control or cloud consent
is implemented here. A future, separately authorized adapter may supply the
translation map and deliver revisions to the exact bound TV media session.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import re
from typing import Mapping

from cue_pipeline import Cue, apply_translations, parse_cues, render

MAX_TARGET_CUES = 120
MAX_TARGET_CHARS = 6500
CONTEXT_CUES = 4
MAX_TV_BYTES = 256 * 1024
MEDIA_KEY = re.compile(r"media\.[0-9a-f]{64}\Z")


@dataclass(frozen=True)
class TranslationWindow:
    number: int
    source_sha256: str
    media_key: str
    ids: tuple[int, ...]
    target: tuple[Cue, ...]
    before: tuple[Cue, ...]
    after: tuple[Cue, ...]


@dataclass(frozen=True)
class SubtitleRevision:
    version: int
    source_sha256: str
    media_key: str
    fmt: str
    translated_count: int
    total_count: int
    last_end_ms: int
    sha256: str
    payload: bytes

    @property
    def complete(self) -> bool:
        return self.translated_count == self.total_count


def _windows(
    cues: tuple[Cue, ...], source_hash: str, key: str,
    max_cues: int, max_chars: int, context: int,
) -> tuple[TranslationWindow, ...]:
    windows: list[TranslationWindow] = []
    start = 0
    while start < len(cues):
        end = start
        size = 0
        while end < len(cues) and end - start < max_cues:
            length = len(cues[end].text)
            if size + length > max_chars:
                break
            size += length
            end += 1
        if end == start:
            raise ValueError("SOURCE_CUE_EXCEEDS_BATCH_BUDGET")
        target = cues[start:end]
        windows.append(TranslationWindow(
            number=len(windows) + 1,
            source_sha256=source_hash,
            media_key=key,
            ids=tuple(c.number for c in target),
            target=target,
            before=cues[max(0, start - context):start],
            after=cues[end:min(len(cues), end + context)],
        ))
        start = end
    return tuple(windows)


class ProgressiveSubtitleSession:
    """Fail-closed revision builder for one **fixed** media+source identity.

    Every commit is all-or-nothing, in increasing contiguous cue order. Stale,
    wrong-media and malformed responses never modify the prior valid revision.
    A future publisher must check both identity and monotonic revision before
    delivery to the TV. No one should assume a revision is auto-delivered.
    """

    def __init__(
        self, source: bytes, fmt: str, media_key: str, *,
        max_cues: int = MAX_TARGET_CUES,
        max_chars: int = MAX_TARGET_CHARS,
        context: int = CONTEXT_CUES,
    ) -> None:
        if not isinstance(media_key, str) or not MEDIA_KEY.fullmatch(media_key):
            raise ValueError("MEDIA_IDENTITY_REQUIRED")
        if type(max_cues) is not int or not 1 <= max_cues <= MAX_TARGET_CUES:
            raise ValueError("BATCH_CUE_LIMIT_INVALID")
        if type(max_chars) is not int or not 1 <= max_chars <= MAX_TARGET_CHARS:
            raise ValueError("BATCH_CHAR_LIMIT_INVALID")
        if type(context) is not int or not 0 <= context <= CONTEXT_CUES:
            raise ValueError("CONTEXT_LIMIT_INVALID")
        if not isinstance(source, bytes):
            raise ValueError("SOURCE_BYTES_REQUIRED")
        self._cues = parse_cues(source, fmt)
        self._hash = hashlib.sha256(source).hexdigest()
        self._fmt = fmt
        self._key = media_key
        self._windows = _windows(
            self._cues, self._hash, media_key, max_cues, max_chars, context
        )
        self._translated: dict[str, str] = {}
        self._revision: SubtitleRevision | None = None

    @property
    def source_sha256(self) -> str:
        return self._hash

    @property
    def media_key(self) -> str:
        return self._key

    @property
    def windows(self) -> tuple[TranslationWindow, ...]:
        return self._windows

    @property
    def revision(self) -> SubtitleRevision | None:
        return self._revision

    def next_window(self) -> TranslationWindow | None:
        version = 0 if self._revision is None else self._revision.version
        return self._windows[version] if version < len(self._windows) else None

    def commit(
        self,
        window: TranslationWindow,
        values: Mapping[int, str],
        *,
        expected_version: int,
        source_sha256: str,
        media_key: str,
    ) -> SubtitleRevision:
        """Commit only exact ordered target IDs; never translate context IDs."""
        current_version = 0 if self._revision is None else self._revision.version
        if type(expected_version) is not int or expected_version != current_version:
            raise ValueError("STALE_REVISION")
        if source_sha256 != self._hash or media_key != self._key:
            raise ValueError("SOURCE_OR_MEDIA_IDENTITY_MISMATCH")
        expected = self.next_window()
        if expected is None:
            raise ValueError("SESSION_ALREADY_COMPLETE")
        if window != expected:
            raise ValueError("WINDOW_IDENTITY_MISMATCH")
        if not isinstance(values, Mapping):
            raise ValueError("TRANSLATION_MAP_REQUIRED")
        if list(values) != list(expected.ids) or any(type(k) is not int for k in values):
            raise ValueError("TRANSLATION_ID_OR_ORDER_MISMATCH")

        # Reuse the strict canonical text validator; do not accept extra cue IDs,
        # timing, HTML or surrogate values from a provider.
        validated = apply_translations(
            expected.target, {str(i): values[i] for i in expected.ids}
        )
        additions = {str(c.number): c.text for c in validated}
        prospective = {**self._translated, **additions}
        last = expected.ids[-1]
        prefix = self._cues[:last]
        translated_prefix = tuple(
            replace(c, text=prospective[str(c.number)]) for c in prefix
        )
        data = render(translated_prefix, self._fmt)
        if len(data) > MAX_TV_BYTES:
            raise ValueError("TV_SUBTITLE_SIZE_LIMIT")
        # Parse again to verify the real player-facing bytes and original timecodes.
        roundtrip = parse_cues(data, self._fmt)
        if len(roundtrip) != last or any(
            (a.number, a.start_ms, a.end_ms, a.identifier, a.settings) !=
            (b.number, b.start_ms, b.end_ms, b.identifier, b.settings)
            for a, b in zip(prefix, roundtrip)
        ):
            raise ValueError("CUMULATIVE_TIMELINE_MISMATCH")
        revised = SubtitleRevision(
            version=current_version + 1,
            source_sha256=self._hash,
            media_key=self._key,
            fmt=self._fmt,
            translated_count=last,
            total_count=len(self._cues),
            last_end_ms=prefix[-1].end_ms,
            sha256=hashlib.sha256(data).hexdigest(),
            payload=data,
        )
        # State is mutated only after every validation succeeds.
        self._translated = prospective
        self._revision = revised
        return revised

    def horizon(self, playback_ms: int, *, warning_ms: int = 15_000) -> str:
        """Numeric horizon metadata only; no interaction with a real player."""
        if type(playback_ms) is not int or playback_ms < 0:
            raise ValueError("PLAYBACK_POSITION_INVALID")
        if type(warning_ms) is not int or warning_ms < 0:
            raise ValueError("WARNING_WINDOW_INVALID")
        if self._revision is None:
            return "NO_SUBTITLES_YET"
        remaining = self._revision.last_end_ms - playback_ms
        if remaining <= 0:
            return "TRANSLATION_BEHIND_PLAYBACK"
        if not self._revision.complete and remaining <= warning_ms:
            return "NEAR_TRANSLATED_HORIZON"
        return "AVAILABLE"
