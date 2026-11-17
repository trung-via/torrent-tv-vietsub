"""Bounded read-only TorrServer ffprobe inventory for authorized stream-only OMP.

The endpoint is reused from upstream OMP TorrServerClient.probe():
GET /ffp/<exact hash>/<file index>. No /stream, torrent add/rem, ffmpeg,
arbitrary host, proxy, redirects, media bytes, TV names, auth in URL or logs.

The owner PRIVATE policy independently authorizes exact torrent/path/rights
and a signed fresh TV request BEFORE calling this reader. Failure = UNKNOWN;
it NEVER guesses Vietnamese absence or calls OpenSubtitles/Gemini.
"""
from __future__ import annotations

import json
import re
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import Request, ProxyHandler, build_opener, HTTPRedirectHandler

from owner_torrserver_readonly import OwnerTorrServerReader

_HASH = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
_MAX_BYTES = 65536
_VI = frozenset(("vi", "vie", "vn", "vietnamese"))
_KNOWN_OTHER = frozenset(("en", "eng", "english", "fr", "fra", "fre", "es",
                          "spa", "de", "deu", "ger", "ja", "jpn", "ko", "kor",
                          "zh", "zho", "chi", "pt", "por", "ru", "rus", "und"))
_VALID_TYPES = frozenset(("video", "audio", "subtitle", "data", "attachment"))


class TorrServerProbeBlocked(ValueError):
    """Stable error code, no private endpoints or media content."""


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def _read_local_ffp(url: str, timeout: float) -> bytes:
    # Constructed exclusively by TorrServerFfpTrackReader from fixed localhost,
    # not supplied by TV or a public API. No redirects or environment proxy.
    request = Request(
        url, method="GET",
        headers={"Accept": "application/json", "Cache-Control": "no-store"})
    try:
        with build_opener(ProxyHandler({}), _NoRedirect()).open(
                request, timeout=timeout) as response:
            if (response.status != 200 or
                    response.headers.get_content_type() != "application/json"):
                raise TorrServerProbeBlocked("P3_FFP_BAD_RESPONSE")
            length = response.headers.get("Content-Length")
            if length is not None and (not length.isdecimal()
                                       or int(length) > _MAX_BYTES):
                raise TorrServerProbeBlocked("P3_FFP_RESPONSE_OVERSIZE")
            body = response.read(_MAX_BYTES + 1)
            if len(body) > _MAX_BYTES:
                raise TorrServerProbeBlocked("P3_FFP_RESPONSE_OVERSIZE")
            return body
    except (HTTPError, URLError, OSError, TimeoutError):
        raise TorrServerProbeBlocked("P3_FFP_LOCAL_READ_UNAVAILABLE") from None


def _vi_embedded_track_state(raw: bytes) -> str:
    """ABSENT only for an actual parsed VIDEO stream + interpretable tracks."""
    if not isinstance(raw, bytes) or not 0 < len(raw) <= _MAX_BYTES:
        return "UNKNOWN"
    try:
        obj = json.loads(raw.decode("utf-8", "strict"))
    except (UnicodeError, ValueError, TypeError, RecursionError):
        return "UNKNOWN"
    if not isinstance(obj, dict):
        return "UNKNOWN"
    tracks = obj.get("streams")
    if (not isinstance(tracks, list)
            or len(tracks) < 1 or len(tracks) > 128):
        return "UNKNOWN"
    saw_video = False
    unknown_subtitle = False
    found_vi = False
    for stream in tracks:
        if not isinstance(stream, dict):
            return "UNKNOWN"
        kind = stream.get("codec_type")
        if not isinstance(kind, str) or kind not in _VALID_TYPES:
            return "UNKNOWN"
        if kind == "video":
            saw_video = True
        if kind != "subtitle":
            continue
        tags = stream.get("tags")
        if not isinstance(tags, dict):
            unknown_subtitle = True
            continue
        lang = tags.get("language")
        if not isinstance(lang, str):
            unknown_subtitle = True
            continue
        lang = lang.strip().lower().replace("_", "-")
        if lang in _VI or lang.startswith("vi-"):
            found_vi = True
        elif lang not in _KNOWN_OTHER or lang == "und":
            unknown_subtitle = True
    if found_vi:
        return "PRESENT"
    if saw_video and not unknown_subtitle:
        return "ABSENT"
    return "UNKNOWN"


class TorrServerFfpTrackReader:
    """Bounded exact-localhost OMP probe; never trusts request-supplied URLs."""

    def __init__(self, torrserver: OwnerTorrServerReader, *,
                 transport: Callable[[str, float], bytes] = _read_local_ffp):
        if not isinstance(torrserver, OwnerTorrServerReader) or not callable(transport):
            raise TorrServerProbeBlocked("P3_FFP_READER_INVALID")
        self._ts = torrserver
        self._transport = transport

    def __call__(self, profile: str, torrent_hash: str, file_index: int) -> str:
        if (profile != self._ts.profile_id or
                not isinstance(torrent_hash, str) or
                _HASH.fullmatch(torrent_hash) is None or
                type(file_index) is not int or
                not 0 <= file_index < 4096):
            return "UNKNOWN"
        port = self._ts._config.localhost_port
        url = ("http://127.0.0.1:" + str(port) +
               "/ffp/" + torrent_hash + "/" + str(file_index))
        try:
            raw = self._transport(url, 3.0)
        except Exception:
            return "UNKNOWN"
        return _vi_embedded_track_state(raw)
