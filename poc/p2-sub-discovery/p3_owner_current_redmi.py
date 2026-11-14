"""Current TV snapshot from signed native Redmi heartbeat + owner metadata.

A P3 PLAY signal alone cannot make this reader return anything. A distinct,
fresh, paired HMAC status sample is required, sourced at the native Redmi
PlayerSession/selected item and G1/P4 automatic choice. The profile comes
from a preconfigured owner-local localhost TorrServer reader, NEVER TV JSON.

Rights, owner AUTO and Vietnamese-track inventory are independent explicit
owner-side gates, not remotely controllable booleans or invented defaults.
"""
from __future__ import annotations

from typing import Callable
from pathlib import Path
import sys

# The legacy OpenSubtitles test runner imports modules without adding the
# P3 sibling package. Always resolve this pinned local tree, not cwd.
_p3_dir = str((Path(__file__).resolve().parent.parent / "p3-vietsub-trigger").resolve())
if _p3_dir not in sys.path:
    sys.path.insert(0, _p3_dir)

from activation_gate import PlaybackSelected
from owner_selected_file_resolver import CurrentPlaying, _one_basename
from owner_torrserver_readonly import OwnerTorrServerReader
from p3_redmi_current_state import SignedRedmiStateCache, RedmiStateRejected


class OwnerTvStateUnavailable(ValueError):
    """Safe sanitized HOLD reason."""


class OwnerCurrentRedmiReader:
    def __init__(self, *,
                 state_cache: SignedRedmiStateCache,
                 torrserver: OwnerTorrServerReader,
                 owner_auto_allowed: Callable[[], bool],
                 media_rights_allowed: Callable[[str, str, int], bool],
                 verified_local_vi_state: Callable[[str, str, int], str]):
        if (not isinstance(state_cache, SignedRedmiStateCache)
                or not isinstance(torrserver, OwnerTorrServerReader)
                or not all(callable(x) for x in (
                    owner_auto_allowed, media_rights_allowed,
                    verified_local_vi_state))):
            raise OwnerTvStateUnavailable("P3_OWNER_VERIFIED_READERS_REQUIRED")
        self._cache = state_cache
        self._ts = torrserver
        self._owner = owner_auto_allowed
        self._rights = media_rights_allowed
        self._vi = verified_local_vi_state

    def _current(self) -> tuple[object, str, bool, bool, str]:
        try:
            first = self._cache.read_fresh()
            # Only the configured owner TorrServer can supply authoritative
            # selected-file filename. No client input from TV title field.
            chosen = self._ts(self._ts._config.profile_id,
                              first.torrent_hash, first.file_index)
            name = _one_basename(chosen.path)
            allowed = self._owner()
            rights = self._rights(self._ts._config.profile_id,
                                  first.torrent_hash, first.file_index)
            vi = self._vi(self._ts._config.profile_id,
                          first.torrent_hash, first.file_index)
            second = self._cache.read_fresh()
            if (first.tv_session_id != second.tv_session_id
                    or first.torrent_hash != second.torrent_hash
                    or first.file_index != second.file_index
                    or first.kind != second.kind or first.boot_id != second.boot_id):
                raise OwnerTvStateUnavailable("P3_TV_STATE_CHANGED")
            if type(allowed) is not bool or type(rights) is not bool or vi not in (
                    "ABSENT", "PRESENT", "UNKNOWN"):
                raise OwnerTvStateUnavailable("P3_OWNER_POLICY_UNVERIFIED")
            return second, name, allowed, rights, vi
        except (RedmiStateRejected, OwnerTvStateUnavailable):
            raise OwnerTvStateUnavailable("P3_TV_STATE_NOT_CURRENT_OR_ON") from None
        except Exception:
            raise OwnerTvStateUnavailable("P3_OWNER_MEDIA_UNAVAILABLE") from None

    def read_playback(self) -> PlaybackSelected:
        state, name, allowed, rights, vi = self._current()
        return PlaybackSelected(
            kind=state.kind, attested=True, active=state.active,
            server_id=self._ts._config.profile_id,
            tv_session_id=state.tv_session_id,
            torrent_hash=state.torrent_hash, file_index=state.file_index,
            video_name=name, owner_auto_enabled=allowed,
            subtitle_choice=state.subtitle_choice,
            media_rights_approved=rights, local_vi_state=vi)

    def read_v3(self) -> CurrentPlaying:
        state, name, allowed, rights, vi = self._current()
        return CurrentPlaying(
            kind=state.kind, attested=True, active=state.active,
            server_id=self._ts._config.profile_id,
            tv_session_id=state.tv_session_id,
            torrent_hash=state.torrent_hash, file_index=state.file_index,
            video_name=name, owner_auto_enabled=allowed,
            viewer_choice=state.subtitle_choice,
            media_rights_approved=rights, local_vi_state=vi)
