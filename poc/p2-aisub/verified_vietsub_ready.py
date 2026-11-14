"""Strict already-ready Vietsub source for the EXISTING signed P4 feed.

This is not an alternate translator, an OpenSubtitles client or a provider.
The registry producer MUST independently bind the source to verified current
TV/TorrServer media. These objects carry only owner-private subtitle bytes.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re

from cue_pipeline import parse_cues
from progressive_handoff import SubtitleRevision, MAX_TV_BYTES

_MEDIA = re.compile(r"media\.[0-9a-f]{64}\Z")
_STATUS = "P3_OWNER_VERIFIED_VI_READY_V1"


@dataclass(frozen=True)
class VerifiedVietsubReady:
    media_key: str
    source_language: str  # 'vi' from VI_FAST or 'en' after existing LEAN120
    source_bytes: bytes
    payload: bytes
    source_sha256: str
    payload_sha256: str
    cue_count: int
    source_status: str = _STATUS

    @classmethod
    def from_verified_bytes(
        cls, *, media_key: str, source_language: str,
        source_bytes: bytes, vietsub_bytes: bytes,
    ) -> "VerifiedVietsubReady":
        if (type(media_key) is not str or not _MEDIA.fullmatch(media_key)
                or source_language not in ("vi", "en")
                or type(source_bytes) is not bytes
                or type(vietsub_bytes) is not bytes
                or not 0 < len(source_bytes) <= MAX_TV_BYTES
                or not 0 < len(vietsub_bytes) <= MAX_TV_BYTES):
            raise ValueError("P4_READY_BYTES_OR_SCOPE_INVALID")
        source = parse_cues(source_bytes, "srt")
        translated = parse_cues(vietsub_bytes, "srt")
        if (not source or not translated
                or len(source) > 2000  # existing P4SignedReceiver contract
                or len(source) != len(translated)
                or any((a.number, a.start_ms, a.end_ms, a.identifier, a.settings)
                       != (b.number, b.start_ms, b.end_ms, b.identifier, b.settings)
                       for a, b in zip(source, translated))
                or (source_language == "vi" and source_bytes != vietsub_bytes)):
            raise ValueError("P4_READY_TIMELINE_OR_LANGUAGE_MISMATCH")
        return cls(
            media_key=media_key, source_language=source_language,
            source_bytes=source_bytes, payload=vietsub_bytes,
            source_sha256=hashlib.sha256(source_bytes).hexdigest(),
            payload_sha256=hashlib.sha256(vietsub_bytes).hexdigest(),
            cue_count=len(source),
        )

    def as_final_revision(self) -> SubtitleRevision:
        # A ready artifact publishes ONE full, cumulative revision; it does
        # not claim live 120->240 streaming during translation.
        refreshed = self.from_verified_bytes(
            media_key=self.media_key, source_language=self.source_language,
            source_bytes=self.source_bytes, vietsub_bytes=self.payload)
        if refreshed != self or self.source_status != _STATUS:
            raise ValueError("P4_READY_SOURCE_CHANGED")
        last = parse_cues(self.payload, "srt")[-1]
        return SubtitleRevision(
            version=1, source_sha256=self.source_sha256,
            media_key=self.media_key, fmt="srt",
            translated_count=self.cue_count, total_count=self.cue_count,
            last_end_ms=last.end_ms, sha256=self.payload_sha256,
            payload=self.payload,
        )
