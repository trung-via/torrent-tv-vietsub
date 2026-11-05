"""Offline adapter for pinned OMP SourceResult -> P2-SOURCE candidate assessment.

Pinned OMP source contracts: src/sources/registry.ts, src/sources/types.ts,
src/api/types.ts at 52ab2df11bc54749ad7ad3d8771e2f0ce1f9550f.

NO fetching a tracker, Torznab, torrent/magnet, TorrServer or TV. No inference
of width/height/codec/VI track from a title, category or source display name.
The caller must supply *trusted origin and grant*, not a grant from a result.
"""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from hashlib import sha256
from typing import Any, Mapping, Sequence

from candidate_verifier import (
    Assessment, Candidate, Criteria, SeedKind, SeedObservation, assess,
)


@dataclass(frozen=True)
class ApprovedOrigin:
    """Authorization decided outside the untrusted search result.

    source_id must be the source id supplied by OMP onResult(sourceId, rows).
    tracker_id must come from an independent approved adapter configuration.
    approved reflects the user's rights/ToS decision for that exact pairing.
    """

    source_id: str
    tracker_id: str
    approved: bool

    def __post_init__(self) -> None:
        if self.source_id != "ts-torznab":
            raise ValueError("ONLY_PINNED_OMP_TS_TORZNAB")
        if not isinstance(self.tracker_id, str) or not self.tracker_id.strip():
            raise ValueError("TRUSTED_TRACKER_ID_REQUIRED")
        if not isinstance(self.approved, bool):
            raise ValueError("EXPLICIT_TRUSTED_GRANT_REQUIRED")


def _captured_at(value: str) -> str:
    """A caller-supplied observation timestamp, never CreateDate (release date)."""
    if not isinstance(value, str) or not value:
        raise ValueError("OBSERVATION_TIME_REQUIRED")
    try:
        d = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError("OBSERVATION_TIME_INVALID") from exc
    if d.tzinfo is None or d.utcoffset() is None:
        raise ValueError("OBSERVATION_TIME_NOT_TIMEZONE_AWARE")
    return value


def _opaque_result_id(source: str, tracker: str, raw: Mapping[str, Any]) -> str:
    """Do not log/store names, magnet URIs, tracker passkeys or HTTP download URLs."""
    # Hash identifies a release when it is properly formed; groupKey may be
    # a URL with sensitive query params, so never include it in the response.
    ident = raw.get("hash") or raw.get("Hash")
    if not isinstance(ident, str) or len(ident) != 40 or any(c not in "0123456789abcdefABCDEF" for c in ident):
        ident = raw.get("groupKey") or raw.get("Title") or ""
    if not isinstance(ident, str):
        ident = ""
    digest = sha256(("\x00".join((source, tracker, ident[:4096]))).encode("utf-8")).hexdigest()
    return digest


def _valid_positive_bytes(value: Any) -> int | None:
    return value if type(value) is int and value > 0 else None


def _valid_reported_seeds(value: Any) -> int | None:
    return value if type(value) is int and value >= 0 else None


def candidate_from_omp_result(
    row: Mapping[str, Any], origin: ApprovedOrigin, observed_at: str
) -> Candidate:
    """Normalize the exact OMP SourceResult keys; fail closed on malformed claims.

    P2-SOURCE.1 Candidate has no field asserting media has been probed.
    OMP search result carries Seed and sizeBytes, not verified stream dimensions,
    actual audio tracks, actual connected peers or confirmed playable codec.
    """
    _captured_at(observed_at)
    if not isinstance(row, Mapping):
        raise ValueError("OMP_ROW_EXPECTED")
    row_source = row.get("source")
    row_tracker = row.get("Tracker")
    matched = row_source == origin.source_id and row_tracker == origin.tracker_id
    # Existing OMP merger can combine different sources; never allow
    # r.sources to expand a grant from the actual selected primary source.
    authorized = origin.approved and matched
    tracker = row_tracker if isinstance(row_tracker, str) else ""
    result_id = _opaque_result_id(origin.source_id, origin.tracker_id, row)
    reported = _valid_reported_seeds(row.get("Seed"))
    observation = (
        (SeedObservation(SeedKind.REPORTED, reported, origin.source_id + ":" + origin.tracker_id, observed_at),)
        if reported is not None and matched else ()
    )
    size_bytes = _valid_positive_bytes(row.get("sizeBytes"))
    return Candidate(
        opaque_id=result_id,
        source_id=origin.source_id,
        source_authorized=authorized,
        file_size_bytes=size_bytes,
        width_px=None,  # not in OMP SourceResult; needs actual media probe
        height_px=None,
        video_codec=None,
        audio_languages=(),  # not proven by release title
        observations=observation,
    )


def assess_omp_results(
    rows: Sequence[Mapping[str, Any]],
    origin: ApprovedOrigin,
    observed_at: str,
    criteria: Criteria,
) -> list[Assessment]:
    _captured_at(observed_at)
    if not isinstance(rows, (list, tuple)) or len(rows) > 100:
        raise ValueError("MAX_100_ROWS_PER_SNAPSHOT")
    return [assess(candidate_from_omp_result(row, origin, observed_at), criteria) for row in rows]
