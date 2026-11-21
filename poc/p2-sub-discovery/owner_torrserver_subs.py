"""Owner-local TorrServer /subs adapter for external in-torrent subtitle FILES.

The endpoint explicitly excludes subtitle tracks embedded in MKV. This
adapter never accesses /play, /ffp, GStreamer, MKV bytes, or remote hosts.
Only a separately verified TV/media selection may call list_for_media().
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import re
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, ProxyHandler

from matcher import Media
from opensubtitles import Asset, MAX_SUBTITLE_BYTES, SubtitleApiError, validate_timed_text
from owner_torrserver_readonly import OwnerLocalTorrServer, _NoRedirect

_HASH = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
_LANG_CODES = {"en": {"en", "eng", "english"},
               "vi": {"vi", "vie", "vietnamese", "vietsub"}}
_SOURCE_EXTENSIONS = {"srt", "vtt", "ass", "ssa"}
_MAX_LIST_BYTES = 64 * 1024


class TorrServerSubsUnavailable(ValueError):
    """Fixed code only, never include a torrent hash, URL or subtitle text."""


def _local_get(url: str, timeout_sec: float, max_bytes: int) -> bytes:
    # URLs are constructed exclusively from configured 127.0.0.1 and the
    # validated hash/index below. No redirects, proxies or arbitrary URL.
    request = Request(url, method="GET", headers={"Cache-Control": "no-store"})
    opener = build_opener(ProxyHandler({}), _NoRedirect())
    try:
        with opener.open(request, timeout=timeout_sec) as response:
            if response.status != 200:
                raise TorrServerSubsUnavailable("TS_SUBS_HTTP_UNAVAILABLE")
            length = response.headers.get("Content-Length")
            if length is not None and (
                    not length.isdecimal() or int(length) > max_bytes):
                raise TorrServerSubsUnavailable("TS_SUBS_TOO_LARGE")
            raw = response.read(max_bytes + 1)
            if not 0 < len(raw) <= max_bytes:
                raise TorrServerSubsUnavailable("TS_SUBS_TOO_LARGE")
            return raw
    except (HTTPError, URLError, TimeoutError, OSError):
        raise TorrServerSubsUnavailable("TS_SUBS_HTTP_UNAVAILABLE") from None


@dataclass(frozen=True)
class SidecarTrack:
    index: int
    language: str


@dataclass(frozen=True)
class SidecarInventory:
    media: Media
    vi: SidecarTrack | None = None
    en: SidecarTrack | None = None


class OwnerTorrServerSubtitleReader:
    def __init__(self, config: OwnerLocalTorrServer, *,
                 transport: Callable[[str, float, int], bytes] = _local_get):
        if not isinstance(config, OwnerLocalTorrServer) or not callable(transport):
            raise TorrServerSubsUnavailable("TS_SUBS_CONFIGURATION_INVALID")
        self._config = config
        self._transport = transport

    def _address(self, media: Media) -> str:
        if (not isinstance(media, Media)
                or media.server_profile_id != self._config.profile_id
                or not isinstance(media.torrent_hash, str)
                or _HASH.fullmatch(media.torrent_hash) is None
                or type(media.file_index) is not int
                or not 0 <= media.file_index < 4096):
            raise TorrServerSubsUnavailable("TS_SUBS_MEDIA_IDENTITY_INVALID")
        return ("http://127.0.0.1:" + str(self._config.localhost_port)
                + "/subs/" + media.torrent_hash + "/" + str(media.file_index))

    @staticmethod
    def _language(row: dict) -> str | None:
        name = row.get("name")
        fmt = row.get("format")
        if (not isinstance(name, str) or not 1 <= len(name) <= 512
                or not isinstance(fmt, str) or fmt not in _SOURCE_EXTENSIONS
                or not name.casefold().endswith("." + fmt)):
            return None
        # Upstream TorrServer recognizes EN but generally reports Vietnamese
        # as "und"; explicit suffix tokens in the companion filename matter.
        tokens = set(re.split(r"[^a-z]+", name.casefold()))
        detected = {lang for lang, keys in _LANG_CODES.items() if tokens & keys}
        if len(detected) == 1:
            return detected.pop()
        if detected:
            return None
        return "en" if row.get("lang") == "en" else None

    def list_for_media(self, media: Media) -> SidecarInventory:
        url = self._address(media)
        try:
            raw = self._transport(url, 2.0, _MAX_LIST_BYTES)
            rows = json.loads(raw.decode("utf-8"))
        except (TorrServerSubsUnavailable, UnicodeError, ValueError, TypeError):
            raise TorrServerSubsUnavailable("TS_SUBS_LIST_UNAVAILABLE") from None
        if not isinstance(rows, list) or len(rows) > 64:
            raise TorrServerSubsUnavailable("TS_SUBS_LIST_INVALID")
        chosen: dict[str, list[SidecarTrack]] = {"vi": [], "en": []}
        for row in rows:
            if not isinstance(row, dict) or type(row.get("index")) is not int:
                raise TorrServerSubsUnavailable("TS_SUBS_LIST_INVALID")
            if not 0 <= row["index"] < 4096:
                raise TorrServerSubsUnavailable("TS_SUBS_LIST_INVALID")
            language = self._language(row)
            if language in chosen:
                chosen[language].append(SidecarTrack(row["index"], language))
        return SidecarInventory(
            media=media,
            vi=chosen["vi"][0] if len(chosen["vi"]) == 1 else None,
            en=chosen["en"][0] if len(chosen["en"]) == 1 else None,
        )

    def download(self, inventory: SidecarInventory,
                 track: SidecarTrack) -> Asset:
        if (not isinstance(inventory, SidecarInventory)
                or not isinstance(track, SidecarTrack)
                or track.language not in ("vi", "en")
                or track != getattr(inventory, track.language)):
            raise TorrServerSubsUnavailable("TS_SUBS_TRACK_NOT_SELECTED")
        url = (self._address(inventory.media) + "?track=" + str(track.index)
               + "&format=vtt&encoding=utf8")
        try:
            raw = self._transport(url, 8.0, MAX_SUBTITLE_BYTES)
            count = validate_timed_text(raw, "vtt")
            # Normalize with the existing P2 cue parser, without running a
            # local video ffprobe or external MKV extractor.
            from cue_pipeline import parse_cues, render
            normalized = render(parse_cues(raw, "vtt"), "srt")
            cues = validate_timed_text(normalized, "srt")
        except (TorrServerSubsUnavailable, SubtitleApiError, UnicodeError, ValueError,
                TypeError, OSError):
            raise TorrServerSubsUnavailable("TS_SUBS_TRACK_UNAVAILABLE") from None
        if count != cues or len(normalized) > MAX_SUBTITLE_BYTES:
            raise TorrServerSubsUnavailable("TS_SUBS_TRACK_INVALID")
        return Asset(track.index, track.language, "srt", normalized,
                     hashlib.sha256(normalized).hexdigest(), cues)
