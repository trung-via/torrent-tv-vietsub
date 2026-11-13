"""Private, exact-media EN source handoff for the existing P2/P4 gateway.

The local owner/discovery workflow supplies a checked media -> file mapping.
This module does NOT discover subtitles, infer a film match, call a provider,
start a LAN service, or accept sources sent from the TV over the network.

The JSON manifest and subtitle bytes remain owner-local and off PUBLIC GitHub.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from assumed_source_handoff import AssumedEnglishSubtitle, MAX_SOURCE_BYTES

_MEDIA = re.compile(r"media\.[0-9a-f]{64}\Z")
_SHA = re.compile(r"[0-9a-f]{64}\Z")
_SCHEMA = "TTV-P2-OWNER-MATCHED-EN-V1"
_MAX_MANIFEST_BYTES = 64 * 1024


def verified_source_from_manifest(manifest: Path, media_key: str
                                  ) -> AssumedEnglishSubtitle:
    """Resolve ONE exact key only AFTER P4 HMAC authentication.

    This is a local-owner assertion of source matching, not a proof of
    OpenSubtitles API success or automatic release matching. The trusted D3
    producer must create this manifest after its own media-match acceptance.
    """
    if not isinstance(media_key, str) or not _MEDIA.fullmatch(media_key):
        raise ValueError("P2_MATCHED_MEDIA_ID_INVALID")
    if not isinstance(manifest, Path) or not manifest.is_absolute() or (
        not manifest.is_file() or manifest.is_symlink()
    ):
        raise ValueError("P2_MATCHED_OWNER_MANIFEST_REQUIRED")
    if manifest.stat().st_size not in range(1, _MAX_MANIFEST_BYTES + 1):
        raise ValueError("P2_MATCHED_MANIFEST_SIZE_INVALID")
    try:
        raw = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError):
        raise ValueError("P2_MATCHED_MANIFEST_INVALID") from None
    if (not isinstance(raw, dict) or set(raw) != {"schema", "sources"} or
        raw["schema"] != _SCHEMA or not isinstance(raw["sources"], list) or
        not 1 <= len(raw["sources"]) <= 32):
        raise ValueError("P2_MATCHED_MANIFEST_SCHEMA_INVALID")
    selected = None
    seen = set()
    for row in raw["sources"]:
        if (not isinstance(row, dict) or set(row) != {
            "media_key", "format", "source_path", "source_sha256", "owner_confirmed_match"
        }):
            raise ValueError("P2_MATCHED_MANIFEST_ROW_INVALID")
        key, fmt, path, sha, approved = (
            row["media_key"], row["format"], row["source_path"],
            row["source_sha256"], row["owner_confirmed_match"])
        if (not isinstance(key, str) or not _MEDIA.fullmatch(key) or
            key in seen or fmt not in ("srt", "vtt") or
            not isinstance(path, str) or not path or
            not isinstance(sha, str) or not _SHA.fullmatch(sha) or
            approved is not True):
            raise ValueError("P2_MATCHED_MANIFEST_ROW_INVALID")
        seen.add(key)
        if key == media_key:
            selected = (fmt, path, sha)
    if selected is None:
        raise ValueError("P2_MATCHED_EN_SOURCE_NOT_FOUND")
    fmt, path, expected_sha = selected
    file = Path(path)
    if (not file.is_absolute() or file.is_symlink() or
        not file.is_file() or file.suffix.lower() != "." + fmt):
        raise ValueError("P2_MATCHED_EN_LOCAL_FILE_REQUIRED")
    if file.stat().st_size not in range(1, MAX_SOURCE_BYTES + 1):
        raise ValueError("P2_MATCHED_EN_SOURCE_SIZE_INVALID")
    data = file.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected_sha:
        raise ValueError("P2_MATCHED_EN_SOURCE_HASH_MISMATCH")
    return AssumedEnglishSubtitle.from_supplied(
        media_key=media_key, fmt=fmt, source_bytes=data)
