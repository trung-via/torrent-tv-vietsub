"""Direct owner-private cached EN SRT -> existing P2 LEAN120 worker.

This is the *translation-only* path. It does NOT assert real TorrServer/OMP
media identity or create a P4 manifest. It does not search, download, copy,
upload, start a service, or contact any model unless run_local_translation()
is explicitly called with consent and a configured existing worker.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import re
from typing import Protocol

from assumed_source_handoff import AssumedEnglishSubtitle, MAX_SOURCE_BYTES
from automatic_lean120_worker import AutomaticLean120Worker
from lean120_api import _https_post
from progressive_handoff import SubtitleRevision

_SHA = re.compile(r"[0-9a-f]{64}\Z")
_LOCAL_SCOPE = b"TTV-P2-LOCAL-TRANSLATION-ONLY-V1\x00"


@dataclass(frozen=True)
class CachedEnReceipt:
    """In-memory D2->P2 contract, NOT a TV-approved source registry.

    The D2 client supplies exactly these values from its successful one-POST
    QA result; for an already-downloaded file the owner may supply them from
    the existing local receipt without repeating OpenSubtitles requests.
    """
    cache_file: Path
    source_sha256: str
    cue_count: int
    language: str = "en"


class _Worker(Protocol):
    def run(self, source: AssumedEnglishSubtitle, *,
            on_revision: object | None = None) -> SubtitleRevision: ...


def _read_cached_en(receipt: CachedEnReceipt, *, private_root: Path) -> bytes:
    if (not isinstance(receipt, CachedEnReceipt)
            or receipt.language != "en"
            or not isinstance(receipt.source_sha256, str)
            or not _SHA.fullmatch(receipt.source_sha256)
            or type(receipt.cue_count) is not int or receipt.cue_count < 1):
        raise ValueError("P2_CACHED_EN_RECEIPT_INVALID")
    file = receipt.cache_file
    root = private_root
    if (not isinstance(file, Path) or not file.is_absolute()
            or file.suffix.casefold() != ".srt" or file.is_symlink()
            or not isinstance(root, Path) or not root.is_absolute()
            or root.is_symlink() or not root.is_dir()):
        raise ValueError("P2_CACHED_EN_PRIVATE_FILE_REQUIRED")
    try:
        canonical_root = root.resolve(strict=True)
        canonical_file = file.resolve(strict=True)
        if not canonical_file.is_relative_to(canonical_root) or not canonical_file.is_file():
            raise ValueError("P2_CACHED_EN_OUTSIDE_PRIVATE_ROOT")
        size = canonical_file.stat().st_size
        if not 0 < size <= MAX_SOURCE_BYTES:
            raise ValueError("P2_CACHED_EN_SIZE_INVALID")
        contents = canonical_file.read_bytes()
    except OSError:
        raise ValueError("P2_CACHED_EN_READ_FAILED") from None
    if hashlib.sha256(contents).hexdigest() != receipt.source_sha256:
        raise ValueError("P2_CACHED_EN_SHA256_MISMATCH")
    return contents


def prepare_local_translation_source(
    receipt: CachedEnReceipt, *, private_root: Path,
) -> AssumedEnglishSubtitle:
    """Recheck existing cached bytes; create a local-only opaque job scope.

    This media.<digest> key is solely a P2 internal worker namespace. It is
    NOT the authenticated P4/OMP active media ID and must never be published
    or passed into a TV source manifest.
    """
    contents = _read_cached_en(receipt, private_root=private_root)
    media = "media." + hashlib.sha256(
        _LOCAL_SCOPE + receipt.source_sha256.encode("ascii")).hexdigest()
    source = AssumedEnglishSubtitle.from_supplied(
        media_key=media, fmt="srt", source_bytes=contents)
    if source.cue_count != receipt.cue_count:
        raise ValueError("P2_CACHED_EN_CUE_COUNT_MISMATCH")
    return source


def run_local_translation(
    receipt: CachedEnReceipt, *, private_root: Path,
    worker: _Worker, cloud_upload_authorized: bool = False,
    pilot_first_window: bool = False,
) -> SubtitleRevision:
    """ONE owner-authorized P2 run, with TV callback forced to None.

    Reuses P2's own batch/window/QA/checkpoint/uncertain API retry rules.
    No additional manifest, queue, daemon, file copy or P4 connection.
    In-process call is intentionally separate from the D2 downloader; the
    owner must authorize real cloud subtitle upload before execution.
    """
    if cloud_upload_authorized is not True:
        raise ValueError("P2_CLOUD_UPLOAD_AUTHORIZATION_REQUIRED")
    if (os.environ.get("CI", "").lower() == "true"
            or os.environ.get("GITHUB_ACTIONS", "").lower() == "true"):
        if (isinstance(worker, AutomaticLean120Worker)
                and worker.transport is _https_post):
            raise ValueError("P2_LIVE_PROVIDER_FORBIDDEN_IN_CI")
    if not callable(getattr(worker, "run", None)):
        raise ValueError("P2_LEAN120_WORKER_REQUIRED")
    if type(pilot_first_window) is not bool:
        raise ValueError("P2_PILOT_FLAG_INVALID")
    if pilot_first_window and not isinstance(worker, AutomaticLean120Worker):
        raise ValueError("P2_PILOT_REQUIRES_EXISTING_WORKER")
    source = prepare_local_translation_source(receipt, private_root=private_root)
    if pilot_first_window:
        return worker.run(source, on_revision=None, max_new_windows=1)
    return worker.run(source, on_revision=None)
