"""Owner-side D2 real search-only probe; never POST or download subtitles.

It reads a local API key from the environment, prompts for a filename of media
the owner is authorized to query, and prints only sanitized decision counts.
It intentionally does not connect to TorrServer or assert real media binding.
"""
from __future__ import annotations

import argparse
import os

from matcher import Media, parse_release
from opensubtitles import OpenSubtitles, SubtitleApiError

_UNVERIFIED_PROFILE = "owner-interactive-search-only"
_UNVERIFIED_HASH = "not-a-real-torrserver-hash"
_QUERY_MODES = ("release", "title")


def search_status(client: OpenSubtitles, filename: str,
                  imdb_id: str | None = None) -> tuple[str, ...]:
    """Search VI first; EN only if no confidently ranked VI; no download call."""
    if not isinstance(filename, str) or not (1 <= len(filename.strip()) <= 255):
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if any(ord(c) < 32 for c in filename) or "/" in filename or "\\" in filename:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    media = Media(_UNVERIFIED_PROFILE, _UNVERIFIED_HASH, 0, filename.strip())
    messages: list[str] = ["D2_SEARCH_ONLY", "TORRSERVER_MEDIA_BINDING=UNVERIFIED"]
    decisions: list[str] = []
    raw_rows_seen = 0
    for language, accepted in (("vi", "VI_MATCH"), ("en", "EN_TRANSLATE")):
        modes = (*_QUERY_MODES, "imdb") if imdb_id else _QUERY_MODES
        for query_mode in modes:
            discovery = client.search(media, language=language, query_mode=query_mode,
                                      imdb_id=imdb_id)
            status = discovery.decision.status
            decisions.append(status)
            raw_rows_seen += discovery.raw_rows
            key = f"{language.upper()}_{query_mode.upper()}"
            messages.append(f"{key}_RAW_ROWS={discovery.raw_rows}")
            messages.append(f"{key}_API_TOTAL={discovery.api_total if discovery.api_total is not None else 'UNKNOWN'}")
            messages.append(f"{key}_CANDIDATES={len(discovery.candidates)}")
            messages.append(f"{key}_RANKED={len(discovery.decision.ranked)}")
            messages.append(f"{key}_DECISION={status}")
            if status == accepted:
                winner = discovery.decision.winner
                evidence = ",".join(winner.evidence) if winner else "none"
                messages.extend((f"BEST_LANGUAGE={language.upper()}",
                                 f"BEST_MATCH_EVIDENCE={evidence}",
                                 f"NEXT_GATE={accepted}",
                                 "DOWNLOAD_REQUESTS=0"))
                return tuple(messages)
        # Weak/ambiguous VI is never downloaded, and EN requires its own match.
    if raw_rows_seen and all(status == "NO_MATCH" for status in decisions):
        messages.append("DIAGNOSTIC=API_HAS_ROWS_BUT_NO_RANKABLE_MATCH")
    elif not raw_rows_seen:
        messages.append("DIAGNOSTIC=API_RETURNED_ZERO_RAW_ROWS")
    messages.append(f"NEXT_GATE={'REVIEW_REQUIRED' if 'REVIEW_REQUIRED' in decisions else 'NO_MATCH'}")
    messages.append("DOWNLOAD_REQUESTS=0")
    return tuple(messages)


def diagnostic_status(client: OpenSubtitles, filename: str,
                      *, imdb_id: str) -> tuple[str, ...]:
    """Only VI+EN IMDb search: two GETs, no downloads or raw API payload."""
    if not isinstance(filename, str) or not (1 <= len(filename.strip()) <= 255):
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if any(ord(c) < 32 for c in filename) or "/" in filename or "\\" in filename:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    media = Media(_UNVERIFIED_PROFILE, _UNVERIFIED_HASH, 0, filename.strip())
    lines = ["D2_SCHEMA_DIAGNOSTIC", "TORRSERVER_MEDIA_BINDING=UNVERIFIED"]
    for language in ("vi", "en"):
        discovery = client.search(media, language=language, query_mode="imdb",
                                  imdb_id=imdb_id)
        prefix = language.upper() + "_IMDB"
        lines.append(f"{prefix}_RAW_ROWS={discovery.raw_rows}")
        lines.append(f"{prefix}_API_TOTAL={discovery.api_total if discovery.api_total is not None else 'UNKNOWN'}")
        lines.append(f"{prefix}_CANDIDATES={len(discovery.candidates)}")
        ranked = discovery.decision.ranked
        lines.append(f"{prefix}_RANKED={len(ranked)}")
        lines.append(f"{prefix}_CONFIDENT={sum(1 for r in ranked if r.confident)}")
        lines.append(f"{prefix}_GROUP_MATCHES={sum(1 for r in ranked if 'group' in r.evidence)}")
        lines.append(f"{prefix}_DECISION={discovery.decision.status}")
        for code, count in discovery.parse_rejections:
            if count:
                lines.append(f"{prefix}_REJECT_{code.upper()}={count}")
    lines.append("DOWNLOAD_REQUESTS=0")
    return tuple(lines)


def review_status(client: OpenSubtitles, filename: str, *, imdb_id: str,
                  top_n: int = 5) -> tuple[str, ...]:
    """Read-only per-release review, max three GET requests. No IDs or filenames emitted.

    The local filename and API key go to OpenSubtitles on an authenticated GET;
    returned data is kept in process memory and only safe scored flags are printed.
    This function never elevates a weak match to automatic download authority.
    """
    if not isinstance(filename, str) or not (1 <= len(filename.strip()) <= 255):
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if any(ord(c) < 32 for c in filename) or "/" in filename or "\\" in filename:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if type(top_n) is not int or not 1 <= top_n <= 5:
        raise SubtitleApiError("INVALID_TOP_N")
    media = Media(_UNVERIFIED_PROFILE, _UNVERIFIED_HASH, 0, filename.strip())
    source = parse_release(media.filename)
    output = ["D2_RELEASE_REVIEW", "TORRSERVER_MEDIA_BINDING=UNVERIFIED",
              "AUTO_DOWNLOAD_ALLOWED=NO"]
    total_gets = 0
    for language in ("vi", "en"):
        first = client.search(media, language=language, query_mode="imdb",
                              imdb_id=imdb_id, page=1)
        total_gets += 1
        discoveries = [first]
        prefix = language.upper()
        output.append(f"{prefix}_PAGE1_RAW_ROWS={first.raw_rows}")
        # Fetch one extra page only when it is known that page 1 was incomplete.
        if first.api_total is not None and first.api_total > first.raw_rows and first.raw_rows == 50:
            second = client.search(media, language=language, query_mode="imdb",
                                   imdb_id=imdb_id, page=2)
            total_gets += 1
            discoveries.append(second)
            output.append(f"{prefix}_PAGE2_RAW_ROWS={second.raw_rows}")
        combined_rows = sum(x.raw_rows for x in discoveries)
        output.append(f"{prefix}_API_TOTAL={first.api_total if first.api_total is not None else 'UNKNOWN'}")
        output.append(f"{prefix}_RETRIEVED_ROWS={combined_rows}")
        output.append(f"{prefix}_COVERAGE={'PARTIAL' if first.api_total is not None and combined_rows < first.api_total else 'FIRST_PAGE_OR_COMPLETE'}")
        candidates = {}
        ranked = {}
        for discovery in discoveries:
            for candidate in discovery.candidates:
                candidates.setdefault(candidate.subtitle.subtitle_id, candidate)
            for item in discovery.decision.ranked:
                ranked.setdefault(item.subtitle_id, item)
        ordered = sorted(ranked.values(), key=lambda item: (-item.score, item.subtitle_id))
        output.append(f"{prefix}_CANDIDATES={len(candidates)}")
        output.append(f"{prefix}_RANKED={len(ordered)}")
        output.append(f"{prefix}_CONFIDENT={sum(1 for item in ordered if item.confident)}")
        output.append(f"{prefix}_GROUP_MATCHES={sum('group' in item.evidence for item in ordered)}")

        def compare(expected, actual):
            if expected is None or actual is None:
                return "UNKNOWN"
            return "YES" if expected == actual else "NO"

        for i, rank in enumerate(ordered[:top_n], 1):
            candidate = candidates.get(rank.subtitle_id)
            if candidate is None:
                continue
            prop = parse_release(candidate.subtitle.release_name)
            evidence = ",".join(rank.evidence)
            output.append(f"{prefix}_TOP{i}_SCORE={rank.score}")
            output.append(f"{prefix}_TOP{i}_YEAR={compare(source.year, prop.year)}")
            output.append(f"{prefix}_TOP{i}_SOURCE={compare(source.source, prop.source)}")
            output.append(f"{prefix}_TOP{i}_RESOLUTION={compare(source.resolution, prop.resolution)}")
            output.append(f"{prefix}_TOP{i}_CODEC={compare(source.codec, prop.codec)}")
            output.append(f"{prefix}_TOP{i}_GROUP={compare(source.group, prop.group)}")
            output.append(f"{prefix}_TOP{i}_EVIDENCE={evidence}")
            output.append(f"{prefix}_TOP{i}_FORMAT_VALIDATED=NO")
    output.append(f"SEARCH_REQUESTS={total_gets}")
    output.append("DOWNLOAD_REQUESTS=0")
    output.append("NEXT_GATE=MANUAL_REVIEW_OR_VERIFIED_MOVIEHASH")
    return tuple(output)


def main() -> int:
    parser = argparse.ArgumentParser(description="Owner-side search only; no downloads")
    parser.add_argument("--imdb-id", default=None, help="verified IMDb id without leading tt")
    parser.add_argument("--diagnose-imdb", action="store_true", help="two IMDb GETs with safe parser rejection counts")
    parser.add_argument("--review-imdb", action="store_true", help="VI/EN top-five release evidence, two or three GETs")
    args = parser.parse_args()
    key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not key or not key.strip() or "\n" in key or "\r" in key:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        release = input("Authorized video release filename (local input only): ").strip()
        client = OpenSubtitles(api_key=key)
        if args.diagnose_imdb and args.review_imdb:
            raise SubtitleApiError("CONFLICTING_SEARCH_MODES")
        if args.review_imdb:
            if args.imdb_id is None:
                raise SubtitleApiError("INVALID_IMDB_ID")
            lines = review_status(client, release, imdb_id=args.imdb_id)
        elif args.diagnose_imdb:
            if args.imdb_id is None:
                raise SubtitleApiError("INVALID_IMDB_ID")
            lines = diagnostic_status(client, release, imdb_id=args.imdb_id)
        else:
            lines = search_status(client, release, imdb_id=args.imdb_id)
        for line in lines:
            print(line)
        return 0
    except SubtitleApiError as exc:
        # Only known sanitized enum values are raised by the owned client.
        print(str(exc))
        return 1
    except (EOFError, KeyboardInterrupt):
        print("D2_SEARCH_CANCELLED")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
