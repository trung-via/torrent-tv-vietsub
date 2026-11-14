"""Exact owner-local media authorization for the real P3/P4 composition.

The policy must be enrolled by the logged-in owner in OwnerBridge (NOT GitHub).
No broad search, guessed permission, title-only match, trust in TV-supplied
filenames, assumed 'ABSENT' VI tracks, or provider call is permitted.

Only exact owner-pinned LOCAL, complete media with matching TorrServer file
metadata can produce a positive rights answer. The VI inventory uses ffprobe
on that exact LOCAL file; unavailable/ambiguous tracks return UNKNOWN (HOLD).
"""
from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
from typing import Callable

from owner_selected_file_resolver import OwnerPinnedFiles, _one_basename
from owner_torrserver_readonly import OwnerTorrServerReader

_SHA40_OR_64 = re.compile(r"(?:[a-f0-9]{40}|[a-f0-9]{64})\Z")
_PROFILE = re.compile(r"[A-Za-z0-9_-]{1,80}\Z")
_LANG_VI = frozenset(("vi", "vie", "vn", "vietnamese"))
_OTHER_OK = frozenset(("en", "eng", "english", "fr", "fra", "fre", "es",
                      "spa", "de", "deu", "ger", "ja", "jpn", "ko", "kor",
                      "zh", "zho", "chi", "pt", "por", "ru", "rus"))
_VI_SIDECARS = (".vi.srt", ".vie.srt", ".vietnamese.srt",
                ".vi.vtt", ".vie.vtt", ".vietnamese.vtt")


class OwnerPolicyBlocked(ValueError):
    """Non-sensitive error code: never report titles/paths from private policy."""


@dataclass(frozen=True)
class PrivateMediaPin:
    torrent_hash: str
    file_index: int
    torrserver_path: str
    video_path: Path
    rights_approved: bool


def _inside(path: Path, root: Path) -> bool:
    try:
        resolved_root = root.resolve(strict=True)
        resolved = path.resolve(strict=True)
        if (".." in path.parts or path.is_symlink()
                or not resolved.is_relative_to(resolved_root)):
            return False
        current = path
        for _ in range(len(path.parts) + 1):
            if current.is_symlink():
                return False
            if current == resolved_root:
                return True
            parent = current.parent
            if parent == current:
                break
            current = parent
        return False
    except (ValueError, RuntimeError, OSError):
        return False


def _probe_subtitle_languages(path: Path) -> str:
    """Only an independent ffprobe inspection can establish owner-local tracks."""
    try:
        result = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "stream=codec_type:stream_tags=language",
             "-of", "json", str(path)],
            capture_output=True, timeout=12, check=False)
        if result.returncode != 0 or len(result.stdout) > 65536:
            return "UNKNOWN"
        parsed = json.loads(result.stdout.decode("utf-8", "strict"))
        tracks = parsed.get("streams")
        if not isinstance(tracks, list) or len(tracks) > 128:
            return "UNKNOWN"
        for item in tracks:
            if not isinstance(item, dict):
                return "UNKNOWN"
            if item.get("codec_type") != "subtitle":
                continue
            tags = item.get("tags", {})
            if not isinstance(tags, dict):
                return "UNKNOWN"
            lang = tags.get("language", "")
            if not isinstance(lang, str) or not lang.strip():
                return "UNKNOWN"
            lang = lang.lower().strip()
            if lang in _LANG_VI or lang.startswith("vi-"):
                return "PRESENT"
            if lang not in _OTHER_OK:
                return "UNKNOWN"
        return "ABSENT"
    except (OSError, subprocess.TimeoutExpired, UnicodeError, ValueError,
            TypeError, RecursionError):
        return "UNKNOWN"


class PrivateP3P4Policy:
    """Owner-private explicit allowlist + independent exact-file checks."""

    def __init__(self, *, manifest: Path, owner_root: Path,
                 private_media_root: Path, torrserver: OwnerTorrServerReader,
                 probe: Callable[[Path], str] = _probe_subtitle_languages):
        if (not isinstance(owner_root, Path) or not owner_root.is_absolute()
                or not owner_root.is_dir()
                or not isinstance(manifest, Path)
                or not manifest.is_absolute()
                or not manifest.is_file() or manifest.is_symlink()
                or not _inside(manifest, owner_root)
                or manifest.stat().st_size > 32768
                or not isinstance(private_media_root, Path)
                or not private_media_root.is_absolute()
                or not private_media_root.is_dir()
                or private_media_root.is_symlink()
                or not isinstance(torrserver, OwnerTorrServerReader)
                or not callable(probe)):
            raise OwnerPolicyBlocked("OWNER_POLICY_PRIVATE_CONFIG_REQUIRED")
        try:
            config = json.loads(manifest.read_text(encoding="utf-8"))
        except (UnicodeError, ValueError, OSError):
            raise OwnerPolicyBlocked("OWNER_POLICY_JSON_INVALID") from None
        if (not isinstance(config, dict)
                or set(config) != {"schema", "enabled", "profile_id", "torrserver_port", "private_media_root", "media"}
                or config["schema"] != "TTV-P3-P4-OWNER-POLICY-V1"
                or type(config["enabled"]) is not bool
                or not isinstance(config["profile_id"], str)
                or not _PROFILE.fullmatch(config["profile_id"])
                or config["profile_id"] != torrserver.profile_id
                or type(config["torrserver_port"]) is not int
                or not 1024 <= config["torrserver_port"] <= 65535
                or config["torrserver_port"] != torrserver._config.localhost_port
                or not isinstance(config["private_media_root"], str)
                or Path(config["private_media_root"]).resolve(strict=False)
                   != private_media_root.resolve(strict=True)
                or not isinstance(config["media"], list)
                or len(config["media"]) > 32):
            raise OwnerPolicyBlocked("OWNER_POLICY_SCHEMA_INVALID")
        pins = {}
        for item in config["media"]:
            if (not isinstance(item, dict)
                    or set(item) != {"torrent_hash", "file_index",
                                    "torrserver_path", "video_path",
                                    "rights_approved"}
                    or not isinstance(item["torrent_hash"], str)
                    or not _SHA40_OR_64.fullmatch(item["torrent_hash"])
                    or type(item["file_index"]) is not int
                    or not 0 <= item["file_index"] < 4096
                    or not isinstance(item["torrserver_path"], str)
                    or not isinstance(item["video_path"], str)
                    or type(item["rights_approved"]) is not bool):
                raise OwnerPolicyBlocked("OWNER_POLICY_MEDIA_ENTRY_INVALID")
            try:
                name = _one_basename(item["torrserver_path"])
                path = Path(item["video_path"])
            except (ValueError, TypeError):
                raise OwnerPolicyBlocked("OWNER_POLICY_MEDIA_PATH_INVALID") from None
            if (not path.is_absolute() or path.name != name
                    or path.suffix.lower() not in (".mkv", ".mp4", ".m4v", ".webm")
                    or not _inside(path, private_media_root)
                    or not path.is_file()):
                raise OwnerPolicyBlocked("OWNER_POLICY_LOCAL_VIDEO_NOT_PINNED")
            key = (item["torrent_hash"], item["file_index"])
            if key in pins:
                raise OwnerPolicyBlocked("OWNER_POLICY_DUPLICATE_MEDIA")
            pins[key] = PrivateMediaPin(
                item["torrent_hash"], item["file_index"],
                item["torrserver_path"], path, item["rights_approved"])
        self._enabled = config["enabled"]
        self._profile = torrserver.profile_id
        self._ts = torrserver
        self._root = private_media_root
        self._pins = pins
        self._probe = probe

    def owner_auto_allowed(self) -> bool:
        return self._enabled is True

    def _verified_pin(self, profile: str, infohash: str, index: int,
                      torrent_path: str | None = None) -> PrivateMediaPin | None:
        if not self._enabled or profile != self._profile:
            return None
        pin = self._pins.get((infohash, index))
        if pin is None or pin.rights_approved is not True:
            return None
        try:
            selected = self._ts(profile, infohash, index)
            if (selected.path != pin.torrserver_path
                    or (torrent_path is not None and torrent_path != selected.path)
                    or _one_basename(selected.path) != pin.video_path.name
                    or not _inside(pin.video_path, self._root)
                    or not pin.video_path.is_file()
                    or pin.video_path.stat().st_size != selected.length):
                return None
        except (OSError, ValueError, TypeError, RuntimeError):
            return None
        return pin

    def media_rights_allowed(self, profile: str, infohash: str, index: int) -> bool:
        return self._verified_pin(profile, infohash, index) is not None

    def verified_local_vi_state(self, profile: str, infohash: str, index: int) -> str:
        pin = self._verified_pin(profile, infohash, index)
        if pin is None:
            return "UNKNOWN"
        stem = pin.video_path.stem
        for suffix in _VI_SIDECARS:
            candidate = pin.video_path.parent / (stem + suffix)
            if candidate.is_symlink():
                return "UNKNOWN"
            if candidate.is_file():
                return "PRESENT"
        outcome = self._probe(pin.video_path)
        return outcome if outcome in ("PRESENT", "ABSENT") else "UNKNOWN"

    def locate_owner_pinned_files(
        self, profile: str, infohash: str, index: int, torrent_path: str
    ) -> OwnerPinnedFiles | None:
        pin = self._verified_pin(profile, infohash, index, torrent_path)
        if pin is None:
            return None
        return OwnerPinnedFiles(video_path=pin.video_path,
                                english_sidecar_path=None,
                                video_file_complete=True)
