"""P3 source-only exact OMP/TorrServer selected-file to owner-local EN binding.

Three injected, already-trusted owner-side readers are required. This module
DOES NOT authenticate the TV or TorrServer, poll or call their HTTP APIs,
register a Windows service, read GitHub payloads, run ffmpeg, or translate.
It turns a current playback + exact TorrServer file record + owner-pinned local
path into LocalMediaSelection for the existing #145 local EN route.

WARNING: proof booleans and injected callbacks are not cryptographic security.
The real source adapter must verify TV session, selected file, endpoint and
ownership BEFORE invoking this code. No self-issued attestation is accepted.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
import re
from typing import Callable

from local_en_direct import LocalMediaSelection, _inside_private_root, _exact_en_sidecar

_HASH = re.compile(r"(?:[a-f0-9]{40}|[a-f0-9]{64})\Z")
_TAG = re.compile(r"[a-zA-Z0-9_-]{1,128}\Z")
_FP = re.compile(r"[a-f0-9]{64}\Z")
_ALLOWED_PLAY = frozenset(("PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED"))
_VIDEO = frozenset((".mkv", ".mp4", ".m4v", ".webm"))
_EN_SUFFIXES = ("en.srt", "eng.srt", "english.srt",
                "en.vtt", "eng.vtt", "english.vtt")


class SelectedFileResolveError(ValueError):
    """Privacy-preserving reason code; no personal file path or torrent data."""


@dataclass(frozen=True)
class CurrentPlaying:
    # Produced ONLY by a trusted fresh TV session reader; no JSON endpoint.
    kind: str
    attested: bool
    active: bool
    server_id: str
    tv_session_id: str
    torrent_hash: str
    file_index: int
    video_name: str
    owner_auto_enabled: bool
    viewer_choice: str
    media_rights_approved: bool
    local_vi_state: str


@dataclass(frozen=True)
class TorrServerSelectedFile:
    # One exact file from an authenticated read-only /torrents get/list
    # metadata reply: OMP TorrentFile {id, path, length}. Not a local path.
    id: int
    path: str
    length: int


@dataclass(frozen=True)
class OwnerPinnedFiles:
    # Explicit owner-local map entry for THIS selected server/hash/index/file,
    # never guessed from title or selected from a broad recursive disk search.
    video_path: Path | None = None
    english_sidecar_path: Path | None = None
    video_file_complete: bool = False


def _fingerprint(server_id: str, infohash: str, file_index: int) -> str:
    """Must match #142 ActivationDeduplicator's local fingerprint exactly."""
    return hashlib.sha256(
        "\x00".join((server_id, infohash.lower(), str(file_index))).encode("utf-8")
    ).hexdigest()


def _one_basename(path: str) -> str:
    """Interpret only TorrServer's documented POSIX-style TorrentFile.path."""
    if (not isinstance(path, str) or not path or len(path) > 2048
            or "\\" in path or "\x00" in path
            or path.startswith(("/", "~"))
            or ":" in path
            or any(ord(c) < 32 or ord(c) == 127 for c in path)):
        raise SelectedFileResolveError("RESOLVER_SERVER_PATH_INVALID")
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        raise SelectedFileResolveError("RESOLVER_SERVER_PATH_INVALID")
    return parts[-1]


def _validated_snapshot(s: CurrentPlaying, requested_name: str,
                        source_fingerprint: str) -> None:
    if not isinstance(s, CurrentPlaying):
        raise SelectedFileResolveError("RESOLVER_TRUSTED_SNAPSHOT_REQUIRED")
    if (s.kind not in _ALLOWED_PLAY or s.attested is not True
            or s.active is not True):
        raise SelectedFileResolveError("RESOLVER_NOT_ACTIVE_AUTHENTICATED_PLAY")
    if (s.owner_auto_enabled is not True
            or s.media_rights_approved is not True
            or s.viewer_choice != "ON"
            or s.local_vi_state != "ABSENT"):
        raise SelectedFileResolveError("RESOLVER_OWNER_OR_VIEWER_GATE_BLOCKED")
    if (not isinstance(s.server_id, str) or _TAG.fullmatch(s.server_id) is None
            or not isinstance(s.tv_session_id, str)
            or _TAG.fullmatch(s.tv_session_id) is None
            or not isinstance(s.torrent_hash, str)
            or _HASH.fullmatch(s.torrent_hash.lower()) is None
            or type(s.file_index) is not int or s.file_index < 0
            or not isinstance(s.video_name, str)
            or len(s.video_name) > 255 or not s.video_name
            or "/" in s.video_name or "\\" in s.video_name
            or s.video_name.startswith(".")
            or any(ord(c) < 32 or ord(c) == 127 for c in s.video_name)
            or not isinstance(requested_name, str)
            or requested_name != s.video_name):
        raise SelectedFileResolveError("RESOLVER_SELECTED_MEDIA_MISMATCH")
    if (not isinstance(source_fingerprint, str)
            or _FP.fullmatch(source_fingerprint) is None
            or source_fingerprint != _fingerprint(
                s.server_id, s.torrent_hash, s.file_index)):
        raise SelectedFileResolveError("RESOLVER_SOURCE_FINGERPRINT_MISMATCH")


def _discover_exact_sidecar(video: Path, private_root: Path,
                            video_name: str) -> Path | None:
    stem = Path(video_name).stem
    hits = []
    for suffix in _EN_SUFFIXES:
        candidate = video.parent / (stem + "." + suffix)
        if candidate.is_symlink():
            raise SelectedFileResolveError("RESOLVER_SIDECAR_SYMLINK_REFUSED")
        if candidate.exists():
            path = _safe_local(candidate, private_root)
            if path.is_file():
                hits.append(path)
    if len(hits) > 1:
        raise SelectedFileResolveError("RESOLVER_AMBIGUOUS_LOCAL_EN")
    return hits[0] if hits else None


def _safe_local(path: Path, private_root: Path) -> Path:
    try:
        return _inside_private_root(path, private_root)
    except (ValueError, OSError, RuntimeError):
        raise SelectedFileResolveError("RESOLVER_UNTRUSTED_PRIVATE_PATH") from None


def resolve_selected_local_source(
    *, requested_name: str, source_fingerprint: str, private_media_root: Path,
    read_verified_current_playback: Callable[[], CurrentPlaying],
    read_verified_torrserver_file: Callable[[str, str, int], TorrServerSelectedFile],
    locate_owner_pinned_files: Callable[[str, str, int, str], OwnerPinnedFiles | None],
) -> LocalMediaSelection | None:
    """Read-only exact-identity handoff for an *already trusted* owner adapter.

    Return None if the selected torrent is only a stream and the owner has no
    local file/sidecar. In that case the caller may use the existing D2 path,
    but must preserve the event fingerprint across its private source cache.
    Identity/path/permission mismatches always HOLD, never fall through.
    """
    if (not callable(read_verified_current_playback)
            or not callable(read_verified_torrserver_file)
            or not callable(locate_owner_pinned_files)):
        raise SelectedFileResolveError("RESOLVER_REQUIRED_TRUSTED_READERS")
    if (not isinstance(private_media_root, Path) or
            not private_media_root.is_absolute() or
            private_media_root.is_symlink() or
            not private_media_root.is_dir()):
        raise SelectedFileResolveError("RESOLVER_OWNER_MEDIA_ROOT_INVALID")
    try:
        state = read_verified_current_playback()
    except Exception:
        raise SelectedFileResolveError("RESOLVER_PLAYBACK_READER_UNAVAILABLE") from None
    _validated_snapshot(state, requested_name, source_fingerprint)

    try:
        record = read_verified_torrserver_file(
            state.server_id, state.torrent_hash.lower(), state.file_index)
    except Exception:
        raise SelectedFileResolveError("RESOLVER_TORRSERVER_READER_UNAVAILABLE") from None
    if (not isinstance(record, TorrServerSelectedFile)
            or type(record.id) is not int
            or record.id != state.file_index
            or type(record.length) is not int or record.length < 1
            or _one_basename(record.path) != state.video_name):
        raise SelectedFileResolveError("RESOLVER_SERVER_FILE_MISMATCH")

    try:
        pinned = locate_owner_pinned_files(
            state.server_id, state.torrent_hash.lower(),
            state.file_index, record.path)
    except Exception:
        raise SelectedFileResolveError("RESOLVER_OWNER_MAPPING_UNAVAILABLE") from None
    if pinned is None:
        return None
    if not isinstance(pinned, OwnerPinnedFiles):
        raise SelectedFileResolveError("RESOLVER_OWNER_MAPPING_INVALID")
    if (pinned.video_path is None and pinned.english_sidecar_path is None):
        return None

    video = None
    if pinned.video_path is not None:
        video = _safe_local(pinned.video_path, private_media_root)
        if video.name != state.video_name or video.suffix.casefold() not in _VIDEO:
            raise SelectedFileResolveError("RESOLVER_LOCAL_VIDEO_NAME_MISMATCH")
        if pinned.video_file_complete is True:
            # Owner-supplied completeness flag is NOT enough by itself. Size
            # must also match this exact selected TorrServer metadata record.
            if video.stat().st_size != record.length:
                raise SelectedFileResolveError("RESOLVER_LOCAL_VIDEO_SIZE_MISMATCH")

    sidecar = None
    if pinned.english_sidecar_path is not None:
        sidecar = _safe_local(pinned.english_sidecar_path, private_media_root)
    elif video is not None:
        sidecar = _discover_exact_sidecar(video, private_media_root,
                                          state.video_name)
    if sidecar is not None:
        if video is not None and sidecar.parent != video.parent:
            raise SelectedFileResolveError("RESOLVER_SIDECAR_DIRECTORY_MISMATCH")
        source_check = LocalMediaSelection(
            attested=True, active=True, owner_authorized=True,
            viewer_choice="ON", local_vi_state="ABSENT",
            server_id=state.server_id, torrent_hash=state.torrent_hash.lower(),
            file_index=state.file_index, video_name=state.video_name,
            private_media_root=private_media_root,
        )
        try:
            _exact_en_sidecar(source_check, sidecar)
        except ValueError:
            raise SelectedFileResolveError("RESOLVER_SIDECAR_NAME_MISMATCH") from None
    if video is None and sidecar is None:
        return None
    return LocalMediaSelection(
        attested=True, active=True, owner_authorized=True,
        viewer_choice="ON", local_vi_state="ABSENT",
        server_id=state.server_id, torrent_hash=state.torrent_hash.lower(),
        file_index=state.file_index, video_name=state.video_name,
        private_media_root=private_media_root,
        video_path=video, en_sidecar_path=sidecar,
        video_file_complete=pinned.video_file_complete is True,
    )
