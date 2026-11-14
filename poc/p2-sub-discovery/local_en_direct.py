"""LOCAL_EN_DIRECT: owner-private, exact-selected-file English subtitle reuse.

Source-only adapter: no TorrServer requests, no OMP hooks, no Gemini or
OpenSubtitles calls, no networking, no P4 delivery. A trusted event adapter
must attest the current server/hash/fileIndex and supply a complete LOCAL
media file or exact English sidecar. No torrent streaming URLs are accepted.

Successful extraction writes a validated SRT to the existing D2 private cache,
returning its existing Asset + Path for #140.after_en_cached(). Never use a
filename or source-attested boolean as a P4/D3 authenticated identity.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
from typing import Callable

from matcher import Media
from opensubtitles import Asset, MAX_SUBTITLE_BYTES, validate_timed_text, write_private_cache

_HASH = re.compile(r"(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})\Z")
_TAG = re.compile(r"[a-zA-Z0-9_-]{1,128}\Z")
_EN_CODECS = frozenset({"subrip", "srt", "ass", "ssa", "webvtt", "mov_text", "text"})
_VIDEOS = frozenset({".mkv", ".mp4", ".m4v", ".webm"})
_SIDECAR_LANG = frozenset({"en", "eng", "english"})
_MAX_PROBE = 64 * 1024


class LocalSourceError(ValueError):
    """Sanitized local-only error code; never append a path/stream or caption."""


@dataclass(frozen=True)
class LocalMediaSelection:
    # Caller MUST have verified these against a current authenticated OMP TV
    # PlayRequest and the same selected TorrServer file; not verified here.
    attested: bool
    active: bool
    owner_authorized: bool
    viewer_choice: str
    local_vi_state: str
    server_id: str
    torrent_hash: str
    file_index: int
    video_name: str
    private_media_root: Path
    video_path: Path | None = None
    en_sidecar_path: Path | None = None
    # Only for embedded extraction: server/owner must confirm video complete.
    video_file_complete: bool = False


@dataclass(frozen=True)
class LocalEnglishResult:
    asset: Asset
    private_cache_file: Path
    source_kind: str  # SIDECAR_SRT | SIDECAR_VTT | EMBEDDED_TEXT


Executor = Callable[[list[str], int, int], bytes]


def _execute_local(argv: list[str], timeout_sec: int, size_cap: int) -> bytes:
    """Bounded local-only binaries. No media path, stdout or stderr in errors."""
    try:
        p = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           timeout=timeout_sec, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise LocalSourceError("LOCAL_SUBTITLE_TOOL_UNAVAILABLE_OR_TIMEOUT") from None
    if p.returncode != 0 or not p.stdout or len(p.stdout) > size_cap:
        raise LocalSourceError("LOCAL_SUBTITLE_TOOL_FAILED_OR_TOO_LARGE")
    return p.stdout


def _inside_private_root(path: Path, root: Path) -> Path:
    if not isinstance(path, Path) or not path.is_absolute():
        raise LocalSourceError("LOCAL_SOURCE_ABSOLUTE_PATH_REQUIRED")
    if not isinstance(root, Path) or not root.is_absolute():
        raise LocalSourceError("LOCAL_ROOT_ABSOLUTE_PATH_REQUIRED")
    try:
        canonical_root = root.resolve(strict=True)
        canonical = path.resolve(strict=True)
    except (OSError, RuntimeError):
        raise LocalSourceError("LOCAL_SOURCE_NOT_READABLE") from None
    if not canonical.is_relative_to(canonical_root) or not canonical.is_file():
        raise LocalSourceError("LOCAL_SOURCE_OUTSIDE_ROOT")
    if path.is_symlink() or root.is_symlink():
        raise LocalSourceError("LOCAL_SOURCE_SYMLINK_REFUSED")
    # Refuse symlinked intermediate directories even when they resolve within
    # root. The first parent strictly inside the allowed root is validated.
    rel = path.relative_to(root) if path.is_relative_to(root) else None
    if rel is None or ".." in rel.parts:
        raise LocalSourceError("LOCAL_SOURCE_UNTRUSTED_PATH")
    walk = root
    for part in rel.parts[:-1]:
        walk = walk / part
        if walk.is_symlink():
            raise LocalSourceError("LOCAL_SOURCE_SYMLINK_REFUSED")
    return canonical


def _identity(m: LocalMediaSelection) -> Media:
    if not isinstance(m, LocalMediaSelection) or (
            m.attested is not True or m.active is not True
            or m.owner_authorized is not True
            or m.viewer_choice != "ON"
            or m.local_vi_state != "ABSENT"):
        raise LocalSourceError("LOCAL_MEDIA_NOT_AUTHORIZED_OR_NOT_SELECTED")
    if (not isinstance(m.server_id, str) or _TAG.fullmatch(m.server_id) is None
            or not isinstance(m.torrent_hash, str)
            or _HASH.fullmatch(m.torrent_hash) is None
            or type(m.file_index) is not int or m.file_index < 0
            or not isinstance(m.video_name, str)
            or not 1 <= len(m.video_name) <= 255
            or m.video_name.startswith(".") or "/" in m.video_name
            or "\\" in m.video_name
            or any(ord(ch) < 32 or ord(ch) == 127 for ch in m.video_name)):
        raise LocalSourceError("LOCAL_MEDIA_IDENTITY_INVALID")
    return Media(m.server_id, m.torrent_hash.lower(), m.file_index, m.video_name)


def _exact_en_sidecar(m: LocalMediaSelection, path: Path) -> str:
    name = path.name
    # Accept only same video stem with explicit EN suffix and known format.
    stem = Path(m.video_name).stem
    found = re.fullmatch(re.escape(stem) + r"\.(en|eng|english)\.(srt|vtt)", name,
                         flags=re.IGNORECASE)
    if found is None:
        raise LocalSourceError("LOCAL_SIDECAR_NOT_EXACT_EN_FOR_VIDEO")
    return found.group(2).lower()


def _run_ffmpeg_local(source: Path, *, stream: int | None, runner: Executor) -> bytes:
    # File/pipe only: no http, https, tcp, concat, crypto, ssh, network input.
    args = ["ffmpeg", "-nostdin", "-hide_banner", "-v", "error",
            "-protocol_whitelist", "file,pipe", "-i", str(source)]
    if stream is not None:
        args += ["-map", "0:" + str(stream)]
    else:
        args += ["-map", "0:0"]
    args += ["-vn", "-an", "-c:s", "srt", "-f", "srt",
             "-fs", str(MAX_SUBTITLE_BYTES), "pipe:1"]
    return runner(args, 45, MAX_SUBTITLE_BYTES)


def _text_english_stream(path: Path, runner: Executor) -> int | None:
    args = ["ffprobe", "-v", "error", "-protocol_whitelist", "file,pipe",
            "-select_streams", "s",
            "-show_entries", "stream=index,codec_type,codec_name:stream_tags=language,title",
            "-of", "json", str(path)]
    response = runner(args, 20, _MAX_PROBE)
    try:
        rows = json.loads(response.decode("utf-8"))["streams"]
    except (UnicodeError, ValueError, KeyError, TypeError):
        raise LocalSourceError("LOCAL_MEDIA_PROBE_UNTRUSTED") from None
    if not isinstance(rows, list) or len(rows) > 64:
        raise LocalSourceError("LOCAL_MEDIA_PROBE_UNTRUSTED")
    selected = []
    for s in rows:
        if not isinstance(s, dict) or s.get("codec_type") != "subtitle":
            continue
        tags = s.get("tags") or {}
        if not isinstance(tags, dict):
            raise LocalSourceError("LOCAL_MEDIA_PROBE_UNTRUSTED")
        language = str(tags.get("language", "")).casefold()
        codec = s.get("codec_name")
        ix = s.get("index")
        if language in _SIDECAR_LANG and codec in _EN_CODECS:
            if type(ix) is not int or not 0 <= ix <= 255:
                raise LocalSourceError("LOCAL_MEDIA_PROBE_UNTRUSTED")
            label = str(tags.get("title", "")).casefold()
            if "sdh" not in label and "hearing impaired" not in label:
                selected.append(ix)
    if len(selected) > 1:
        raise LocalSourceError("LOCAL_EN_MULTIPLE_TEXT_TRACKS_AMBIGUOUS")
    return selected[0] if selected else None


def find_local_english(m: LocalMediaSelection, *, cache_root: Path,
                       runner: Executor = _execute_local) -> LocalEnglishResult | None:
    """Return eligible EN as private validated SRT, or None to use D2 VI_FAST.

    Invalid local sources/ambiguous tracks raise LocalSourceError instead of
    silently falling through to a quota-bearing remote search or upload.
    """
    media = _identity(m)
    if not isinstance(cache_root, Path) or not cache_root.is_absolute() or cache_root.is_symlink():
        raise LocalSourceError("LOCAL_PRIVATE_CACHE_REQUIRED")
    if not isinstance(m.private_media_root, Path) or not m.private_media_root.is_absolute():
        raise LocalSourceError("LOCAL_ROOT_ABSOLUTE_PATH_REQUIRED")
    if not callable(runner):
        raise LocalSourceError("LOCAL_RUNNER_REQUIRED")

    if m.video_path is not None:
        video = _inside_private_root(m.video_path, m.private_media_root)
        if video.name != m.video_name or video.suffix.casefold() not in _VIDEOS:
            raise LocalSourceError("LOCAL_VIDEO_IDENTITY_MISMATCH")
    else:
        video = None

    if m.en_sidecar_path is not None:
        side = _inside_private_root(m.en_sidecar_path, m.private_media_root)
        fmt = _exact_en_sidecar(m, side)
        if video is not None and side.parent != video.parent:
            raise LocalSourceError("LOCAL_SIDECAR_VIDEO_DIRECTORY_MISMATCH")
        if side.stat().st_size > MAX_SUBTITLE_BYTES:
            raise LocalSourceError("LOCAL_SUBTITLE_TOO_LARGE")
        contents = side.read_bytes() if fmt == "srt" else _run_ffmpeg_local(side, stream=None, runner=runner)
        kind = "SIDECAR_SRT" if fmt == "srt" else "SIDECAR_VTT"
    elif video is not None and m.video_file_complete is True:
        stream = _text_english_stream(video, runner)
        if stream is None:
            return None
        before = video.stat()
        contents = _run_ffmpeg_local(video, stream=stream, runner=runner)
        after = video.stat()
        if (before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns):
            raise LocalSourceError("LOCAL_VIDEO_CHANGED_DURING_EXTRACTION")
        kind = "EMBEDDED_TEXT"
    else:
        # A TorrServer stream URL, remote TV UI track label, or incomplete
        # movie cannot be interpreted as a readable owner-private local file.
        return None

    if (not isinstance(contents, bytes) or
            not 0 < len(contents) < MAX_SUBTITLE_BYTES):
        raise LocalSourceError("LOCAL_EN_SUBTITLE_SIZE_INVALID")
    try:
        count = validate_timed_text(contents, "srt")
    except ValueError:
        raise LocalSourceError("LOCAL_EN_TIMED_QA_FAILED") from None
    asset = Asset(0, "en", "srt", contents, hashlib.sha256(contents).hexdigest(), count)
    try:
        path = write_private_cache(cache_root, media, asset)
    except (ValueError, OSError):
        raise LocalSourceError("LOCAL_EN_CACHE_WRITE_REJECTED") from None
    return LocalEnglishResult(asset=asset, private_cache_file=path, source_kind=kind)
