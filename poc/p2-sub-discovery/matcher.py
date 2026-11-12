"""Offline, deterministic subtitle-release matching. No network, I/O or downloads.

D1 candidate decision only; media metadata and search results must be supplied
by a trusted caller. Actual OpenSubtitles API and TV transport are separate gates.
"""
from __future__ import annotations

from dataclasses import dataclass
import re


_HASH = re.compile(r"[0-9a-fA-F]{16}\\Z")
_YEAR = re.compile(r"(?<!\\d)(?:19|20)\\d{2}(?!\\d)")
_VIDEO_EXT = re.compile(r"\\.(?:mkv|mp4|avi|mov|webm|srt|vtt)\\Z", re.I)
_GROUP = re.compile(r"-([a-z0-9]{2,30})\\Z", re.I)
_RESOLUTION = re.compile(r"(?<!\\w)(720p|1080p|2160p|4k)(?!\\w)", re.I)
_CODEC = re.compile(r"(?<!\\w)(x264|x265|h264|h265|hevc|av1)(?!\\w)", re.I)
_SOURCE = re.compile(r"(?<!\\w)(bluray|blu ray|bdrip|brrip|web[- ]?dl|webrip|hdtv)(?!\\w)", re.I)
_LANG = {"vi": "vi", "vie": "vi", "vietnamese": "vi", "en": "en", "eng": "en", "english": "en"}


def _hash(value: str | None) -> str | None:
    if value is None:
        return None
    if not _HASH.fullmatch(value):
        raise ValueError("invalid 64-bit movie hash")
    return value.lower()


def _clean(value: str) -> str:
    return " ".join(re.findall(r"[a-z0-9]+", value.casefold()))


@dataclass(frozen=True)
class Media:
    server_profile_id: str
    torrent_hash: str
    file_index: int
    filename: str
    movie_hash: str | None = None

    def __post_init__(self) -> None:
        if not self.server_profile_id or not self.torrent_hash or self.file_index < 0 or not self.filename:
            raise ValueError("incomplete media identity")
        _hash(self.movie_hash)

    @property
    def key(self) -> tuple[str, str, int]:
        return (self.server_profile_id, self.torrent_hash, self.file_index)


@dataclass(frozen=True)
class Subtitle:
    subtitle_id: str
    release_name: str
    language: str
    fmt: str = "srt"
    movie_hash: str | None = None


@dataclass(frozen=True)
class SearchResults:
    media_key: tuple[str, str, int]
    subtitles: tuple[Subtitle, ...]


@dataclass(frozen=True)
class Release:
    title: str
    year: int | None
    source: str | None
    resolution: str | None
    codec: str | None
    group: str | None


def parse_release(filename: str) -> Release:
    """Filename hint parser, not authoritative metadata or content verification."""
    basename = re.split(r"[/\\\\]", filename)[-1]
    stem = _VIDEO_EXT.sub("", basename)
    group_match = _GROUP.search(stem)
    group = group_match.group(1).casefold() if group_match else None
    if group_match:
        stem = stem[:group_match.start()]
    searchable = re.sub(r"[._]+", " ", stem).lower()
    year_match = _YEAR.search(searchable)
    source_match = _SOURCE.search(searchable)
    resolution_match = _RESOLUTION.search(searchable)
    codec_match = _CODEC.search(searchable)
    cut_points = [m.start() for m in (year_match, source_match, resolution_match, codec_match) if m]
    title = _clean(searchable[:min(cut_points)] if cut_points else searchable)
    raw_source = source_match.group(1).replace("-", "").replace(" ", "") if source_match else None
    source = "bluray" if raw_source in {"bluray", "bdrip", "brrip"} else (
        "web" if raw_source in {"webdl", "webrip"} else raw_source
    )
    return Release(
        title=title,
        year=int(year_match.group()) if year_match else None,
        source=source,
        resolution=resolution_match.group(1).lower() if resolution_match else None,
        codec=codec_match.group(1).lower() if codec_match else None,
        group=group,
    )


@dataclass(frozen=True)
class Ranked:
    subtitle_id: str
    language: str
    score: int
    confident: bool
    evidence: tuple[str, ...]


@dataclass(frozen=True)
class Decision:
    status: str  # VI_MATCH | EN_TRANSLATE | REVIEW_REQUIRED | NO_MATCH
    winner: Ranked | None
    ranked: tuple[Ranked, ...]


def _rank(media: Media, candidate: Subtitle) -> Ranked | None:
    lang = _LANG.get(candidate.language.lower())
    if lang is None or candidate.fmt.lower() not in {"srt", "vtt"}:
        return None
    reference = parse_release(media.filename)
    proposed = parse_release(candidate.release_name)
    if not reference.title or not proposed.title or reference.title != proposed.title:
        return None
    if reference.year is not None and proposed.year is not None and reference.year != proposed.year:
        return None
    score, evidence = 40, ["title"]
    if reference.year is not None and reference.year == proposed.year:
        score += 15
        evidence.append("year")
    if reference.source is not None and reference.source == proposed.source:
        score += 12
        evidence.append("source")
    if reference.group is not None and reference.group == proposed.group:
        score += 25
        evidence.append("group")
    if reference.resolution is not None and reference.resolution == proposed.resolution:
        score += 3
        evidence.append("resolution")
    if reference.codec is not None and reference.codec == proposed.codec:
        score += 2
        evidence.append("codec")
    media_hash = _hash(media.movie_hash)
    sub_hash = _hash(candidate.movie_hash)
    exact_hash = media_hash is not None and media_hash == sub_hash
    hash_conflict = media_hash is not None and sub_hash is not None and not exact_hash
    if exact_hash:
        score += 100
        evidence.append("moviehash")
    if hash_conflict:
        evidence.append("different_moviehash")
    same_release = (
        reference.year is not None and reference.year == proposed.year
        and reference.source is not None and reference.source == proposed.source
        and reference.group is not None and reference.group == proposed.group
    )
    confident = not hash_conflict and (exact_hash or same_release)
    return Ranked(candidate.subtitle_id, lang, score, confident, tuple(evidence))


def choose(media: Media, results: SearchResults) -> Decision:
    """Prefer confidently matched VI, then EN; ambiguous/weak -> human review.

    A search response for another TorrServer file cannot be reused across titles,
    even if the displayed filenames are identical.
    """
    if results.media_key != media.key:
        raise ValueError("media binding mismatch")
    ids = [c.subtitle_id for c in results.subtitles]
    if len(ids) != len(set(ids)) or any(not v for v in ids):
        raise ValueError("duplicate or empty subtitle ID")
    ranked = tuple(sorted(
        (item for sub in results.subtitles if (item := _rank(media, sub)) is not None),
        key=lambda r: (-r.score, r.language, r.subtitle_id),
    ))
    if not ranked:
        return Decision("NO_MATCH", None, ranked)
    for language, status in (("vi", "VI_MATCH"), ("en", "EN_TRANSLATE")):
        choices = [item for item in ranked if item.language == language]
        if choices and choices[0].confident and (len(choices) == 1 or choices[0].score - choices[1].score >= 10):
            return Decision(status, choices[0], ranked)
    return Decision("REVIEW_REQUIRED", None, ranked)
