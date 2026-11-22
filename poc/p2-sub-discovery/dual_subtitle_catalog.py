"""Owner-private, source-separated EN→AI and downloaded-VI receipts.

No provider, translator, P4 listener or TV effects. This additive V2 cache
does not mutate the legacy .auto-source-<fingerprint>.json pointer while an
older installed Owner may still be serving it.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re

from matcher import Media
from opensubtitles import Asset, SubtitleApiError, validate_timed_text


_HEX = re.compile(r"[0-9a-f]{64}\Z")
_SRT = re.compile(r"[0-9a-f]{64}\.srt\Z")
_SCHEMA = "TTV-DUAL-SOURCE-V1"
_KIND_LANGUAGE = {"ai_en": "en", "downloaded_vi": "vi"}


@dataclass(frozen=True)
class SourceReceipt:
    kind: str
    file: Path
    sha256: str
    cues: int
    release_matched: bool


class DualSubtitleCatalog:
    def __init__(self, root: Path):
        if (not isinstance(root, Path) or not root.is_absolute()
                or root.is_symlink()):
            raise SubtitleApiError("DUAL_CACHE_ROOT_INVALID")
        self.root = root

    @staticmethod
    def _verify_binding(media: Media, fingerprint: str) -> None:
        if not isinstance(media, Media) or not isinstance(fingerprint, str) or not _HEX.fullmatch(fingerprint):
            raise SubtitleApiError("DUAL_MEDIA_ID_INVALID")
        expected = hashlib.sha256("\x00".join((
            media.server_profile_id, media.torrent_hash.lower(),
            str(media.file_index))).encode("utf-8")).hexdigest()
        if fingerprint != expected:
            raise SubtitleApiError("DUAL_MEDIA_BINDING_MISMATCH")

    def _index(self, fingerprint: str, kind: str) -> Path:
        return self.root / (".dual-source-" + fingerprint + "-" + kind + ".json")

    def _file(self, row: dict, kind: str) -> SourceReceipt:
        if (not isinstance(row, dict)
                or set(row) != {"schema", "kind", "file", "language", "sha256", "cues", "release_matched"}
                or row["schema"] != _SCHEMA or row["kind"] != kind
                or row["language"] != _KIND_LANGUAGE[kind]
                or not isinstance(row["file"], str) or not _SRT.fullmatch(row["file"])
                or not isinstance(row["sha256"], str) or not _HEX.fullmatch(row["sha256"])
                or type(row["cues"]) is not int or row["cues"] < 1
                or type(row["release_matched"]) is not bool):
            raise SubtitleApiError("DUAL_SOURCE_INDEX_INVALID")
        file = self.root / row["file"]
        if file.is_symlink() or not file.is_file() or not 0 < file.stat().st_size <= 256 * 1024:
            raise SubtitleApiError("DUAL_SOURCE_FILE_INVALID")
        try:
            raw = file.read_bytes()
        except OSError:
            raise SubtitleApiError("DUAL_SOURCE_FILE_UNREADABLE") from None
        if (hashlib.sha256(raw).hexdigest() != row["sha256"]
                or validate_timed_text(raw, "srt") != row["cues"]):
            raise SubtitleApiError("DUAL_SOURCE_CONTENT_CHANGED")
        return SourceReceipt(kind, file, row["sha256"], row["cues"], row["release_matched"])

    def read(self, media: Media, fingerprint: str, kind: str) -> SourceReceipt | None:
        self._verify_binding(media, fingerprint)
        if kind not in _KIND_LANGUAGE:
            raise SubtitleApiError("DUAL_SOURCE_KIND_INVALID")
        index = self._index(fingerprint, kind)
        if not index.exists() and not index.is_symlink():
            return None
        if index.is_symlink() or not index.is_file() or not 0 < index.stat().st_size <= 512:
            raise SubtitleApiError("DUAL_SOURCE_INDEX_INVALID")
        try:
            row = json.loads(index.read_text("utf-8"))
        except (OSError, UnicodeError, ValueError):
            raise SubtitleApiError("DUAL_SOURCE_INDEX_INVALID") from None
        return self._file(row, kind)

    def record(self, media: Media, fingerprint: str, kind: str,
               asset: Asset, file: Path, *, release_matched: bool) -> SourceReceipt:
        self._verify_binding(media, fingerprint)
        if kind not in _KIND_LANGUAGE or type(release_matched) is not bool:
            raise SubtitleApiError("DUAL_SOURCE_KIND_INVALID")
        if (not isinstance(asset, Asset) or asset.language != _KIND_LANGUAGE[kind]
                or asset.fmt != "srt" or not isinstance(file, Path)
                or not file.is_absolute() or file.parent != self.root
                or not _SRT.fullmatch(file.name)):
            raise SubtitleApiError("DUAL_SOURCE_FILE_INVALID")
        if (asset.sha256 != hashlib.sha256(asset.contents).hexdigest()
                or asset.cues != validate_timed_text(asset.contents, "srt")):
            raise SubtitleApiError("DUAL_SOURCE_CONTENT_CHANGED")
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        row = {"schema": _SCHEMA, "kind": kind, "file": file.name,
               "language": asset.language, "sha256": asset.sha256,
               "cues": asset.cues, "release_matched": release_matched}
        # Verify a caller-supplied file before writing a trusted index.
        receipt = self._file(row, kind)
        index = self._index(fingerprint, kind)
        raw = json.dumps(row, separators=(",", ":"), sort_keys=True).encode()
        try:
            fd = os.open(index, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            existing = self.read(media, fingerprint, kind)
            if existing != receipt:
                raise SubtitleApiError("DUAL_SOURCE_INDEX_CONFLICT")
            return existing
        with os.fdopen(fd, "wb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        return receipt

    def import_legacy(self, media: Media, fingerprint: str) -> SourceReceipt | None:
        """Non-destructive import of one verified legacy VI/EN source index."""
        self._verify_binding(media, fingerprint)
        old = self.root / (".auto-source-" + fingerprint + ".json")
        if not old.exists() and not old.is_symlink():
            return None
        if old.is_symlink() or not old.is_file() or not 0 < old.stat().st_size <= 512:
            raise SubtitleApiError("DUAL_LEGACY_INDEX_INVALID")
        try:
            row = json.loads(old.read_text("utf-8"))
        except (OSError, UnicodeError, ValueError):
            raise SubtitleApiError("DUAL_LEGACY_INDEX_INVALID") from None
        if (not isinstance(row, dict)
                or set(row) != {"schema", "file", "language", "sha256", "cues"}
                or row["schema"] != "TTV-LOCAL-AUTO-SOURCE-V1"
                or row["language"] not in ("en", "vi")
                or not isinstance(row["file"], str) or not _SRT.fullmatch(row["file"])
                or not isinstance(row["sha256"], str) or not _HEX.fullmatch(row["sha256"])
                or type(row["cues"]) is not int or row["cues"] < 1):
            raise SubtitleApiError("DUAL_LEGACY_INDEX_INVALID")
        kind = "ai_en" if row["language"] == "en" else "downloaded_vi"
        receipt = self._file({**row, "schema": _SCHEMA, "kind": kind,
                              "release_matched": False}, kind)
        raw = receipt.file.read_bytes()
        asset = Asset(0, row["language"], "srt", raw, row["sha256"], row["cues"])
        return self.record(media, fingerprint, kind, asset, receipt.file,
                           release_matched=False)
