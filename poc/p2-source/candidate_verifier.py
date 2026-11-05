"""P2-SOURCE: offline, evidence-labeled candidate filter, no search/network/torrent effects.

Receives normalized metadata only from a separately authorized source adapter.
Does not prove rights, media integrity, peer availability, or actual video codec:
those are independent upstream verification gates, never inferred from names.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class Verdict(str, Enum):
    ELIGIBLE_METADATA = "ELIGIBLE_METADATA"
    REJECT = "REJECT"
    UNKNOWN = "UNKNOWN"


class Resolution(str, Enum):
    P1440 = "1440p"  # 2560x1440 minimum
    DCI2K = "dci2k"  # 2048x1080 minimum, explicitly distinct from 1440p


class SeedKind(str, Enum):
    REPORTED = "reported"
    SCRAPED = "scraped"
    CONNECTED = "connected"


@dataclass(frozen=True)
class SeedObservation:
    kind: SeedKind
    count: int
    source: str
    observed_at: str  # RFC3339 timestamp; provenance, not proof of freshness

    def __post_init__(self):
        if not isinstance(self.count, int) or isinstance(self.count, bool) or self.count < 0:
            raise ValueError("seed_count_must_be_nonnegative_integer")
        if not self.source.strip() or not self.observed_at.strip():
            raise ValueError("seed_provenance_required")


@dataclass(frozen=True)
class Candidate:
    opaque_id: str
    source_id: str
    source_authorized: bool  # from trusted adapter policy, NOT candidate name/claim
    file_size_bytes: Optional[int]
    width_px: Optional[int]
    height_px: Optional[int]
    video_codec: Optional[str]
    audio_languages: tuple[str, ...] = ()
    observations: tuple[SeedObservation, ...] = ()

    def __post_init__(self):
        if not self.opaque_id or not self.source_id:
            raise ValueError("opaque_identity_and_source_required")
        for value in (self.file_size_bytes, self.width_px, self.height_px):
            if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value <= 0):
                raise ValueError("metadata_must_be_positive_integer_or_unknown")
        if not isinstance(self.source_authorized, bool):
            raise ValueError("trusted_source_authorized_must_be_boolean")


@dataclass(frozen=True)
class Criteria:
    min_bytes: Optional[int] = None
    max_bytes: Optional[int] = None
    min_seeds: Optional[int] = None
    seed_kind: SeedKind = SeedKind.REPORTED
    resolution: Optional[Resolution] = None
    require_audio_vi: bool = False

    def __post_init__(self):
        for value in (self.min_bytes, self.max_bytes, self.min_seeds):
            if value is not None and (not isinstance(value, int) or isinstance(value, bool) or value < 0):
                raise ValueError("invalid_criteria_number")
        if self.min_bytes is not None and self.max_bytes is not None and self.min_bytes > self.max_bytes:
            raise ValueError("inverted_size_range")


@dataclass(frozen=True)
class Assessment:
    opaque_id: str
    verdict: Verdict
    reasons: tuple[str, ...]
    seed_kind: Optional[SeedKind] = None
    seed_observation: Optional[SeedObservation] = None
    # Caution: this verdict is never permission to add torrent, stream, or publish.


def assess(candidate: Candidate, criteria: Criteria) -> Assessment:
    rejected: list[str] = []
    unknown: list[str] = []
    selected: Optional[SeedObservation] = None

    # Authorization is a required upstream gate. Missing/false does not mean
    # copyrighted content can be fetched or used.
    if not candidate.source_authorized:
        rejected.append("SOURCE_NOT_AUTHORIZED")

    if criteria.min_bytes is not None or criteria.max_bytes is not None:
        if candidate.file_size_bytes is None:
            unknown.append("SIZE_UNVERIFIED")
        else:
            if criteria.min_bytes is not None and candidate.file_size_bytes < criteria.min_bytes:
                rejected.append("SIZE_BELOW_MINIMUM")
            if criteria.max_bytes is not None and candidate.file_size_bytes > criteria.max_bytes:
                rejected.append("SIZE_ABOVE_MAXIMUM")

    if criteria.resolution is not None:
        if candidate.width_px is None or candidate.height_px is None:
            unknown.append("VIDEO_DIMENSIONS_UNVERIFIED")
        else:
            minimum = {
                Resolution.P1440: (2560, 1440),
                Resolution.DCI2K: (2048, 1080),
            }[criteria.resolution]
            if candidate.width_px < minimum[0] or candidate.height_px < minimum[1]:
                rejected.append("RESOLUTION_BELOW_" + criteria.resolution.value.upper())

    if criteria.require_audio_vi:
        languages = {x.lower().strip() for x in candidate.audio_languages}
        if not languages:
            unknown.append("AUDIO_TRACK_METADATA_UNVERIFIED")
        elif not languages.intersection({"vi", "vie", "vietnamese"}):
            rejected.append("NO_REPORTED_VI_AUDIO")

    if criteria.min_seeds is not None:
        matching = [x for x in candidate.observations if x.kind == criteria.seed_kind]
        if len(matching) != 1:
            unknown.append("SEED_OBSERVATION_MISSING_OR_AMBIGUOUS_" + criteria.seed_kind.value.upper())
        else:
            selected = matching[0]
            if selected.count < criteria.min_seeds:
                rejected.append("SEEDS_BELOW_MINIMUM_" + criteria.seed_kind.value.upper())

    if rejected:
        return Assessment(candidate.opaque_id, Verdict.REJECT, tuple(rejected + unknown), criteria.seed_kind if criteria.min_seeds is not None else None, selected)
    if unknown:
        return Assessment(candidate.opaque_id, Verdict.UNKNOWN, tuple(unknown), criteria.seed_kind if criteria.min_seeds is not None else None, selected)
    return Assessment(candidate.opaque_id, Verdict.ELIGIBLE_METADATA, ("UPSTREAM_CONFIRMATION_STILL_REQUIRED",), criteria.seed_kind if criteria.min_seeds is not None else None, selected)
