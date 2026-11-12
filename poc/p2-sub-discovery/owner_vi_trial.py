"""Owner-only VI candidate review and at-most-one quota-incurring download.

Only runs when the owner explicitly starts this Python process with a local key.
Lists provider metadata on the owner's laptop; never writes it to GitHub.
No EN translation, TorrServer, TV, auto-download or repeated POST retries.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import unicodedata
import uuid
from typing import Callable

from matcher import Media, parse_release
from opensubtitles import OpenSubtitles, SubtitleApiError, write_private_cache

Emit = Callable[[str], None]
Ask = Callable[[str], str]


def _safe_display(value: str, limit: int = 150) -> str:
    """Display a bounded, single-line plain-text label only on owner's terminal."""
    if not isinstance(value, str):
        return "UNKNOWN"
    cleaned = "".join(c if not unicodedata.category(c).startswith("C") else " "
                      for c in value)
    return " ".join(cleaned.split())[:limit] or "UNKNOWN"


def owner_trial(client: OpenSubtitles, filename: str, imdb_id: str, *,
                ask: Ask = input, emit: Emit = print,
                cache_root: Path | None = None) -> int:
    """VI-only search, optional one manually approved POST and verified local SRT."""
    if not isinstance(filename, str) or not 1 <= len(filename.strip()) <= 255:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if any(ord(c) < 32 for c in filename) or "/" in filename or "\\" in filename:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if not parse_release(filename).title:
        raise SubtitleApiError("BAD_MEDIA_TITLE")
    # Trial-only random marker: explicitly NOT a TorrServer infohash or movie hash.
    media = Media("owner-vi-trial-unverified", uuid.uuid4().hex, 0, filename.strip())
    discovery = client.search(media, language="vi", query_mode="imdb", imdb_id=imdb_id)
    by_id = {c.subtitle.subtitle_id: c for c in discovery.candidates}
    ranked = [(r, by_id[r.subtitle_id])
              for r in discovery.decision.ranked
              if r.language == "vi" and r.subtitle_id in by_id
              and "title" in r.evidence][:5]

    emit("D2_VI_MANUAL_REVIEW")
    emit("TORRSERVER_MEDIA_BINDING=UNVERIFIED")
    emit("AUTO_DOWNLOAD_ALLOWED=NO")
    emit(f"VI_RAW_ROWS={discovery.raw_rows}")
    emit(f"VI_RANKED={len(discovery.decision.ranked)}")
    emit(f"VI_SHORTLIST={len(ranked)}")
    emit("SYNC_VERIFIED=NO")
    emit("FORMAT_VALIDATED=NO")
    if not ranked:
        emit("NEXT_GATE=NO_VI_SHORTLIST")
        emit("DOWNLOAD_POST_ATTEMPTS=0")
        return 0

    for index, (rank, candidate) in enumerate(ranked, 1):
        emit(f"OPTION_{index}_SCORE={rank.score}")
        emit(f"OPTION_{index}_EVIDENCE={','.join(rank.evidence)}")
        emit(f"OPTION_{index}_SOURCE_HINT={_safe_display(candidate.subtitle.release_name)}")
        emit(f"OPTION_{index}_SOURCE_FORMAT={candidate.subtitle.fmt}")

    choice = ask("Select 1-5 shown above, or 0 to cancel: ").strip()
    if choice == "0":
        emit("OWNER_CANCELLED")
        emit("DOWNLOAD_POST_ATTEMPTS=0")
        return 0
    if not choice.isascii() or not choice.isdecimal() or not 1 <= int(choice) <= len(ranked):
        emit("INVALID_SELECTION")
        emit("DOWNLOAD_POST_ATTEMPTS=0")
        return 1

    chosen_rank, chosen = ranked[int(choice) - 1]
    emit(f"SELECTED_SCORE={chosen_rank.score}")
    emit(f"SELECTED_EVIDENCE={','.join(chosen_rank.evidence)}")
    emit(f"SELECTED_SOURCE_HINT={_safe_display(chosen.subtitle.release_name)}")
    emit("NOTE=This candidate has not been synchronized against real video")
    # A distinct interactive approval *after* the selected release has been shown.
    # One attempted POST may consume quota even if conversion/content QA fails.
    confirmation = ask("One chargeable subtitle POST: type DOWNLOAD ONE exactly to authorize: ").strip()
    if confirmation != "DOWNLOAD ONE":
        emit("OWNER_CANCELLED")
        emit("DOWNLOAD_POST_ATTEMPTS=0")
        return 0

    emit("DOWNLOAD_POST_ATTEMPTS=1")
    asset = client.download_manual_vi(media, discovery, file_id=chosen.file_id, authorized=True)
    # Fail-closed: no cache until UTF-8/timings have been verified in API client.
    if cache_root is None:
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SubtitleApiError("PRIVATE_CACHE_LOCATION_NOT_CONFIGURED")
        cache_root = Path(local) / "TorrentTVVietsub" / "subtitle-trials"
    path = write_private_cache(cache_root, media, asset)
    emit("DOWNLOAD_AND_SRT_QA=PASS")
    emit(f"CUES={asset.cues}")
    emit(f"CONTENT_SHA256={asset.sha256}")
    emit(f"PRIVATE_CACHE_FILENAME={path.name}")
    emit("PRIVATE_CACHE_SAVED=YES")
    emit("TV_SYNC_VERIFIED=NO")
    emit("NEXT_GATE=LOCAL_CONTENT_AND_SYNC_REVIEW")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="One optional owner-consented Vietnamese subtitle download")
    parser.add_argument("--imdb-id", required=True, help="verified IMDb title id for this owner's film")
    args = parser.parse_args()
    api_key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not api_key or not api_key.strip() or "\n" in api_key or "\r" in api_key:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        release = input("Authorized video release filename (local input only): ")
        client = OpenSubtitles(api_key=api_key)
        return owner_trial(client, release, args.imdb_id)
    except SubtitleApiError as exc:
        # Safe, enumerated API client errors only. Never print raw provider
        # response, temporary signed URL, key, filenames or dialogue.
        print(str(exc))
        return 1
    except (EOFError, KeyboardInterrupt):
        print("D2_OWNER_CANCELLED")
        return 1
    except OSError:
        print("PRIVATE_CACHE_IO_ERROR")
        return 1


if __name__ == "__main__":
    sys.exit(main())
