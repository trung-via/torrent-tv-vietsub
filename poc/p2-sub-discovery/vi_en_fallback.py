"""Configurable fast subtitle discovery: VI_FAST (default), EN_DIRECT, VI_FULL.

Match metadata before consuming download quota. Release-group/1080p are useful
owner heuristics, never proof of actual video sync. Moviehash is optional and
may be used only when computed from real video bytes by a trusted caller.
"""
from __future__ import annotations

from dataclasses import dataclass
from time import monotonic

from matcher import Media, Ranked, SearchResults, choose, parse_release, preferred_media_release
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


@dataclass(frozen=True)
class DualCandidates:
    """Separate EN→AI default from a non-authoritative VI option.

    A search candidate is NOT evidence that its timestamps fit the video.
    The consumer must label the VI alternative accordingly and must not
    substitute it silently for the AI track. No download happens here.
    """
    ai_file_id: int | None
    vi_option_file_id: int | None
    vi_release_matched: bool
    vi: Discovery
    en: Discovery
    get_requests: int
    default_source: str  # AI | VI_OPTION | NONE


def _vi_option(media: Media, discovery: Discovery) -> Ranked | None:
    """Offer likely same-film VI even if exact video-cut sync is unproven.

    A missing group is acceptable only for a clearly labelled manual option;
    a *conflicting* group, source, resolution, codec, hash or year is not.
    Title + year + two matching release properties are required, so a broad
    film-title search cannot pollute the TV subtitle menu.
    """
    expected = preferred_media_release(media)
    candidates = {c.subtitle.subtitle_id: c.subtitle for c in discovery.candidates}
    for ranked in discovery.decision.ranked:
        if ranked.language != "vi" or "year" not in ranked.evidence:
            continue
        sub = candidates.get(ranked.subtitle_id)
        if sub is None or "different_moviehash" in ranked.evidence:
            continue
        actual = parse_release(sub.release_name)
        if any(getattr(expected, field) is not None
               and getattr(actual, field) is not None
               and getattr(expected, field) != getattr(actual, field)
               for field in ("source", "resolution", "codec", "group")):
            continue
        if ranked.confident or sum(
                clue in ranked.evidence
                for clue in ("source", "resolution", "codec", "group")) >= 2:
            return ranked
    return None


def discover_dual_candidates(client: OpenSubtitles, media: Media, *,
                             imdb_id: str | None = None,
                             vi_timeout_seconds: float = VI_FAST_SOCKET_TIMEOUT_SECONDS
                             ) -> DualCandidates:
    """Always discover EN for AI and VI for a separate fallback option.

    Search is non-mutating. It does not spend download quota, translate, or
    publish a P4 revision; those remain independently authorized consumers.
    """
    if type(vi_timeout_seconds) not in (int, float) or not 1 <= vi_timeout_seconds <= 15:
        raise SubtitleApiError("INVALID_SEARCH_TIMEOUT")
    vi = _empty_discovery(media)
    vi_gets = 0
    try:
        vi, _complete, vi_gets = _discover_complete(
            client, media, language="vi", imdb_id=imdb_id,
            max_pages=1, timeout_seconds=float(vi_timeout_seconds))
    except SubtitleApiError as error:
        if str(error) != "API_NETWORK_ERROR":
            raise
        vi_gets = 1  # One failed bounded GET; do not retry.
    en = _empty_discovery(media)
    try:
        en, _complete, en_gets = _discover_complete(
            client, media, language="en", imdb_id=imdb_id, max_pages=2)
    except SubtitleApiError as error:
        if str(error) != "API_NETWORK_ERROR":
            raise
        # A transient EN network failure must not discard a separately
        # eligible, explicitly labelled VI option. Do not retry the GET.
        en_gets = 1
    ai = en.decision.winner if en.decision.status == "EN_TRANSLATE" else None
    option = _vi_option(media, vi)
    return DualCandidates(
        ai_file_id=int(ai.subtitle_id) if ai is not None else None,
        vi_option_file_id=int(option.subtitle_id) if option is not None else None,
        vi_release_matched=option.confident if option is not None else False,
        vi=vi, en=en, get_requests=vi_gets + en_gets,
        default_source="AI" if ai is not None else (
            "VI_OPTION" if option is not None else "NONE"),
    )


def _empty_discovery(media: Media) -> Discovery:
    results = SearchResults(media.key, ())
    return Discovery(media.key, results, (), choose(media, results),
                     raw_rows=0, api_total=0)


def _discover_complete(client: OpenSubtitles, media: Media, *,
                       language: str, imdb_id: str | None = None,
                       max_pages: int = 2,
                       timeout_seconds: float | None = None) -> tuple[Discovery, bool, int]:
    """Bounded page aggregation; never use unobserved rows as ranking proof."""
    if max_pages not in (1, 2):
        raise ValueError("unsupported page budget")
    # Use OpenSubtitles title+year extracted from the authorized video name
    # when a separately verified IMDb ID is not available. Never guess IDs or
    # require users to supply a movie hash just to search metadata.
    mode = "imdb" if imdb_id is not None else "title"
    first = client.search(media, language=language, query_mode=mode,
                          imdb_id=imdb_id, page=1,
                          timeout_seconds=timeout_seconds)
    pages = [first]
    if (max_pages == 2 and first.raw_rows == 50 and
            (first.api_total is None or first.api_total > first.raw_rows)):
        pages.append(client.search(media, language=language,
                                   query_mode=mode, imdb_id=imdb_id, page=2))
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
                      imdb_id: str | None = None, policy: str = "VI_FAST",
                      vi_timeout_seconds: float = VI_FAST_SOCKET_TIMEOUT_SECONDS,
                      external_en_available: bool = False) -> Route:
    """VI_FAST limits VI to one GET; EN_DIRECT skips it; VI_FULL is legacy.

    No mode ever treats title/year/1080p alone as sync evidence. Select the
    strongest confidently matched release from the bounded *observed* rows;
    provider total_count is a pagination hint, never a prerequisite for using
    a winner. This avoids stalling on thousands of unrelated uploads.
    """
    if policy not in SEARCH_POLICIES:
        raise SubtitleApiError("UNSUPPORTED_SEARCH_POLICY")
    if type(external_en_available) is not bool:
        raise SubtitleApiError("EXTERNAL_EN_AVAILABILITY_INVALID")
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
        if vi.decision.status == "VI_MATCH" and vi.decision.winner is not None:
            return Route("VI_READY", "CONFIDENT_VI_RELEASE", "vi",
                         int(vi.decision.winner.subtitle_id), vi, None, vi_gets,
                         search_policy=policy, vi_probe_status=vi_probe,
                         vi_elapsed_ms=vi_ms)

    # The caller verified exactly one English *sidecar file in the torrent*.
    # Preserve the OpenSubtitles VI-first probe but save the EN provider GET.
    # The caller fetches and validates sidecar bytes; failed fetches may
    # fall back through an EN_DIRECT lookup without repeating the VI GET.
    if external_en_available:
        return Route("EXTERNAL_EN", "TORRENT_SIDECAR_EN", "en", None,
                     vi, None, vi_gets, search_policy=policy,
                     vi_probe_status=vi_probe, vi_elapsed_ms=vi_ms)

    start_en = monotonic()
    en, _en_complete, en_gets = _discover_complete(
        client, media, language="en", imdb_id=imdb_id, max_pages=2)
    en_ms = round((monotonic() - start_en) * 1000)
    common = dict(search_policy=policy, vi_probe_status=vi_probe,
                  vi_elapsed_ms=vi_ms, en_elapsed_ms=en_ms)
    count = vi_gets + en_gets
    if en.decision.status == "EN_TRANSLATE" and en.decision.winner is not None:
        return Route("EN_TRANSLATE", "CONFIDENT_EN_RELEASE", "en",
                     int(en.decision.winner.subtitle_id), vi, en, count, **common)
    if vi.decision.ranked or en.decision.ranked:
        return Route("REVIEW_REQUIRED", "NO_CONFIDENT_UNAMBIGUOUS_RELEASE",
                     None, None, vi, en, count, **common)
    return Route("NO_MATCH", "NO_RANKABLE_SUBTITLES",
                 None, None, vi, en, count, **common)
