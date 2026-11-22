"""Offline, deterministic subtitle-release matching. No network, I/O or downloads.

D1 candidate decision only; media metadata and search results must be supplied
by a trusted caller. Actual OpenSubtitles API and TV transport are separate gates.
"""
from __future__ import annotations

from dataclasses import dataclass
import re


_HASH = re.compile(r"[0-9a-fA-F]{16}\Z")
_YEAR = re.compile(r"(?<!\d)(?:19|20)\d{2}(?!\d)")
_VIDEO_EXT = re.compile(r"\.(?:mkv|mp4|avi|mov|webm|srt|vtt|ass|ssa|sub|txt|smi|sami)\Z", re.I)
_GROUP = re.compile(r"-([a-z0-9]{2,30})\Z", re.I)
# Subtitles routinely append language/accessibility markers after the VIDEO
# release group: e.g. "-TEAM_eng SDH" or "-TEAM_eng". Remove only terminal
# recognized labels, never arbitrary tokens from the release group itself.
_SUBTITLE_TRAILING_TAG = re.compile(
    r"(?:[._\s-]+)(en|eng|english|vi|vie|vietnamese|sdh|cc|forced|hearing[._\s-]+impaired)\Z",
    re.I,
)
_RESOLUTION = re.compile(r"(?<!\w)(720p|1080p|2160p|4k)(?!\w)", re.I)
_CODEC = re.compile(r"(?<!\w)(x264|x265|h264|h265|hevc|av1)(?!\w)", re.I)
_SOURCE = re.compile(r"(?<!\w)(blu[- ]?ray|bdrip|brrip|web[- ]?dl|webrip|hdtv)(?!\w)", re.I)
_LANG = {"vi": "vi", "vie": "vi", "vietnamese": "vi", "en": "en", "eng": "en", "english": "en"}


def _hash(value: str | None) -> str | None:
    if value is None:
        return None
    if not _HASH.fullmatch(value):
        raise ValueError("invalid 64-bit movie hash")
    return value.lower()


def _clean(value: str) -> str:
    # Unicode words retain Cyrillic and other scripts for provider fallback.
    # The original ASCII expression silently turned Russian film names empty.
    return " ".join(re.findall(r"[^\W_]+", value.casefold()))


@dataclass(frozen=True)
class Media:
    server_profile_id: str
    torrent_hash: str
    file_index: int
    filename: str
    movie_hash: str | None = None
    torrent_title: str | None = None

    def __post_init__(self) -> None:
        if not self.server_profile_id or not self.torrent_hash or self.file_index < 0 or not self.filename:
            raise ValueError("incomplete media identity")
        _hash(self.movie_hash)
        if self.torrent_title is not None and (
                not isinstance(self.torrent_title, str)
                or not self.torrent_title.strip()
                or len(self.torrent_title) > 512
                or any(ord(c) < 32 or ord(c) == 127
                       for c in self.torrent_title)):
            raise ValueError("invalid torrent display title")

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


def _release_stem_and_accessibility(filename: str) -> tuple[str, bool]:
    """Strip only recognized *terminal* subtitle labels for release matching.

    Metadata like '-TEAM_eng SDH' belongs to video group TEAM; 'eng' is the
    subtitle language and 'SDH' is an accessibility variant. Do not collapse
    two different release groups just because they share title/resolution.
    """
    basename = re.split(r"[/\\]", filename)[-1]
    stem = _VIDEO_EXT.sub("", basename)
    is_sdh = False
    for _ in range(8):
        match = _SUBTITLE_TRAILING_TAG.search(stem)
        if match is None:
            break
        tag = match.group(1).casefold()
        is_sdh = is_sdh or tag in {"sdh", "cc"} or tag.startswith("hearing")
        stem = stem[:match.start()]
    return stem, is_sdh


def parse_release(filename: str) -> Release:
    """Filename hint parser, not authoritative metadata or content verification."""
    stem, _ = _release_stem_and_accessibility(filename)
    group_match = _GROUP.search(stem)
    if group_match and (group_match.group(1).casefold() in {"dl", "rip", "ray", "x264", "x265", "h264", "h265", "720p", "1080p", "2160p"}
                        or _YEAR.fullmatch(group_match.group(1))):
        group_match = None
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


def preferred_media_release(media: Media) -> Release:
    """Rank/search using an international alias from the verified torrent.

    The exact video filename and media.key remain untouched. A bilingual
    Russian/English torrent label is search metadata, not proof that a
    subtitle is synchronized with the selected video. Only the Latin title
    from its explicit alias is used; release facts still come from the file.
    """
    actual = parse_release(media.filename)
    if not media.torrent_title:
        return actual
    parts = re.split(r"\s+/\s+", media.torrent_title, maxsplit=4)
    # Do not override an already-readable filename using an unrelated
    # single-language torrent/folder name (multi-file collections exist).
    if len(parts) == 1 and re.search(r"[a-z]", actual.title):
        return actual
    candidates = parts[1:] if len(parts) > 1 else parts
    for text in candidates:
        # "| P | Jaskier" is an audio/voice-over label, not an EN scene group.
        proposed = parse_release(text.split("|", 1)[0].strip())
        if not proposed.title or not re.search(r"[a-z]", proposed.title):
            continue
        if (actual.year is not None and proposed.year is not None
                and actual.year != proposed.year):
            continue
        if (actual.source is not None and proposed.source is not None
                and actual.source != proposed.source):
            continue
        if (actual.resolution is not None and proposed.resolution is not None
                and actual.resolution != proposed.resolution):
            continue
        return Release(
            title=proposed.title,
            year=actual.year if actual.year is not None else proposed.year,
            source=actual.source or proposed.source,
            resolution=actual.resolution or proposed.resolution,
            codec=actual.codec or proposed.codec,
            group=actual.group,
        )
    return actual


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
    # "provider" is OpenSubtitles metadata with an unverified output format.
    # Rank the release; the D2 download gate must request/verify SRT before use.
    if lang is None or candidate.fmt.lower() not in {"srt", "vtt", "provider"}:
        return None
    reference = preferred_media_release(media)
    proposed = parse_release(candidate.release_name)
    # OpenSubtitles uploads sometimes omit the leading English article from
    # the exact international torrent alias ("The Odyssey" -> "Odyssey").
    # Compare the remaining *complete* title, never a fuzzy token subset.
    def without_the(value: str) -> str:
        return value.removeprefix("the ")

    if (not reference.title or not proposed.title or
            without_the(reference.title) != without_the(proposed.title)):
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
    # A normal English dialogue subtitle is preferred over its same-release
    # SDH variant for AI translation. SDH is still eligible if it is the only
    # good candidate. A 10-point penalty only resolves *otherwise identical*
    # same-release SDH/non-SDH ties; unrelated groups remain below exact group.
    if lang == "en" and _release_stem_and_accessibility(candidate.release_name)[1]:
        score -= 10
        evidence.append("sdh_variant")
    media_hash = _hash(media.movie_hash)
    sub_hash = _hash(candidate.movie_hash)
    exact_hash = media_hash is not None and media_hash == sub_hash
    hash_conflict = media_hash is not None and sub_hash is not None and not exact_hash
    if exact_hash:
        score += 100
        evidence.append("moviehash")
    if hash_conflict:
        evidence.append("different_moviehash")
    # Release labels often omit BDRip/WEB metadata. That should not discard
    # an otherwise unique full title/year/1080p/HEVC match. An *explicit*
    # source, group or resolution conflict still blocks confidence.
    group_conflict = (reference.group is not None and proposed.group is not None
                      and reference.group != proposed.group)
    source_conflict = (reference.source is not None and proposed.source is not None
                       and reference.source != proposed.source)
    resolution_conflict = (reference.resolution is not None
                           and proposed.resolution is not None
                           and reference.resolution != proposed.resolution)
    same_release = (
        reference.year is not None and reference.year == proposed.year
        and not group_conflict and not source_conflict
        # The same scene group may encode the same cut at 720p and 1080p;
        # no known group means 2160p vs 1080p is only an uncertain release.
        and (not resolution_conflict or (
            reference.group is not None and reference.group == proposed.group))
        and (
            (reference.source is not None and reference.source == proposed.source)
            or (reference.resolution is not None
                and reference.resolution == proposed.resolution
                and ((reference.codec is not None and reference.codec == proposed.codec)
                     or (reference.group is not None
                         and reference.group == proposed.group)))
        )
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
        # A high-scoring upload with a *known conflicting release group* is
        # not a plausible runner-up and must not veto a confident candidate.
        choices = [item for item in ranked
                   if item.language == language and item.confident]
        if choices and (len(choices) == 1 or choices[0].score - choices[1].score >= 10):
            return Decision(status, choices[0], ranked)
    return Decision("REVIEW_REQUIRED", None, ranked)
