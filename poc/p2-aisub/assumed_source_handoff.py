"""P2 source handoff when *an external workflow already supplied* an EN SRT/VTT.

User decision: defer Brain subtitle discovery/verification. Do not invent
that a matching subtitle has been found. This contract validates structure
and exact media identity, then passes the supplied bytes to configurable
LEAN120 API→P4 cumulative revision feed.

No implicit network, API request, file discovery or background service.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re

from cue_pipeline import parse_cues
from lan_revision_feed import SessionRevisionFeed, translate_into_feed
from lean120_api import ModelProfile
from progressive_handoff import SubtitleRevision

MEDIA = re.compile(r"media\.[0-9a-f]{64}\Z")
MAX_SOURCE_BYTES = 256 * 1024


@dataclass(frozen=True)
class AssumedEnglishSubtitle:
    media_key: str
    fmt: str
    source_sha256: str
    cue_count: int
    source_bytes: bytes
    source_status: str = "ASSUMED_MATCHED_EN_TIMED_TEXT"

    @classmethod
    def from_supplied(cls, *, media_key: str, fmt: str,
                      source_bytes: bytes) -> "AssumedEnglishSubtitle":
        """The caller, not this module, asserts a correct EN subtitle match.

        This checks UTF-8, timing/IDs and opaque film key only. It cannot
        determine whether words or language truly match a film.
        """
        if not isinstance(media_key, str) or not MEDIA.fullmatch(media_key):
            raise ValueError("ASSUMED_SOURCE_MEDIA_KEY_INVALID")
        if fmt not in ("srt", "vtt"):
            raise ValueError("ASSUMED_SOURCE_FORMAT_INVALID")
        if (not isinstance(source_bytes, bytes) or
                not 0 < len(source_bytes) <= MAX_SOURCE_BYTES):
            raise ValueError("ASSUMED_SOURCE_BYTES_INVALID")
        cues = parse_cues(source_bytes, fmt)
        return cls(
            media_key, fmt, hashlib.sha256(source_bytes).hexdigest(),
            len(cues), bytes(source_bytes)
        )


def translate_supplied_to_feed(
    handoff: AssumedEnglishSubtitle, profile: ModelProfile,
    *, feed: SessionRevisionFeed, glossary: dict[str, str],
    api_key: str, transport: object,
) -> tuple[SubtitleRevision, ...]:
    """Explicit API invocation, with film/source preflight before tokens.

    The provided transport is injectable for an offline fake provider.
    Human approves actual media text/cloud upload in a separate live gate.
    """
    if not isinstance(handoff, AssumedEnglishSubtitle) or handoff.source_status != (
        "ASSUMED_MATCHED_EN_TIMED_TEXT"
    ):
        raise ValueError("ASSUMED_SOURCE_HANDOFF_REQUIRED")
    expected = AssumedEnglishSubtitle.from_supplied(
        media_key=handoff.media_key, fmt=handoff.fmt,
        source_bytes=handoff.source_bytes,
    )
    if (expected.source_sha256 != handoff.source_sha256 or
        expected.cue_count != handoff.cue_count):
        raise ValueError("ASSUMED_SOURCE_HASH_OR_CUES_CHANGED")
    if (feed.media_key != handoff.media_key or
            feed.source_sha256 != handoff.source_sha256):
        raise ValueError("ASSUMED_SOURCE_FEED_SCOPE_INVALID")
    return translate_into_feed(
        handoff.source_bytes, handoff.fmt, handoff.media_key, profile,
        feed=feed, glossary=glossary, api_key=api_key,
        transport=transport,
    )
