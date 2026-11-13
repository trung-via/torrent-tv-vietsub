"""D3-EN owner-private handoff: confident EN D2 asset -> EXISTING P2 manifest.

Pure validation plus one explicit, fail-closed private manifest write. It does
NOT authenticate a TV, inspect TorrServer, assert real subtitle sync, call an
OpenSubtitles/Gemini API, or start LAN/ADB/Windows services. The trusted owner
caller must obtain independent evidence before constructing OwnerBinding.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

from matcher import Media
from opensubtitles import Asset, SubtitleApiError, validate_timed_text
from vi_en_fallback import Route


_MEDIA_RX = re.compile(r"media\.[0-9a-f]{64}\Z")
_SHA_RX = re.compile(r"[0-9a-f]{64}\Z")
_SCHEMA = "TTV-P2-OWNER-MATCHED-EN-V1"
_MAX_BYTES = 256 * 1024
_MANIFEST_NAME = "verified-en-manifest.json"


@dataclass(frozen=True)
class OwnerBinding:
    """Trusted-caller attestations; flags are NOT cryptographic proof.

    The caller must independently reconcile the authenticated active OMP
    media key to an actual selected TorrServer file and confirmed subtitle
    timing. Never populate this from D1 filenames or synthetic trial IDs.
    """

    p4_media_key: str
    d1_media_identity: tuple[str, str, int]
    p4_hmac_observed: bool
    torrserver_file_observed: bool
    owner_confirmed_release_and_sync: bool


def _respects_vi_precedence(route: Route) -> bool:
    """D3 must respect the discovery policy, not reinterpret one VI page.

    Under VI_FAST an incomplete VI page may have a provisional VI_MATCH,
    but is *not* authoritative: a later VI page could reveal ambiguity.
    Thus a correctly selected confident EN is permitted for that policy.
    EN_DIRECT intentionally skips online VI; VI_FULL stays exhaustive.
    These are routing consistency checks, not real-media trust evidence.
    """
    if route.reason != "CONFIDENT_EN_RELEASE" or route.language != "en":
        return False
    policy = route.search_policy
    state = route.vi_probe_status
    if policy == "EN_DIRECT":
        return (state == "SKIPPED"
                and not route.vi.candidates
                and not route.vi.decision.ranked)
    if policy == "VI_FAST":
        if state == "INCOMPLETE":
            return True
        if state == "NETWORK_ERROR_FALLBACK":
            return not route.vi.candidates and not route.vi.decision.ranked
        return state == "COMPLETE" and route.vi.decision.status != "VI_MATCH"
    if policy == "VI_FULL":
        return state == "COMPLETE" and route.vi.decision.status != "VI_MATCH"
    return False


def stage_confirmed_en_manifest(*, media: Media, route: Route, asset: Asset,
                                cached_file: Path, private_root: Path,
                                binding: OwnerBinding) -> Path:
    """Create P2's existing EN-only JSON manifest, once, with no overwrite.

    No automatic provider upload: #118 separately requires owner-local
    cloud authorization, a configured private profile and GEMINI_API_KEY.
    """
    if not isinstance(media, Media) or not isinstance(binding, OwnerBinding):
        raise SubtitleApiError("D3_OWNER_BINDING_REQUIRED")
    if (media.server_profile_id.startswith("owner-fallback-unverified") or
        not isinstance(binding.p4_media_key, str) or
        not _MEDIA_RX.fullmatch(binding.p4_media_key) or
        binding.d1_media_identity != media.key or
        binding.p4_hmac_observed is not True or
        binding.torrserver_file_observed is not True or
        binding.owner_confirmed_release_and_sync is not True):
        raise SubtitleApiError("D3_VERIFIED_MEDIA_AND_OWNER_REVIEW_REQUIRED")

    if (not isinstance(route, Route) or route.status != "EN_TRANSLATE" or
        route.language != "en" or type(route.selected_file_id) is not int or
        route.selected_file_id <= 0 or
        route.vi.media_key != media.key or
        route.vi.results.media_key != media.key or
        not _respects_vi_precedence(route) or
        route.en is None or route.en.media_key != media.key or
        route.en.results.media_key != media.key or
        route.en.decision.status != "EN_TRANSLATE" or
        route.en.decision.winner is None or
        route.en.decision.winner.subtitle_id != str(route.selected_file_id) or
        route.en.decision.winner.confident is not True or
        len([c for c in route.en.candidates
             if c.file_id == route.selected_file_id
             and c.subtitle.language == "en"]) != 1):
        raise SubtitleApiError("D3_CONFIDENT_EN_SELECTION_REQUIRED")

    if (not isinstance(asset, Asset) or asset.file_id != route.selected_file_id
        or asset.language != "en" or asset.fmt != "srt" or
        not isinstance(asset.contents, bytes) or
        not 0 < len(asset.contents) <= _MAX_BYTES or
        not isinstance(asset.sha256, str) or
        not _SHA_RX.fullmatch(asset.sha256) or
        hashlib.sha256(asset.contents).hexdigest() != asset.sha256 or
        type(asset.cues) is not int or asset.cues < 1 or
        validate_timed_text(asset.contents, "srt") != asset.cues):
        raise SubtitleApiError("D3_EN_ASSET_INVALID")

    if (not isinstance(private_root, Path) or not private_root.is_absolute()
        or private_root.is_symlink() or not private_root.is_dir() or
        not isinstance(cached_file, Path) or not cached_file.is_absolute()
        or cached_file.is_symlink() or not cached_file.is_file() or
        cached_file.suffix.lower() != ".srt"):
        raise SubtitleApiError("D3_PRIVATE_CACHE_REQUIRED")
    try:
        root = private_root.resolve(strict=True)
        file = cached_file.resolve(strict=True)
        if not file.is_relative_to(root) or file.read_bytes() != asset.contents:
            raise SubtitleApiError("D3_PRIVATE_CACHE_SOURCE_MISMATCH")
    except (OSError, ValueError) as exc:
        raise SubtitleApiError("D3_PRIVATE_CACHE_SOURCE_MISMATCH") from None

    target = root / _MANIFEST_NAME
    if target.exists() or target.is_symlink():
        raise SubtitleApiError("D3_MANIFEST_EXISTS_REVIEW_REQUIRED")
    body = json.dumps({
        "schema": _SCHEMA,
        "sources": [{
            "media_key": binding.p4_media_key,
            "format": "srt",
            "source_path": str(file),
            "source_sha256": asset.sha256,
            "owner_confirmed_match": True,
        }],
    }, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    if len(body) > 64 * 1024:
        raise SubtitleApiError("D3_MANIFEST_TOO_LARGE")

    # Atomic creation WITHOUT clobbering an existing source manifest.
    # Hard-linking a complete private temp is supported on standard NTFS and
    # ensures an existing target cannot be silently replaced.
    tmp = None
    try:
        fd, name = tempfile.mkstemp(prefix=".d3-manifest-", dir=root)
        tmp = Path(name)
        with os.fdopen(fd, "wb") as output:
            os.fchmod(output.fileno(), 0o600) if hasattr(os, "fchmod") else None
            output.write(body)
            output.flush()
            os.fsync(output.fileno())
        os.link(tmp, target)
        return target
    except (OSError, FileExistsError):
        raise SubtitleApiError("D3_PRIVATE_MANIFEST_WRITE_FAILED") from None
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)
