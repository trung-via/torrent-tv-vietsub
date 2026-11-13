"""Read-only owner probe for VI_FAST/EN_DIRECT/VI_FULL on OpenSubtitles.

Only GET /subtitles by verified title IMDb ID; no download, model or TV API.
Releases are owner-local text, not uploaded to public GitHub or logs.
"""
from __future__ import annotations

import argparse
import os
import unicodedata
import uuid

from matcher import Media, parse_release
from opensubtitles import OpenSubtitles, SubtitleApiError
from vi_en_fallback import SEARCH_POLICIES, select_vi_then_en


def _label(value: str) -> str:
    if not isinstance(value, str):
        return "UNKNOWN"
    return " ".join("".join(
        c if not unicodedata.category(c).startswith("C") else " " for c in value
    ).split())[:120] or "UNKNOWN"


def _compare(reference, actual):
    if reference is None or actual is None:
        return "UNKNOWN"
    return "YES" if reference == actual else "NO"


def search_only_status(client: OpenSubtitles, filename: str, imdb_id: str, *,
                       policy: str = "VI_FAST") -> tuple[str, ...]:
    if (not isinstance(filename, str) or not 1 <= len(filename.strip()) <= 255
            or "/" in filename or "\\" in filename
            or any(ord(c) < 32 for c in filename)):
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    # This random marker is NOT a TorrServer identity or movie hash.
    media = Media("owner-search-only-unverified", uuid.uuid4().hex,
                  0, filename.strip())
    source = parse_release(media.filename)
    if not source.title:
        raise SubtitleApiError("BAD_MEDIA_TITLE")
    route = select_vi_then_en(client, media, imdb_id=imdb_id, policy=policy)

    output = ["D25_SEARCH_ONLY", "META_GET_ONLY=YES",
              "REAL_MEDIA_BINDING=UNVERIFIED",
              f"SEARCH_POLICY={route.search_policy}",
              f"VIDEO_RELEASE_GROUP={source.group or 'UNKNOWN'}",
              f"VIDEO_RESOLUTION={source.resolution or 'UNKNOWN'}",
              f"VI_PROBE_STATUS={route.vi_probe_status}",
              f"VI_SEARCH_ELAPSED_MS={route.vi_elapsed_ms}",
              f"EN_SEARCH_ELAPSED_MS={route.en_elapsed_ms}"]
    for prefix, d in (("VI", route.vi), ("EN", route.en)):
        searched = d is not None and (prefix == "EN" or
                                     route.vi_probe_status != "SKIPPED")
        output.append(f"{prefix}_SEARCHED={'YES' if searched else 'NO'}")
        if not searched:
            continue
        output.append(f"{prefix}_RAW_ROWS={d.raw_rows}")
        output.append(f"{prefix}_API_TOTAL={d.api_total if d.api_total is not None else 'UNKNOWN'}")
        output.append(f"{prefix}_CANDIDATES={len(d.candidates)}")
        output.append(f"{prefix}_RANKED={len(d.decision.ranked)}")
        output.append(f"{prefix}_CONFIDENT={sum(r.confident for r in d.decision.ranked)}")
        output.append(f"{prefix}_GROUP_MATCHES={sum('group' in r.evidence for r in d.decision.ranked)}")
        by_id = {candidate.subtitle.subtitle_id: candidate
                 for candidate in d.candidates}
        for index, item in enumerate(d.decision.ranked[:3], 1):
            if item.subtitle_id not in by_id:
                continue
            candidate = by_id[item.subtitle_id]
            attrs = parse_release(candidate.subtitle.release_name)
            output.append(f"{prefix}_TOP{index}_SCORE={item.score}")
            output.append(f"{prefix}_TOP{index}_CONFIDENT={'YES' if item.confident else 'NO'}")
            output.append(f"{prefix}_TOP{index}_GROUP={_compare(source.group, attrs.group)}")
            output.append(f"{prefix}_TOP{index}_SOURCE={_compare(source.source, attrs.source)}")
            output.append(f"{prefix}_TOP{index}_RESOLUTION={_compare(source.resolution, attrs.resolution)}")
            output.append(f"{prefix}_TOP{index}_CODEC={_compare(source.codec, attrs.codec)}")
            output.append(f"{prefix}_TOP{index}_EVIDENCE={','.join(item.evidence)}")
            # Release metadata is shown only on owner's screen. It is untrusted
            # provider text, so strip control characters and bound the length.
            output.append(f"{prefix}_TOP{index}_RELEASE_HINT={_label(candidate.subtitle.release_name)}")
    output.extend((f"ROUTE={route.status}", f"ROUTE_REASON={route.reason}",
                   f"SEARCH_GET_REQUESTS={route.get_requests}",
                   "DOWNLOAD_POST_REQUESTS=0",
                   "TRANSLATION_REQUESTS=0",
                   "SYNC_VERIFIED=NO"))
    return tuple(output)


def main() -> int:
    parser = argparse.ArgumentParser(description="GET-only OpenSubtitles VI_FAST owner probe")
    parser.add_argument("--imdb-id", required=True)
    parser.add_argument("--search-policy", choices=SEARCH_POLICIES, default="VI_FAST")
    args = parser.parse_args()
    key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not key or not key.strip() or "\r" in key or "\n" in key:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        release = input("Authorized release name (local input only): ")
        status = search_only_status(OpenSubtitles(api_key=key), release,
                                    args.imdb_id, policy=args.search_policy)
        for line in status:
            print(line)
        return 0
    except SubtitleApiError as exc:
        # The client emits safe predefined error codes, never raw API content.
        print(str(exc))
        print("DOWNLOAD_POST_REQUESTS=0")
        return 1
    except (EOFError, KeyboardInterrupt, OSError):
        print("OWNER_SEARCH_LOCAL_STOP")
        print("DOWNLOAD_POST_REQUESTS=0")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
