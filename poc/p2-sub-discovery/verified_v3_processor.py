"""Verified V3 OMP-selected media consumer for ONE existing owner-agent flow.

This is the typed composition of:
  - #142 P3 playback policy + #143 owner-private V3 event inbox,
  - #147 exact selected TorrServer file resolver, #145 LOCAL_EN_DIRECT,
  - existing #140 VI_FAST/OpenSubtitles and Gemini LEAN120 worker.

The input event's TV session/fingerprint are ONLY correlation keys.
A trusted caller-supplied owner TV reader MUST independently authenticate and
re-read current session/player state + exact TorrServer selected-file metadata
before provider calls. This module contains NO TV reader, network listener,
credentials, timer, disk crawler or actual device installation.
"""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
import re
from pathlib import Path
from typing import Callable

from matcher import Media, Release, preferred_media_release
from owner_selected_file_resolver import (
    CurrentPlaying, TorrServerSelectedFile, OwnerPinnedFiles,
    SelectedFileResolveError, resolve_selected_local_source, _fingerprint,
)
from local_en_direct import LocalMediaSelection
from owner_session_bridge import PreProviderTransient, owner_full_trace

try:
    # Newer Owner bridges supply the shared validator. The installed V2-R0
    # bridge predates that export; keep the six-file discovery upgrade
    # compatible without replacing a live session/queue implementation.
    from owner_session_bridge import _authorized_selection
except ImportError:
    def _authorized_selection(value: object, fingerprint: str | None,
                              session: str | None) -> dict[str, object]:
        """Same fail-closed coordinates check as the newer Owner bridge."""
        if not isinstance(value, dict) or set(value) != {
                "server_id", "torrent_hash", "file_index"}:
            raise ValueError("OWNER_BRIDGE_BACKGROUND_SELECTION_INVALID")
        server, torrent, index = (value["server_id"], value["torrent_hash"],
                                  value["file_index"])
        if (not isinstance(server, str)
                or not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", server)
                or not isinstance(torrent, str)
                or not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", torrent)
                or type(index) is not int or index < 0
                or session is None or fingerprint is None
                or hashlib.sha256("\x00".join((server, torrent, str(index)))
                                  .encode("utf-8")).hexdigest() != fingerprint):
            raise ValueError("OWNER_BRIDGE_BACKGROUND_SELECTION_INVALID")
        return {"server_id": server, "torrent_hash": torrent, "file_index": index}


class V3IdentityError(ValueError):
    """Sanitized mismatch, never a private path or title in public logs."""


@dataclass(frozen=True)
class SubtitleLookupIdentity:
    """The same exact media identity consumed by D1/D2 and LOCAL_EN_DIRECT.

    Metadata fields are RELEASE HINTS from a verified selected filename, not
    IMDb IDs, cryptographic verification of video bytes or subtitle sync.
    """
    media: Media
    title_hint: str
    year_hint: int | None
    source_hint: str | None
    resolution_hint: str | None
    codec_hint: str | None
    release_group_hint: str | None
    season_hint: int | None
    episode_hint: int | None


_SE = re.compile(r"(?:^|[._ -])s(\d{1,2})[._ -]?e(\d{1,3})(?=$|[._ -])", re.I)
_X = re.compile(r"(?:^|[._ -])(\d{1,2})x(\d{2,3})(?=$|[._ -])", re.I)


def _episode_token(filename: str) -> tuple[int, int] | None:
    match = _SE.search(filename) or _X.search(filename)
    if match is None:
        return None
    return int(match.group(1)), int(match.group(2))


def subtitle_lookup_identity(
    state: CurrentPlaying, record: TorrServerSelectedFile,
) -> SubtitleLookupIdentity:
    """Give D1/D2 the *selected server/hash/index/file*, never a guessed title.

    Caller must already have used resolve_selected_local_source with these
    same trusted state+record objects. Expose only release hints for ranking.
    """
    movie = Media(
        state.server_id, state.torrent_hash.lower(),
        state.file_index, state.video_name,
        torrent_title=record.torrent_title)
    release: Release = preferred_media_release(movie)
    by_filename = _episode_token(state.video_name)
    by_server_path = _episode_token(record.path)
    if by_filename is not None and by_server_path is not None and by_filename != by_server_path:
        raise V3IdentityError("V3_EPISODE_METADATA_CONFLICT")
    episode = by_filename or by_server_path
    return SubtitleLookupIdentity(
        media=movie,
        title_hint=release.title,
        year_hint=release.year,
        source_hint=release.source,
        resolution_hint=release.resolution,
        codec_hint=release.codec,
        release_group_hint=release.group,
        season_hint=episode[0] if episode else None,
        episode_hint=episode[1] if episode else None,
    )


class VerifiedV3Processor:
    """One owner-private inbox consumer; never creates a second worker.

    Trusted readers MUST be supplied from a previously authenticated
    owner-local OMP/TorrServer integration. The V3 envelope itself NEVER
    establishes identity/permission; every event is re-evaluated live.
    """

    def __init__(
        self, *,
        flow: object,
        private_media_root: Path,
        read_verified_current_playback: Callable[[], CurrentPlaying],
        read_verified_torrserver_file: Callable[[str, str, int], TorrServerSelectedFile],
        locate_owner_pinned_files: Callable[[str, str, int, str], OwnerPinnedFiles | None],
        on_vietsub_ready: Callable[..., object] | None = None,
    ) -> None:
        if not callable(getattr(flow, "selected_media", None)):
            raise V3IdentityError("V3_EXISTING_WORKER_REQUIRED")
        if not all(callable(f) for f in (
            read_verified_current_playback, read_verified_torrserver_file,
            locate_owner_pinned_files
        )):
            raise V3IdentityError("V3_AUTHENTICATED_READER_REQUIRED")
        if (not isinstance(private_media_root, Path)
                or not private_media_root.is_absolute()
                or private_media_root.is_symlink()):
            raise V3IdentityError("V3_OWNER_PRIVATE_ROOT_REQUIRED")
        self.flow = flow
        self.media_root = private_media_root
        self.read_current = read_verified_current_playback
        self.read_server = read_verified_torrserver_file
        if on_vietsub_ready is not None and not callable(on_vietsub_ready):
            raise V3IdentityError("V3_READY_CALLBACK_INVALID")
        self.locate_owner = locate_owner_pinned_files
        self.on_ready = on_vietsub_ready

    def selected_media(
        self, video_filename: str, *,
        source_fingerprint: str | None = None,
        tv_session_id: str | None = None,
        authorized_selection: dict[str, object] | None = None,
    ) -> object:
        if (not isinstance(source_fingerprint, str)
                or not isinstance(tv_session_id, str) or not tv_session_id):
            raise V3IdentityError("V3_SESSION_AND_FINGERPRINT_REQUIRED")
        if authorized_selection is not None:
            # Exact coordinates were frozen in the private event by the
            # already-authenticated P3 tap, while the viewer was still on A.
            # Neither closing A nor starting B revokes that translation job.
            coordinates = _authorized_selection(
                authorized_selection, source_fingerprint, tv_session_id)
            current = CurrentPlaying(
                kind="PLAY_REQUEST_ACCEPTED", attested=True, active=True,
                server_id=str(coordinates["server_id"]),
                tv_session_id=tv_session_id,
                torrent_hash=str(coordinates["torrent_hash"]),
                file_index=int(coordinates["file_index"]),
                video_name=video_filename, owner_auto_enabled=True,
                viewer_choice="REQUESTED", media_rights_approved=True,
                local_vi_state="ABSENT")
        else:
            # Preserve the old V3 fail-closed contract for events without
            # a signed-tap Owner snapshot. They may not outlive their TV.
            try:
                current = self.read_current()
            except Exception:
                raise PreProviderTransient("V3_TV_READER_UNAVAILABLE") from None
            if not isinstance(current, CurrentPlaying):
                raise PreProviderTransient("V3_CURRENT_MEDIA_UNAVAILABLE")
        if (source_fingerprint != _fingerprint(
                current.server_id, current.torrent_hash,
                current.file_index)):
            raise V3IdentityError("V3_CURRENT_SOURCE_MISMATCH")
        try:
            record = self.read_server(
                current.server_id, current.torrent_hash.lower(),
                current.file_index)
        except Exception:
            raise PreProviderTransient("V3_SERVER_READER_UNAVAILABLE") from None

        # The resolver performs ALL exact TV, session, metadata, owner-root,
        # local file and subtitle controls, even when no local EN is mapped.
        local: LocalMediaSelection | None = resolve_selected_local_source(
            requested_name=video_filename,
            source_fingerprint=source_fingerprint,
            expected_tv_session_id=tv_session_id,
            private_media_root=self.media_root,
            read_verified_current_playback=lambda: current,
            read_verified_torrserver_file=lambda *_: record,
            locate_owner_pinned_files=self.locate_owner,
        )
        lookup = subtitle_lookup_identity(current, record)
        # A missing parseable release title is NOT an identity mismatch.
        # The downstream source selector already returns REVIEW_REQUIRED
        # without provider downloads for incomplete release metadata.
        # Do not strand an otherwise authentic user request in .blocked.

        # Final live-session read: reduces stale A→B race while providers are
        # still NOT called. Downstream D3/P4 must independently verify exact
        # TV current media/session immediately before any subtitle delivery.
        if authorized_selection is None:
            try:
                latest = self.read_current()
            except Exception:
                raise PreProviderTransient("V3_TV_REFRESH_UNAVAILABLE") from None
        else:
            # Independent fresh TorrServer metadata was already verified;
            # background work uses the original per-film consent snapshot.
            latest = current
        if (not isinstance(latest, CurrentPlaying)
                or not latest.attested or not latest.active
                or latest.kind != current.kind
                or latest.server_id != current.server_id
                or latest.tv_session_id != current.tv_session_id
                or latest.torrent_hash.lower() != current.torrent_hash.lower()
                or latest.file_index != current.file_index
                or latest.video_name != current.video_name
                or latest.owner_auto_enabled is not True
                or latest.media_rights_approved is not True
                or latest.viewer_choice not in ("ON", "REQUESTED")
                or latest.local_vi_state == "PRESENT"):
            raise V3IdentityError("V3_TV_SELECTION_CHANGED")
        if latest.local_vi_state != "ABSENT":
            # A flaky ffprobe result is not evidence of a different TV item.
            # Defer before the provider and recheck, never permanently block
            # an otherwise unchanged and explicitly requested selection.
            raise PreProviderTransient("V3_TV_REFRESH_UNAVAILABLE")

        outcome = self.flow.selected_media(
            video_filename,
            source_fingerprint=source_fingerprint,
            verified_media=lookup.media,
            local_source=local,
        )
        if self.on_ready is not None and getattr(outcome, "status", None) in (
                "VI_READY", "VIETSUB_READY"):
            # Only the original source-discovery/LEAN120 result may create a
            # ready source. Registration independently revalidates the live
            # TV session, owner rights, exact file and private cache output.
            try:
                self.on_ready(
                    media=lookup.media, source_fingerprint=source_fingerprint,
                    tv_session_id=tv_session_id, flow=self.flow, result=outcome)
            except Exception as exc:
                # A→B/exit invalidates P4 delivery, NOT the completed A SRT.
                # Exact reason remains in Owner-private diagnostics.
                owner_full_trace("P4_READY_DEFERRED_TRANSLATION_SAVED", error=exc)
        return outcome
