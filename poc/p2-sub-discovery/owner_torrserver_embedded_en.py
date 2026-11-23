"""Extract one verified English *text* subtitle stream from an MKV torrent.

No OpenSubtitles API, torrent mutation, TV callback or provider translation.
The Owner supplies its pinned localhost TorrServer profile and the already
verified server/hash/file identity. /ffp inventories tracks; ffmpeg reads the
exact /play file and demuxes subtitles, without downloading a separate MKV.

This is best-effort: missing peers, a non-seekable stream, missing ffmpeg,
bitmap-only tracks and extraction deadlines all return sanitized unavailable
codes. A torrent may still have to transfer substantial media pieces.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from typing import Callable

from matcher import Media
from opensubtitles import Asset, MAX_SUBTITLE_BYTES, SubtitleApiError, validate_timed_text
from owner_torrserver_ffp_tracks import _read_local_ffp
from owner_torrserver_readonly import OwnerLocalTorrServer

_HASH = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
_TEXT_CODECS = frozenset(("subrip", "ass", "ssa", "webvtt", "mov_text", "text"))
_EN = frozenset(("en", "eng", "en-us", "en-gb", "english"))
_MAX_PROBE_BYTES = 65536


class EmbeddedEnglishUnavailable(ValueError):
    """Stable local-only code; never return URLs, torrent hashes or movie text."""


def _english_text_track(raw: bytes) -> int:
    """Select one unambiguous global ffprobe stream index, not a track ordinal."""
    if not isinstance(raw, bytes) or not 0 < len(raw) <= _MAX_PROBE_BYTES:
        raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_INVALID")
    try:
        data = json.loads(raw.decode("utf-8", "strict"))
        streams = data["streams"]
    except (ValueError, UnicodeError, TypeError, KeyError, RecursionError):
        raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_INVALID") from None
    if not isinstance(streams, list) or not 0 < len(streams) <= 128:
        raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_INVALID")
    seen = set()
    choices: list[tuple[int, bool]] = []
    for entry in streams:
        if not isinstance(entry, dict) or type(entry.get("index")) is not int:
            raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_INVALID")
        index = entry["index"]
        if not 0 <= index < 128 or index in seen:
            raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_INVALID")
        seen.add(index)
        if entry.get("codec_type") != "subtitle":
            continue
        tags = entry.get("tags")
        if not isinstance(tags, dict):
            continue
        language = tags.get("language")
        if not isinstance(language, str) or language.strip().casefold() not in _EN:
            continue
        if entry.get("codec_name") not in _TEXT_CODECS:
            continue
        disposition = entry.get("disposition")
        default = (isinstance(disposition, dict)
                   and disposition.get("default") == 1)
        choices.append((index, default))
    if not choices:
        raise EmbeddedEnglishUnavailable("EMBEDDED_EN_TEXT_TRACK_NOT_FOUND")
    if len(choices) == 1:
        return choices[0][0]
    preferred = [index for index, default in choices if default]
    if len(preferred) != 1:
        raise EmbeddedEnglishUnavailable("EMBEDDED_EN_TRACK_AMBIGUOUS")
    return preferred[0]


def _run_ffmpeg(args: list[str], timeout: float) -> int:
    """Conceal ffmpeg output: upstream movie paths and URL must stay private."""
    return subprocess.run(args, timeout=timeout, stdin=subprocess.DEVNULL,
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL, check=False).returncode


class OwnerTorrServerEmbeddedEnglishReader:
    def __init__(self, config: OwnerLocalTorrServer, *,
                 probe: Callable[[str, float], bytes] = _read_local_ffp,
                 runner: Callable[[list[str], float], int] = _run_ffmpeg,
                 ffmpeg_executable: str = "ffmpeg",
                 timeout_sec: float = 45.0):
        if (not isinstance(config, OwnerLocalTorrServer)
                or not callable(probe) or not callable(runner)
                or not isinstance(ffmpeg_executable, str)
                or not ffmpeg_executable.strip()
                or type(timeout_sec) not in (int, float)
                or not 1 <= timeout_sec <= 180):
            raise EmbeddedEnglishUnavailable("EMBEDDED_EN_CONFIG_INVALID")
        self._config = config
        self._probe = probe
        self._runner = runner
        self._ffmpeg = ffmpeg_executable
        self._timeout = float(timeout_sec)

    def extract(self, media: Media, *, private_root: Path) -> Asset:
        cfg = self._config
        if (not isinstance(media, Media)
                or media.server_profile_id != cfg.profile_id
                or not isinstance(media.torrent_hash, str)
                or _HASH.fullmatch(media.torrent_hash) is None
                or type(media.file_index) is not int
                or not 0 <= media.file_index < 4096
                or not isinstance(private_root, Path)
                or not private_root.is_absolute()
                or private_root.is_symlink()):
            raise EmbeddedEnglishUnavailable("EMBEDDED_EN_MEDIA_INVALID")
        base = "http://127.0.0.1:" + str(cfg.localhost_port)
        selected = "/" + media.torrent_hash + "/" + str(media.file_index)
        try:
            track = _english_text_track(self._probe(base + "/ffp" + selected, 3.0))
        except EmbeddedEnglishUnavailable:
            raise
        except (OSError, TimeoutError, ValueError, TypeError):
            raise EmbeddedEnglishUnavailable("EMBEDDED_EN_PROBE_UNAVAILABLE") from None
        private_root.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.TemporaryDirectory(prefix=".embedded-en-", dir=private_root) as temp:
            dest = Path(temp) / "en.srt"
            command = [
                self._ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error",
                "-i", base + "/play" + selected,
                "-map", "0:" + str(track), "-vn", "-an", "-dn",
                "-c:s", "srt", "-f", "srt", str(dest),
            ]
            try:
                code = self._runner(command, self._timeout)
            except (OSError, subprocess.TimeoutExpired):
                raise EmbeddedEnglishUnavailable("EMBEDDED_EN_EXTRACT_UNAVAILABLE") from None
            if code != 0 or not dest.is_file() or dest.is_symlink():
                raise EmbeddedEnglishUnavailable("EMBEDDED_EN_EXTRACT_UNAVAILABLE")
            if not 0 < dest.stat().st_size <= MAX_SUBTITLE_BYTES:
                raise EmbeddedEnglishUnavailable("EMBEDDED_EN_EXTRACT_SIZE_INVALID")
            try:
                data = dest.read_bytes()
                count = validate_timed_text(data, "srt")
            except (SubtitleApiError, ValueError, UnicodeError, OSError):
                raise EmbeddedEnglishUnavailable("EMBEDDED_EN_TEXT_INVALID") from None
        return Asset(track, "en", "srt", data, hashlib.sha256(data).hexdigest(), count)
