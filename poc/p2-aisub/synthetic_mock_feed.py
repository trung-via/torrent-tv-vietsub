"""Deterministic, synthetic-only P4 subtitle revisions for LAN acceptance.

This is a DEV TEST fixture, not translation of film content. No Gemini API,
file discovery, real subtitle ingestion, listener or background work on import.
The caller must explicitly opt in and start its own private LAN listener.
"""
from __future__ import annotations

import base64
import hashlib
import json
import time
from typing import Callable

from lan_revision_feed import SessionRevisionFeed
from progressive_handoff import ProgressiveSubtitleSession, SubtitleRevision

_SYNTHETIC_CUES = 240


def synthetic_source_srt() -> bytes:
    """Two full 120-cue windows with immutable, synthetic timestamps."""
    lines: list[str] = []
    for number in range(1, _SYNTHETIC_CUES + 1):
        start = number * 2
        end = start + 1
        hh, mm, ss = start // 3600, (start // 60) % 60, start % 60
        eh, em, es = end // 3600, (end // 60) % 60, end % 60
        lines.append(
            f"{number}\n{hh:02d}:{mm:02d}:{ss:02d},000 --> "
            f"{eh:02d}:{em:02d}:{es:02d},000\n"
            f"TTV_SYNTHETIC_EN_{number:03d}\n"
        )
    return ("\n".join(lines) + "\n").encode("utf-8")


def synthetic_source_sha256() -> str:
    return hashlib.sha256(synthetic_source_srt()).hexdigest()


def publish_synthetic_revisions(
    media_key: str,
    feed: SessionRevisionFeed,
    *,
    hold_seconds: float = 20.0,
    wait: Callable[[float], None] = time.sleep,
) -> tuple[SubtitleRevision, SubtitleRevision]:
    """Publish 120, hold, then 240 to *one already authenticated* feed.

    Requires an exact media/source hash match. The PC owner separately starts
    the listener; this function never opens a socket or touches user media.
    The default hold accommodates the TV's 6-second polling cycle.
    """
    if feed.media_key != media_key or feed.source_sha256 != synthetic_source_sha256():
        raise ValueError("P4_SYNTHETIC_FEED_IDENTITY_MISMATCH")
    if not isinstance(hold_seconds, (int, float)) or not 0 <= hold_seconds <= 120:
        raise ValueError("P4_SYNTHETIC_HOLD_INVALID")
    session = ProgressiveSubtitleSession(synthetic_source_srt(), "srt", media_key)
    if len(session.windows) != 2 or tuple(len(w.ids) for w in session.windows) != (120, 120):
        raise ValueError("P4_SYNTHETIC_WINDOWS_INVALID")

    results: list[SubtitleRevision] = []
    for i, window in enumerate(session.windows):
        revision = session.commit(
            window,
            {cue_id: f"Phụ đề giả lập {cue_id:03d}" for cue_id in window.ids},
            expected_version=i,
            source_sha256=session.source_sha256,
            media_key=session.media_key,
        )
        feed.publish(revision)
        results.append(revision)
        if i == 0:
            wait(hold_seconds)
    return results[0], results[1]


def decode_latest_test_only(feed: SessionRevisionFeed) -> dict:
    """Offline test convenience, never part of the LAN wire protocol."""
    payload = feed.latest()
    if payload is None:
        raise ValueError("P4_SYNTHETIC_FEED_EMPTY")
    return json.loads(payload)
