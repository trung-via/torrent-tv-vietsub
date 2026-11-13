"""VI-first OpenSubtitles routing, EN fallback only after confident source match.

GET-only route. D1 confidence is release/hash evidence, NOT verified video sync.
No download, AI API request, TV control or file I/O in this module.
"""
from __future__ import annotations

from dataclasses import dataclass

from matcher import Media, SearchResults, choose
from opensubtitles import Candidate, Discovery, OpenSubtitles, SubtitleApiError


@dataclass(frozen=True)
class Route:
    status: str  # VI_READY | EN_TRANSLATE | REVIEW_REQUIRED | NO_MATCH
    reason: str
    language: str | None
    selected_file_id: int | None
    vi: Discovery
    en: Discovery | None
    get_requests: int
    video_sync_verified: bool = False


def _discover_complete(client: OpenSubtitles, media: Media, *,
                       language: str, imdb_id: str) -> tuple[Discovery, bool, int]:
    """At most 2 GETs; treat partial pagination as non-authoritative."""
    first = client.search(media, language=language, query_mode="imdb",
                          imdb_id=imdb_id, page=1)
    pages = [first]
    if (first.raw_rows == 50 and
            (first.api_total is None or first.api_total > first.raw_rows)):
        pages.append(client.search(media, language=language,
                                   query_mode="imdb", imdb_id=imdb_id, page=2))
    seen: dict[int, Candidate] = {}
    for part in pages:
        if part.media_key != media.key or part.results.media_key != media.key:
            raise SubtitleApiError("MEDIA_BINDING_MISMATCH")
        for c in part.candidates:
            if c.subtitle.language != language:
                raise SubtitleApiError("CROSS_LANGUAGE_SEARCH_ROW")
            if c.file_id in seen:
                if seen[c.file_id] != c:
                    raise SubtitleApiError("CONFLICTING_PROVIDER_CANDIDATE")
                continue
            seen[c.file_id] = c
    all_candidates = tuple(seen.values())
    results = SearchResults(media.key, tuple(c.subtitle for c in all_candidates))
    raw_rows = sum(p.raw_rows for p in pages)
    total = first.api_total
    complete = ((total is not None and raw_rows >= total)
                or (total is None and pages[-1].raw_rows < 50))
    merged = Discovery(media.key, results, all_candidates, choose(media, results),
                       raw_rows=raw_rows, api_total=total)
    return merged, complete, len(pages)


def select_vi_then_en(client: OpenSubtitles, media: Media, *,
                      imdb_id: str) -> Route:
    """VI wins only on confident, unambiguous match. Otherwise examine EN.

    Never promote a weaker VI/EN candidate into an automatic match. When VI
    pagination is incomplete, EN must NOT preempt an unseen VI candidate.
    """
    vi, vi_complete, vi_gets = _discover_complete(
        client, media, language="vi", imdb_id=imdb_id)
    if not vi_complete:
        return Route("REVIEW_REQUIRED", "VI_COVERAGE_INCOMPLETE", None, None,
                     vi, None, vi_gets)
    if vi.decision.status == "VI_MATCH" and vi.decision.winner is not None:
        return Route("VI_READY", "CONFIDENT_VI_RELEASE", "vi",
                     int(vi.decision.winner.subtitle_id), vi, None, vi_gets)
    en, en_complete, en_gets = _discover_complete(
        client, media, language="en", imdb_id=imdb_id)
    total = vi_gets + en_gets
    if not en_complete:
        return Route("REVIEW_REQUIRED", "EN_COVERAGE_INCOMPLETE",
                     None, None, vi, en, total)
    if en.decision.status == "EN_TRANSLATE" and en.decision.winner is not None:
        return Route("EN_TRANSLATE", "CONFIDENT_EN_RELEASE", "en",
                     int(en.decision.winner.subtitle_id), vi, en, total)
    if vi.decision.ranked or en.decision.ranked:
        return Route("REVIEW_REQUIRED", "NO_CONFIDENT_UNAMBIGUOUS_RELEASE",
                     None, None, vi, en, total)
    return Route("NO_MATCH", "NO_RANKABLE_SUBTITLES",
                 None, None, vi, en, total)
