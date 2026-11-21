"""Canonical P3 selected Media -> existing G1/P4 native media key.

Keep this in one place; V3 source_fingerprint and P4 mediaKey are DISTINCT
formats and MUST NOT be confused, even for the same selected torrent file.

Source: poc/g1-prod/P1ProductionSubtitles.kt::mediaKey()
sha256(b"prod\\0" + server_profile_id + b"\\0" + infohash + b"\\0" + index).

No network, provider calls or TV writes. A computed key does NOT grant
permission to activate P4: native selected engine must be VLC, paired, ON,
and independently current, while D3/P4 check session/media at delivery.
"""
from __future__ import annotations

import hashlib
import re

from matcher import Media

_PROFILE = re.compile(r"[A-Za-z0-9_-]{1,80}\Z")
_HASH_40 = re.compile(r"[0-9a-f]{40}\Z")


class P4MediaKeyError(ValueError):
    """Safe identity gate, without real media name/hash in error."""


def p4_media_key(media: Media, *, vlc_selected: bool) -> str:
    """Translate EXACT verified V3 coordinates to P4's existing native key."""
    if (not isinstance(media, Media)
            or vlc_selected is not True
            or not isinstance(media.server_profile_id, str)
            or _PROFILE.fullmatch(media.server_profile_id) is None
            or not isinstance(media.torrent_hash, str)
            or _HASH_40.fullmatch(media.torrent_hash) is None
            or type(media.file_index) is not int or media.file_index < 0):
        raise P4MediaKeyError("P4_MEDIA_IDENTITY_NOT_READY")
    canonical = ("prod\0" + media.server_profile_id + "\0" +
                 media.torrent_hash + "\0" +
                 str(media.file_index)).encode("utf-8")
    return "media." + hashlib.sha256(canonical).hexdigest()
