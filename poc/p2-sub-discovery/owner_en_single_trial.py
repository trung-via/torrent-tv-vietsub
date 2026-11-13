"""Owner-local single authorized *non-SDH* English subtitle download probe.

Only after an exact user-supplied expected release and a freshly confident
VI_FAST -> EN route; no Gemini/TV/TorrServer actions. All credentials and
subtitle bytes stay on owner laptop. A persistent per-target claim is created
BEFORE the one quota-bearing POST, to prevent accidental reruns after failures.
"""
from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
from typing import Callable
import re
import tempfile
import uuid

from matcher import Media, _release_stem_and_accessibility, parse_release
from opensubtitles import Asset, OpenSubtitles, SubtitleApiError, write_private_cache
from vi_en_fallback import select_vi_then_en

_SAFE_GROUP = re.compile(r"[a-zA-Z0-9]{2,30}\Z")


def _preflight_cache(root: Path) -> None:
    if root.is_symlink():
        raise SubtitleApiError("UNSAFE_CACHE_ROOT")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, probe = tempfile.mkstemp(prefix=".en-probe-", dir=root)
    try:
        os.close(fd)
    finally:
        Path(probe).unlink(missing_ok=True)


def _claim_one_post(root: Path, filename: str, release: str) -> None:
    """Owner-local, no-reset marker: once claimed, no repeat without review."""
    digest = hashlib.sha256(
        (filename.casefold() + "\0" + release.casefold()).encode("utf-8")
    ).hexdigest()
    target = root / (".en-once-" + digest)
    if target.is_symlink():
        raise SubtitleApiError("EN_DOWNLOAD_ALREADY_ATTEMPTED")
    try:
        fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise SubtitleApiError("EN_DOWNLOAD_ALREADY_ATTEMPTED") from None
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(b"ONE_POST_CLAIMED\n")
    except BaseException:
        # Keep marker on uncertain I/O outcome to fail closed on retries.
        raise


def download_one_exact_en(client: OpenSubtitles, filename: str, expected_release: str,
                          expected_group: str, *, ask=input, emit=print,
                          cache_root: Path | None = None,
                          imdb_id: str | None = None,
                          on_cached_en: Callable[[Path, Asset], object] | None = None) -> int:
    if on_cached_en is not None and not callable(on_cached_en):
        raise SubtitleApiError("INVALID_EN_CACHE_CALLBACK")
    if (not isinstance(filename, str) or not filename.strip()
            or len(filename) > 255 or "/" in filename or "\\" in filename
            or any(ord(ch) < 32 for ch in filename)):
        raise SubtitleApiError("BAD_MEDIA_FILENAME")
    if (not isinstance(expected_release, str) or not expected_release.strip()
            or len(expected_release) > 255
            or any(ord(ch) < 32 for ch in expected_release)):
        raise SubtitleApiError("BAD_EXPECTED_RELEASE")
    if not isinstance(expected_group, str) or not _SAFE_GROUP.fullmatch(expected_group):
        raise SubtitleApiError("BAD_EXPECTED_GROUP")
    media = Media("owner-one-en-unverified", uuid.uuid4().hex, 0, filename.strip())
    video = parse_release(media.filename)
    if video.year is None or video.title == "" or video.group != expected_group.casefold():
        raise SubtitleApiError("VIDEO_RELEASE_METADATA_MISMATCH")

    route = select_vi_then_en(client, media, imdb_id=imdb_id, policy="VI_FAST")
    emit("D2_EN_SINGLE_OWNER_TRIAL")
    emit("MEDIA_BINDING=UNVERIFIED")
    emit("SEARCH_POLICY=VI_FAST")
    emit(f"ROUTE={route.status}")
    emit(f"SEARCH_GET_REQUESTS={route.get_requests}")
    emit("DOWNLOAD_POST_ATTEMPTS=0")
    emit("TRANSLATION_REQUESTS=0")
    if (route.status != "EN_TRANSLATE" or route.reason != "CONFIDENT_EN_RELEASE"
            or route.language != "en" or route.selected_file_id is None
            or route.en is None):
        emit("NEXT_GATE=SOURCE_REVIEW_NO_DOWNLOAD")
        return 0

    chosen = [c for c in route.en.candidates
              if c.file_id == route.selected_file_id and c.subtitle.language == "en"]
    if len(chosen) != 1:
        raise SubtitleApiError("CANDIDATE_BINDING_MISMATCH")
    release = chosen[0].subtitle.release_name
    parsed = parse_release(release)
    _, sdh = _release_stem_and_accessibility(release)
    if (release.casefold().strip() != expected_release.casefold().strip()
            or parsed.group != video.group or sdh
            or any(f not in route.en.decision.winner.evidence
                   for f in ("title", "year", "source", "group", "resolution", "codec"))):
        emit("EXPECTED_STANDARD_EN_NOT_SELECTED")
        emit("NEXT_GATE=SOURCE_REVIEW_NO_DOWNLOAD")
        return 0
    emit("EXACT_RELEASE_MATCH=YES")
    emit("EN_STANDARD_NOT_SDH=YES")
    emit(f"EN_WINNER_SCORE={route.en.decision.winner.score}")
    emit("REAL_VIDEO_SYNC_VERIFIED=NO")

    reply = ask("One quota-bearing EN download? Type DOWNLOAD ONE to proceed, else cancel: ")
    if reply != "DOWNLOAD ONE":
        emit("OWNER_CANCELLED")
        return 0

    if cache_root is None:
        local = os.environ.get("LOCALAPPDATA")
        if not local:
            raise SubtitleApiError("PRIVATE_CACHE_LOCATION_NOT_CONFIGURED")
        cache_root = Path(local) / "TorrentTVVietsub" / "subtitle-trials"
    root = Path(cache_root)
    _preflight_cache(root)
    _claim_one_post(root, media.filename, release)
    emit("DOWNLOAD_POST_ATTEMPTS=1")
    # A single API POST only; never retry on failed HTTP/QA/cache save.
    asset = client.download_manual_en(media, route.en,
                                      file_id=route.selected_file_id,
                                      authorized=True)
    destination = write_private_cache(root, media, asset)
    emit("DOWNLOAD_AND_SRT_QA=PASS")
    emit(f"SRT_CUES={asset.cues}")
    emit(f"CONTENT_SHA256={asset.sha256}")
    emit(f"PRIVATE_CACHE_FILENAME={destination.name}")
    emit("PRIVATE_CACHE_SAVED=YES")
    emit("AI_TEXT_UPLOADED=NO")
    emit("TV_SYNC_VERIFIED=NO")
    # Optional in-process P2 integration. D2 itself never imports or invokes
    # Gemini: the caller owns any cloud-upload authorization. No duplicate
    # manifest or subtitle file is created. The one-POST marker remains even
    # if the downstream worker fails after the SRT has been safely cached.
    if on_cached_en is None:
        emit("NEXT_GATE=LOCAL_EN_CONTENT_AND_TRANSLATION_REVIEW")
    else:
        emit("NEXT_GATE=LOCAL_P2_DIRECT_HANDOFF")
        on_cached_en(destination, asset)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="One owner-approved EN-only release download")
    parser.add_argument("--release-name", required=True)
    parser.add_argument("--expected-en-release", required=True)
    parser.add_argument("--expected-group", required=True)
    parser.add_argument("--imdb-id", required=False)
    args = parser.parse_args()
    key = os.environ.get("OPENSUBTITLES_API_KEY")
    if not key or not key.strip() or "\n" in key or "\r" in key:
        print("API_KEY_NOT_CONFIGURED")
        return 1
    try:
        return download_one_exact_en(
            OpenSubtitles(api_key=key), args.release_name,
            args.expected_en_release, args.expected_group,
            imdb_id=args.imdb_id)
    except SubtitleApiError as exc:
        print(str(exc))
        print("NO_AUTOMATIC_RETRY=YES")
        return 1
    except (OSError, KeyboardInterrupt, EOFError):
        print("OWNER_EN_TRIAL_LOCAL_STOP")
        print("NO_AUTOMATIC_RETRY=YES")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
