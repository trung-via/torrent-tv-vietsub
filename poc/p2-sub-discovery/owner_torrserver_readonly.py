"""Strict owner-LAPTOP-only read of the currently selected TorrServer file.

Source-pinned to OMP TorrServerClient.get(hash): POST /torrents
{"action":"get","hash":"..."}; OMP files() uses file_stats first, else
JSON data.TorrServer.Files. No add/rem/loadInfo/stream/ffprobe operations.

Safety: only explicit 127.0.0.1 high-port HTTP inside the owner Windows
process; never bind to a service, accept a host from the TV packet, follow
redirects, read media/subtitle bytes or print URL/auth/profile/hash.

The caller must separately verify TV pairing/current selection and owner
rights/ON, and bind the configured server profile id. Localhost metadata alone
does NOT authenticate the TV event or grant a cloud-subtitle download.
"""
from __future__ import annotations

from dataclasses import dataclass
import json
import re
from typing import Callable
from urllib.error import HTTPError, URLError
from urllib.request import (
    Request, build_opener, ProxyHandler, HTTPRedirectHandler,
)

from owner_selected_file_resolver import TorrServerSelectedFile

_HASH = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})\Z")
_PROFILE = re.compile(r"[A-Za-z0-9_-]{1,80}\Z")
_MAX_META_BYTES = 512 * 1024
_MAX_FILES = 4096


class OwnerTorrServerReadError(ValueError):
    """Sanitized reason code, no server URL or movie title."""


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _local_post(url: str, payload: bytes, timeout_sec: float) -> bytes:
    """Only POST to the explicitly configured localhost server."""
    request = Request(
        url, data=payload, method="POST",
        headers={"Content-Type": "application/json",
                 "Accept": "application/json",
                 "Cache-Control": "no-store"},
    )
    opener = build_opener(ProxyHandler({}), _NoRedirect())
    try:
        with opener.open(request, timeout=timeout_sec) as response:
            if (response.status != 200 or
                    response.headers.get_content_type() != "application/json"):
                raise OwnerTorrServerReadError("TS_GET_RESPONSE_INVALID")
            length = response.headers.get("Content-Length")
            if length is not None and (not length.isdecimal()
                                       or int(length) > _MAX_META_BYTES):
                raise OwnerTorrServerReadError("TS_METADATA_TOO_LARGE")
            data = response.read(_MAX_META_BYTES + 1)
            if len(data) > _MAX_META_BYTES:
                raise OwnerTorrServerReadError("TS_METADATA_TOO_LARGE")
            return data
    except (HTTPError, URLError, TimeoutError, OSError):
        raise OwnerTorrServerReadError("TS_GET_UNAVAILABLE") from None


@dataclass(frozen=True)
class OwnerLocalTorrServer:
    """One owner-pinned TV/TorrServer profile, never supplied by TV JSON."""

    profile_id: str
    localhost_port: int
    timeout_sec: float = 4.0

    def __post_init__(self):
        if (not isinstance(self.profile_id, str)
                or _PROFILE.fullmatch(self.profile_id) is None
                or type(self.localhost_port) is not int
                or not 1024 <= self.localhost_port <= 65535
                or type(self.timeout_sec) not in (float, int)
                or not 0.5 <= self.timeout_sec <= 8.0):
            raise OwnerTorrServerReadError("TS_OWNER_PROFILE_INVALID")

    @property
    def url(self) -> str:
        return "http://127.0.0.1:" + str(self.localhost_port) + "/torrents"


class OwnerTorrServerReader:
    """Exact file metadata only, suitable as read_verified_torrserver_file.

    This verifies configured owner profile + *server response* hash, but not
    the TV session itself. The VerifiedV3Processor remains responsible for
    independent trusted current-TV checks, viewer ON/rights, and re-check.
    """

    def __init__(self, config: OwnerLocalTorrServer, *,
                 transport: Callable[[str, bytes, float], bytes] = _local_post):
        if not isinstance(config, OwnerLocalTorrServer) or not callable(transport):
            raise OwnerTorrServerReadError("TS_OWNER_READER_INVALID")
        self._config = config
        self._transport = transport

    @property
    def profile_id(self) -> str:
        """Owner-pinned profile, not a value from the TV packet."""
        return self._config.profile_id


    def __call__(self, server_id: str, torrent_hash: str,
                 file_index: int) -> TorrServerSelectedFile:
        cfg = self._config
        if (server_id != cfg.profile_id
                or not isinstance(torrent_hash, str)
                or _HASH.fullmatch(torrent_hash) is None
                or type(file_index) is not int or not 0 <= file_index < _MAX_FILES):
            raise OwnerTorrServerReadError("TS_SELECTED_MEDIA_IDENTITY_INVALID")
        body = json.dumps(
            {"action": "get", "hash": torrent_hash},
            separators=(",", ":"), sort_keys=True).encode("ascii")
        try:
            data = self._transport(cfg.url, body, float(cfg.timeout_sec))
        except Exception:
            raise OwnerTorrServerReadError("TS_GET_UNAVAILABLE") from None
        if not isinstance(data, bytes) or not 0 < len(data) <= _MAX_META_BYTES:
            raise OwnerTorrServerReadError("TS_METADATA_SIZE_INVALID")
        try:
            torrent = json.loads(data.decode("utf-8", errors="strict"))
        except (UnicodeError, ValueError, RecursionError):
            raise OwnerTorrServerReadError("TS_METADATA_JSON_INVALID") from None
        if not isinstance(torrent, dict) or torrent.get("hash") != torrent_hash:
            raise OwnerTorrServerReadError("TS_METADATA_HASH_MISMATCH")
        files = torrent.get("file_stats")
        if not isinstance(files, list) or not files:
            data_field = torrent.get("data")
            if not isinstance(data_field, str) or len(data_field) > _MAX_META_BYTES:
                raise OwnerTorrServerReadError("TS_FILE_LIST_UNAVAILABLE")
            try:
                decoded = json.loads(data_field)
                files = decoded["TorrServer"]["Files"]
            except (ValueError, TypeError, KeyError, RecursionError):
                raise OwnerTorrServerReadError("TS_FILE_LIST_UNAVAILABLE") from None
        if not isinstance(files, list) or len(files) > _MAX_FILES:
            raise OwnerTorrServerReadError("TS_FILE_LIST_INVALID")
        selected = [
            f for f in files
            if (isinstance(f, dict) and type(f.get("id")) is int
                and f["id"] == file_index)
        ]
        if len(selected) != 1:
            raise OwnerTorrServerReadError("TS_SELECTED_FILE_NOT_UNIQUE")
        found = selected[0]
        if (not isinstance(found.get("path"), str)
                or not found["path"] or len(found["path"]) > 2048
                or type(found.get("length")) is not int
                or found["length"] < 1):
            raise OwnerTorrServerReadError("TS_SELECTED_FILE_FIELDS_INVALID")
        return TorrServerSelectedFile(
            id=file_index, path=found["path"], length=found["length"])
