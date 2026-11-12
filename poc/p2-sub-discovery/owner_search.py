"""Owner-side D2 real search-only probe; never POST or download subtitles.

It reads a local API key from the environment, prompts for a filename of media
the owner is authorized to query, and prints only sanitized decision counts.
It intentionally does not connect to TorrServer or assert real media binding.
"""
from __future__ import annotations

import argparse
import os

from matcher import Media
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Owner-side search only; no downloads")
    parser.add_argument("--imdb-id", default=None, help="verified IMDb id without leading tt")
    args = parser.parse_args()
    key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not key or not key.strip() or "\n" in key or "\r" in key:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        release = input("Authorized video release filename (local input only): ").strip()
        client = OpenSubtitles(api_key=key)
        for line in search_status(client, release, imdb_id=args.imdb_id):
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
