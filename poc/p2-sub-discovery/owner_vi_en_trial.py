"""Owner-only VI -> EN matched subtitle download test; translation needs consent.

Only authorized local release/IMDb metadata and single explicit quota POST.
Never invokes any AI provider or uploads dialogue. No TV/TorrServer actions.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import tempfile
import uuid

from matcher import Media
from opensubtitles import OpenSubtitles, SubtitleApiError, write_private_cache
from owner_vi_trial import _safe_display
from vi_en_fallback import SEARCH_POLICIES, select_vi_then_en


def owner_fallback_trial(client: OpenSubtitles, filename: str, imdb_id: str, *,
                         ask=input, emit=print, cache_root: Path | None = None,
                         search_policy: str = "VI_FAST") -> int:
    if not isinstance(filename, str) or not 1 <= len(filename.strip()) <= 255:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if any(ord(c) < 32 for c in filename) or "/" in filename or "\\" in filename:
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    media = Media("owner-fallback-unverified", uuid.uuid4().hex, 0, filename.strip())
    route = select_vi_then_en(client, media, imdb_id=imdb_id,
                              policy=search_policy)

    emit("D2_VI_EN_FALLBACK_OWNER")
    emit("REAL_VIDEO_BINDING=UNVERIFIED")
    emit(f"SEARCH_POLICY={route.search_policy}")
    emit(f"VI_PROBE_STATUS={route.vi_probe_status}")
    emit(f"VI_SEARCH_ELAPSED_MS={route.vi_elapsed_ms}")
    emit(f"EN_SEARCH_ELAPSED_MS={route.en_elapsed_ms}")
    emit(f"VI_RANKED={len(route.vi.decision.ranked)}")
    emit(f"EN_RANKED={len(route.en.decision.ranked) if route.en else 0}")
    emit(f"ROUTE={route.status}")
    emit(f"ROUTE_REASON={route.reason}")
    emit(f"SEARCH_REQUESTS={route.get_requests}")
    emit("VIDEO_SYNC_VERIFIED=NO")
    emit("TRANSLATION_REQUESTS=0")

    if route.status not in ("VI_READY", "EN_TRANSLATE"):
        # Weak EN release names are useful owner-facing evidence, but NEVER
        # authorize a quota POST through this branch.
        if route.en and route.en.decision.ranked:
            by_id = {c.subtitle.subtitle_id: c
                     for c in route.en.candidates}
            reviewed = [r for r in route.en.decision.ranked
                        if r.subtitle_id in by_id][:3]
            emit(f"REVIEW_EN_COUNT={len(route.en.decision.ranked)}")
            for index, item in enumerate(reviewed, 1):
                hint = by_id[item.subtitle_id].subtitle.release_name
                emit(f"REVIEW_EN_TOP{index}_SCORE={item.score}")
                emit(f"REVIEW_EN_TOP{index}_EVIDENCE={','.join(item.evidence)}")
                emit(f"REVIEW_EN_TOP{index}_RELEASE_HINT={_safe_display(hint)}")
        emit("DOWNLOAD_POST_ATTEMPTS=0")
        emit("NEXT_GATE=MANUAL_SOURCE_REVIEW")
        return 0

    discovery = route.vi if route.status == "VI_READY" else route.en
    if discovery is None or route.selected_file_id is None:
        raise SubtitleApiError("CANDIDATE_BINDING_MISMATCH")
    chosen = [c for c in discovery.candidates if c.file_id == route.selected_file_id
              and c.subtitle.language == route.language]
    if len(chosen) != 1:
        raise SubtitleApiError("CANDIDATE_BINDING_MISMATCH")

    emit(f"SELECTED_LANGUAGE={route.language.upper()}")
    emit(f"SELECTED_RELEASE_HINT={_safe_display(chosen[0].subtitle.release_name)}")
    emit("MATCH_EVIDENCE=RELEASE_METADATA_ONLY")
    emit("FORMAT_VALIDATED=NO")
    emit("DOWNLOAD_POST_ATTEMPTS=0")
    reply = ask("One quota-bearing download for this candidate? Type DOWNLOAD ONE or anything else to cancel: ")
    if reply.strip() != "DOWNLOAD ONE":
        emit("OWNER_CANCELLED")
        return 0

    # Preflight local private cache BEFORE quota-bearing POST.
    if cache_root is None:
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SubtitleApiError("PRIVATE_CACHE_LOCATION_NOT_CONFIGURED")
        cache_root = Path(local) / "TorrentTVVietsub" / "subtitle-trials"
    root = Path(cache_root)
    if root.is_symlink():
        raise SubtitleApiError("UNSAFE_CACHE_ROOT")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, probe = tempfile.mkstemp(prefix=".fallback-cache-probe-", dir=root)
    try:
        os.close(fd)
    finally:
        os.unlink(probe)

    emit("DOWNLOAD_POST_ATTEMPTS=1")
    if route.language == "vi":
        asset = client.download_manual_vi(media, discovery,
                                          file_id=route.selected_file_id,
                                          authorized=True)
    else:
        asset = client.download_manual_en(media, discovery,
                                          file_id=route.selected_file_id,
                                          authorized=True)
    destination = write_private_cache(root, media, asset)
    emit("DOWNLOAD_SRT_QA=PASS")
    emit(f"SRT_LANGUAGE={asset.language.upper()}")
    emit(f"SRT_CUES={asset.cues}")
    emit(f"PRIVATE_CACHE_FILENAME={destination.name}")
    emit("PRIVATE_CACHE_SAVED=YES")
    emit("AI_TEXT_UPLOADED=NO")
    emit("NEXT_GATE=USE_VI_WITH_BINDING" if asset.language == "vi"
         else "NEXT_GATE=EN_TRANSLATION_PROVIDER_AUTHORIZATION")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="VI-first with optional matched EN fallback")
    parser.add_argument("--imdb-id", required=True)
    parser.add_argument("--search-policy", choices=SEARCH_POLICIES,
                        default="VI_FAST", help="VI_FAST (default), EN_DIRECT, VI_FULL")
    args = parser.parse_args()
    token = os.environ.get("OPENSUBTITLES_API_KEY")
    if not token or not token.strip() or "\r" in token or "\n" in token:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        name = input("Authorized video release filename (local input only): ")
        return owner_fallback_trial(OpenSubtitles(api_key=token), name, args.imdb_id,
                                    search_policy=args.search_policy)
    except SubtitleApiError as exc:
        print(str(exc))
        return 1
    except (OSError, EOFError, KeyboardInterrupt):
        print("OWNER_FALLBACK_LOCAL_STOP")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
