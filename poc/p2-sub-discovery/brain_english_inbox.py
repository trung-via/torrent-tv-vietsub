"""Temporary Brain-prepared EN inbox; no API, AGY acquisition or TV transport.

The Brain/Owner staging boundary writes only into the existing Owner-private
cache. The TV tap remains the *only* trigger for the established LEAN120/P4
translation path. Staged files are bound to P3's exact server/hash/fileIndex
fingerprint, not to a title search or a global "latest English subtitle".
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile

from agy_opensubtitles_acquisition import AgyEnglishUnavailable, _validate_source
from matcher import Media
from opensubtitles import Asset, MAX_SUBTITLE_BYTES, SubtitleApiError, validate_timed_text
from owner_selected_file_resolver import _fingerprint

_FP = re.compile(r"[0-9a-f]{64}\Z")
_SCHEMA = "TTV-BRAIN-EN-INBOX-V1"
_FILE = "english.srt"
_MANIFEST = "receipt.json"


class BrainEnglishUnavailable(ValueError):
    """Only safe status codes escape; never emit private paths or cue text."""


def _private_inbox(cache_root: Path) -> Path:
    if (not isinstance(cache_root, Path) or not cache_root.is_absolute()
            or cache_root.is_symlink()):
        raise BrainEnglishUnavailable("BRAIN_EN_PRIVATE_ROOT_INVALID")
    inbox = cache_root / ".brain-en-inbox"
    if inbox.is_symlink():
        raise BrainEnglishUnavailable("BRAIN_EN_INBOX_SYMLINK")
    return inbox


def _fp(source_fingerprint: str) -> str:
    if not isinstance(source_fingerprint, str) or not _FP.fullmatch(source_fingerprint):
        raise BrainEnglishUnavailable("BRAIN_EN_FINGERPRINT_INVALID")
    return source_fingerprint


def _name(video_name: str) -> str:
    if (not isinstance(video_name, str) or not 1 <= len(video_name) <= 255
            or video_name.startswith(".") or "/" in video_name
            or "\\" in video_name
            or any(ord(c) < 32 or ord(c) == 127 for c in video_name)):
        raise BrainEnglishUnavailable("BRAIN_EN_VIDEO_NAME_INVALID")
    return video_name


def _content(contents: bytes) -> tuple[str, int]:
    if not isinstance(contents, bytes) or not 0 < len(contents) <= MAX_SUBTITLE_BYTES:
        raise BrainEnglishUnavailable("BRAIN_EN_SRT_SIZE_INVALID")
    try:
        cues = validate_timed_text(contents, "srt")
    except (UnicodeError, ValueError, SubtitleApiError):
        raise BrainEnglishUnavailable("BRAIN_EN_SRT_QA_FAILED") from None
    return hashlib.sha256(contents).hexdigest(), cues


def stage_brain_english(*, cache_root: Path, source_fingerprint: str,
                        video_name: str, release_name: str, source_page: str,
                        srt_file: Path) -> Path:
    """Stage a locally supplied SRT atomically; no remote fetch or overwrite.

    The caller must obtain the fingerprint from trusted Owner/TorrServer
    metadata, not invent one from the human-visible film title.
    """
    inbox = _private_inbox(cache_root)
    fp = _fp(source_fingerprint)
    video_name = _name(video_name)
    if (not isinstance(release_name, str) or not release_name.strip()
            or len(release_name) > 512 or
            any(ord(c) < 32 or ord(c) == 127 for c in release_name)
            or not isinstance(source_page, str) or len(source_page) > 2048
            or any(ord(c) < 32 or ord(c) == 127 for c in source_page)):
        raise BrainEnglishUnavailable("BRAIN_EN_SOURCE_METADATA_INVALID")
    if (not isinstance(srt_file, Path) or not srt_file.is_absolute()
            or srt_file.is_symlink() or not srt_file.is_file()):
        raise BrainEnglishUnavailable("BRAIN_EN_INPUT_FILE_INVALID")
    try:
        if srt_file.stat().st_size > MAX_SUBTITLE_BYTES:
            raise BrainEnglishUnavailable("BRAIN_EN_SRT_SIZE_INVALID")
        payload = srt_file.read_bytes()
    except OSError:
        raise BrainEnglishUnavailable("BRAIN_EN_INPUT_UNREADABLE") from None
    digest, cues = _content(payload)
    receipt = {
        "schema": _SCHEMA, "source_fingerprint": fp,
        "video_name": video_name, "release_name": release_name,
        "source_page": source_page, "language": "en",
        "sha256": digest, "cues": cues,
    }
    expected = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode("utf-8")
    inbox.mkdir(parents=True, exist_ok=True, mode=0o700)
    dest = inbox / fp
    if dest.is_symlink():
        raise BrainEnglishUnavailable("BRAIN_EN_DESTINATION_UNTRUSTED")
    if dest.exists():
        if (dest.is_dir() and not (dest / _FILE).is_symlink()
                and not (dest / _MANIFEST).is_symlink()
                and (dest / _FILE).is_file() and (dest / _MANIFEST).is_file()
                and (dest / _FILE).read_bytes() == payload
                and (dest / _MANIFEST).read_bytes() == expected):
            return dest
        raise BrainEnglishUnavailable("BRAIN_EN_STAGE_CONFLICT")
    temp = Path(tempfile.mkdtemp(prefix=".pending-", dir=inbox))
    try:
        for filename, data in ((_FILE, payload), (_MANIFEST, expected)):
            with (temp / filename).open("xb") as out:
                out.write(data)
                out.flush()
                os.fsync(out.fileno())
        os.rename(temp, dest)
    except FileExistsError:
        raise BrainEnglishUnavailable("BRAIN_EN_STAGE_CONFLICT") from None
    finally:
        if temp.exists():
            shutil.rmtree(temp)
    return dest


def acquire_brain_english(media: Media, cache_root: Path) -> Asset:
    """Read exact staged EN at TV activation; never fall back to API/AGY search."""
    if not isinstance(media, Media):
        raise BrainEnglishUnavailable("BRAIN_EN_VERIFIED_MEDIA_REQUIRED")
    inbox = _private_inbox(cache_root)
    fp = _fingerprint(*media.key)
    dest = inbox / fp
    if not dest.exists():
        raise BrainEnglishUnavailable("BRAIN_EN_NOT_STAGED")
    if (dest.is_symlink() or not dest.is_dir()
            or (dest / _FILE).is_symlink() or (dest / _MANIFEST).is_symlink()
            or not (dest / _FILE).is_file() or not (dest / _MANIFEST).is_file()):
        raise BrainEnglishUnavailable("BRAIN_EN_STAGE_UNTRUSTED")
    try:
        if (dest / _MANIFEST).stat().st_size > 4096:
            raise BrainEnglishUnavailable("BRAIN_EN_RECEIPT_INVALID")
        receipt = json.loads((dest / _MANIFEST).read_text(encoding="utf-8"))
        if (not isinstance(receipt, dict) or set(receipt) != {
                "schema", "source_fingerprint", "video_name", "release_name",
                "source_page", "language", "sha256", "cues"}
                or receipt["schema"] != _SCHEMA
                or receipt["source_fingerprint"] != fp
                or receipt["video_name"] != media.filename
                or receipt["language"] != "en"
                or not isinstance(receipt["sha256"], str)
                or not _FP.fullmatch(receipt["sha256"])
                or type(receipt["cues"]) is not int or receipt["cues"] < 1):
            raise BrainEnglishUnavailable("BRAIN_EN_RECEIPT_INVALID")
        if (dest / _FILE).stat().st_size > MAX_SUBTITLE_BYTES:
            raise BrainEnglishUnavailable("BRAIN_EN_SRT_SIZE_INVALID")
        contents = (dest / _FILE).read_bytes()
        digest, count = _content(contents)
        if digest != receipt["sha256"] or count != receipt["cues"]:
            raise BrainEnglishUnavailable("BRAIN_EN_SRT_CHANGED")
        _validate_source(media, {
            "release_name": receipt["release_name"],
            "source_page": receipt["source_page"],
        })
    except BrainEnglishUnavailable:
        raise
    except AgyEnglishUnavailable:
        raise BrainEnglishUnavailable("BRAIN_EN_RELEASE_MISMATCH") from None
    except (OSError, ValueError, TypeError, KeyError, UnicodeError):
        raise BrainEnglishUnavailable("BRAIN_EN_RECEIPT_INVALID") from None
    return Asset(0, "en", "srt", contents, digest, count)


def main() -> None:
    parser = argparse.ArgumentParser(description="Owner-private Brain EN staging only")
    parser.add_argument("--cache-root", type=lambda x: Path(x).absolute(), required=True)
    parser.add_argument("--source-fingerprint", required=True)
    parser.add_argument("--video-name", required=True)
    parser.add_argument("--release-name", required=True)
    parser.add_argument("--source-page", required=True)
    parser.add_argument("--srt", type=lambda x: Path(x).absolute(), required=True)
    args = parser.parse_args()
    stage_brain_english(
        cache_root=args.cache_root, source_fingerprint=args.source_fingerprint,
        video_name=args.video_name, release_name=args.release_name,
        source_page=args.source_page, srt_file=args.srt)
    print("BRAIN_EN_STAGE=READY_EXACT_MEDIA")


if __name__ == "__main__":
    main()
