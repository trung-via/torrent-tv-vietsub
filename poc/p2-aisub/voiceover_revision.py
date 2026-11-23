"""Offline contract for one AGY translation revision -> incremental voice-over cues.

This module NEVER downloads subtitles, calls AGY/VieNeu, starts a service,
modifies the TV or publishes to LAN. The existing SubtitleRevision is the sole
translated source for both subtitle delivery and the optional TTS consumer.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re
from typing import Sequence

from cue_pipeline import parse_cues
from progressive_handoff import SubtitleRevision

_VOICE = re.compile(r"[a-zA-Z0-9_-]{1,64}\\Z")


@dataclass(frozen=True)
class NarrationCue:
    number: int
    start_ms: int
    end_ms: int
    text: str
    tts_key: str


@dataclass(frozen=True)
class VoiceoverPlan:
    media_key: str
    source_sha256: str
    revision_version: int
    revision_sha256: str
    voice_id: str
    translated_count: int
    completed_count: int
    new_cues: tuple[NarrationCue, ...]

    @property
    def is_caught_up(self) -> bool:
        return not self.new_cues


def _audio_key(revision: SubtitleRevision, cue: object, voice_id: str) -> str:
    # Key never depends on the ephemeral TV session. Reopening A can reuse
    # audio, while only the live player session may receive/play it.
    canonical = {
        "schema": "TTV-VOICEOVER-CUE-V1",
        "media_key": revision.media_key,
        "source_sha256": revision.source_sha256,
        "voice_id": voice_id,
        "number": cue.number,
        "start_ms": cue.start_ms,
        "end_ms": cue.end_ms,
        "text": cue.text,
    }
    body = json.dumps(canonical, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(body).hexdigest()


def plan_voiceover(
    revision: SubtitleRevision, *, voice_id: str,
    completed_keys: Sequence[str] = (),
) -> VoiceoverPlan:
    """Pure, deterministic incremental planner.

    completed_keys are durable, verified TTS-success receipts for the exact
    contiguous cue prefix, not merely previously enqueued work. Failed,
    interrupted and ambiguous TTS outputs are never marked completed here.
    """
    if not isinstance(revision, SubtitleRevision):
        raise ValueError("VOICEOVER_SUBTITLE_REVISION_REQUIRED")
    if not isinstance(voice_id, str) or not _VOICE.fullmatch(voice_id):
        raise ValueError("VOICEOVER_VOICE_ID_INVALID")
    if type(revision.version) is not int or revision.version < 1:
        raise ValueError("VOICEOVER_REVISION_VERSION_INVALID")
    if (not isinstance(revision.payload, bytes)
            or hashlib.sha256(revision.payload).hexdigest() != revision.sha256):
        raise ValueError("VOICEOVER_REVISION_DIGEST_MISMATCH")
    if not isinstance(completed_keys, (tuple, list)) or any(
            not isinstance(key, str) or not re.fullmatch(r"[0-9a-f]{64}", key)
            for key in completed_keys):
        raise ValueError("VOICEOVER_RECEIPT_INVALID")
    cues = parse_cues(revision.payload, revision.fmt)
    if (len(cues) != revision.translated_count
            or revision.translated_count > revision.total_count
            or cues[-1].end_ms != revision.last_end_ms):
        raise ValueError("VOICEOVER_REVISION_CUES_INVALID")
    if len(completed_keys) > len(cues):
        raise ValueError("VOICEOVER_RECEIPT_AHEAD_OF_REVISION")
    for index, received in enumerate(completed_keys):
        if received != _audio_key(revision, cues[index], voice_id):
            raise ValueError("VOICEOVER_RECEIPT_PREFIX_MISMATCH")
    new_cues = tuple(NarrationCue(
        number=c.number, start_ms=c.start_ms, end_ms=c.end_ms,
        text=" ".join(c.text.split()),
        tts_key=_audio_key(revision, c, voice_id),
    ) for c in cues[len(completed_keys):])
    return VoiceoverPlan(
        media_key=revision.media_key,
        source_sha256=revision.source_sha256,
        revision_version=revision.version,
        revision_sha256=revision.sha256,
        voice_id=voice_id,
        translated_count=revision.translated_count,
        completed_count=len(completed_keys),
        new_cues=new_cues,
    )


def assess_voice_fit(*, cue_duration_ms: int, audio_duration_ms: int,
                     max_speed: float = 1.25) -> str:
    """Recommend a renderer action; never truncate or distort speech silently."""
    if (type(cue_duration_ms) is not int or cue_duration_ms <= 0
            or type(audio_duration_ms) is not int or audio_duration_ms <= 0
            or not 1.0 <= max_speed <= 1.5):
        raise ValueError("VOICEOVER_TIMING_INVALID")
    if audio_duration_ms <= cue_duration_ms:
        return "PLAY_AS_IS"
    if audio_duration_ms <= cue_duration_ms * max_speed:
        return "TIME_STRETCH"
    return "REWRITE_OR_USE_ORIGINAL_AUDIO"
