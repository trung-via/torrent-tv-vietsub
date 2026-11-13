"""Configurable fast subtitle discovery: VI_FAST (default), EN_DIRECT, VI_FULL.

Match metadata before consuming download quota. Release-group/1080p are useful
owner heuristics, never proof of actual video sync. Moviehash is optional and
may be used only when computed from real video bytes by a trusted caller.
"""
from __future__ import annotations

from dataclasses import dataclass
from time import monotonic

from matcher import Media, SearchResults, choose
from opensubtitles import Candidate, Discovery, OpenSubtitles, SubtitleApiError

SEARCH_POLICIES = ("VI_FAST", "EN_DIRECT", "VI_FULL")
VI_FAST_SOCKET_TIMEOUT_SECONDS = 4.0


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
    search_policy: str = "VI_FAST"
    vi_probe_status: str = "UNKNOWN"
    vi_elapsed_ms: int = 0
    en_elapsed_ms: int = 0


def _empty_discovery(media: Media) -> Discovery:
    results = SearchResults(media.key, ())
    return Discovery(media.key, results, (), choose(media, results),
                     raw_rows=0, api_total=0)


def _discover_complete(client: OpenSubtitles, media: Media, *,
                       language: str, imdb_id: str,
                       max_pages: int = 2,
                       timeout_seconds: float | None = None) -> tuple[Discovery, bool, int]:
    """Bounded page aggregation; never use unobserved rows as ranking proof."""
    if max_pages not in (1, 2):
        raise ValueError("unsupported page budget")
    first = client.search(media, language=language, query_mode="imdb",
                          imdb_id=imdb_id, page=1,
                          timeout_seconds=timeout_seconds)
    pages = [first]
    if (max_pages == 2 and first.raw_rows == 50 and
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
                      imdb_id: str, policy: str = "VI_FAST",
                      vi_timeout_seconds: float = VI_FAST_SOCKET_TIMEOUT_SECONDS) -> Route:
    """VI_FAST limits VI to one GET; EN_DIRECT skips it; VI_FULL is legacy.

    No mode ever treats title/year/1080p alone as sync evidence. A single
    confident VI must be from a complete *observed* VI page set. For VI_FAST,
    a partial page moves to EN instead of blocking progress. EN remains
    conservative: pagination incomplete or ambiguous means manual review.
    """
    if policy not in SEARCH_POLICIES:
        raise SubtitleApiError("UNSUPPORTED_SEARCH_POLICY")
    if type(vi_timeout_seconds) not in (float, int) or not 1 <= vi_timeout_seconds <= 15:
        raise SubtitleApiError("INVALID_SEARCH_TIMEOUT")

    vi = _empty_discovery(media)
    vi_gets = 0
    vi_probe = "SKIPPED"
    vi_ms = 0
    if policy != "EN_DIRECT":
        start = monotonic()
        try:
            vi, complete, vi_gets = _discover_complete(
                client, media, language="vi", imdb_id=imdb_id,
                max_pages=1 if policy == "VI_FAST" else 2,
                timeout_seconds=float(vi_timeout_seconds) if policy == "VI_FAST" else None)
            vi_probe = "COMPLETE" if complete else "INCOMPLETE"
        except SubtitleApiError as error:
            if policy != "VI_FAST" or str(error) != "API_NETWORK_ERROR":
                raise
            # One transient VI GET was attempted; do not retry/fan out.
            # Authentication / rate-limit and invalid schema errors must not
            # silently trigger more provider calls.
            vi_gets, complete, vi_probe = 1, False, "NETWORK_ERROR_FALLBACK"
        vi_ms = round((monotonic() - start) * 1000)
        if not complete and policy == "VI_FULL":
            return Route("REVIEW_REQUIRED", "VI_COVERAGE_INCOMPLETE",
                         None, None, vi, None, vi_gets,
                         search_policy=policy, vi_probe_status=vi_probe,
                         vi_elapsed_ms=vi_ms)
        if complete and vi.decision.status == "VI_MATCH" and vi.decision.winner is not None:
            return Route("VI_READY", "CONFIDENT_VI_RELEASE", "vi",
                         int(vi.decision.winner.subtitle_id), vi, None, vi_gets,
                         search_policy=policy, vi_probe_status=vi_probe,
                         vi_elapsed_ms=vi_ms)

    start_en = monotonic()
    en, en_complete, en_gets = _discover_complete(
        client, media, language="en", imdb_id=imdb_id, max_pages=2)
    en_ms = round((monotonic() - start_en) * 1000)
    common = dict(search_policy=policy, vi_probe_status=vi_probe,
                  vi_elapsed_ms=vi_ms, en_elapsed_ms=en_ms)
    count = vi_gets + en_gets
    if not en_complete:
        return Route("REVIEW_REQUIRED", "EN_COVERAGE_INCOMPLETE",
                     None, None, vi, en, count, **common)
    if en.decision.status == "EN_TRANSLATE" and en.decision.winner is not None:
        return Route("EN_TRANSLATE", "CONFIDENT_EN_RELEASE", "en",
                     int(en.decision.winner.subtitle_id), vi, en, count, **common)
    if vi.decision.ranked or en.decision.ranked:
        return Route("REVIEW_REQUIRED", "NO_CONFIDENT_UNAMBIGUOUS_RELEASE",
                     None, None, vi, en, count, **common)
    return Route("NO_MATCH", "NO_RANKABLE_SUBTITLES",
                 None, None, vi, en, count, **common)
