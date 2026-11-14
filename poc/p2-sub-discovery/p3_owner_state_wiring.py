"""ONE source-only owner composition of signed Redmi P3 and existing V3/P4.

This is the missing typed wiring, not a runner, HTTP server starter, media
crawler or provider client. An explicit owner process must supply its PRIVATE
paired device secret, media roots and trusted policy/track inventory callbacks.

It reuses the existing P4 paired HTTPS handler and existing owner-session
agent via its trusted_v3_factory injection. There is no second translator,
OpenSubtitles client, or additional event queue.
"""
from __future__ import annotations

from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Callable, Type
import sys

_POC = Path(__file__).resolve().parent.parent
for _part in ("p2-aisub", "p3-vietsub-trigger"):
    _sub = str(_POC / _part)
    if _sub not in sys.path:
        sys.path.insert(0, _sub)

from paired_activation import PairedActivation
from owner_selected_file_resolver import OwnerPinnedFiles
from owner_torrserver_readonly import OwnerTorrServerReader
from verified_v3_processor import VerifiedV3Processor
from p3_redmi_current_state import SignedRedmiStateCache
from p3_owner_replay_journal import OwnerReplayJournal
from p3_owner_current_redmi import OwnerCurrentRedmiReader
from p3_signed_playback_signal import SignedPlaybackVerifier
from p3_signed_signal_to_owner import SignedP3ToOwner
from p3_p4_shared_https_route import make_p3_p4_handler


@dataclass(frozen=True)
class OwnerP3StatusComposition:
    """Call handler on the SAME previously approved P4 HTTPS server only."""
    handler: Type[BaseHTTPRequestHandler]
    cache: SignedRedmiStateCache
    current: OwnerCurrentRedmiReader
    signal: SignedP3ToOwner
    private_media_root: Path
    locate_owner_pinned_files: Callable

    def trusted_v3_factory(self, existing_flow: object) -> VerifiedV3Processor:
        """Passed into the existing #146 run_owner_agent(..., trusted_v3_factory).

        The existing worker still rechecks the current signed status before
        D1/D2/LOCAL_EN/LEAN120. A vanished TV or OFF yields HOLD.
        """
        return VerifiedV3Processor(
            flow=existing_flow,
            private_media_root=self.private_media_root,
            read_verified_current_playback=self.current.read_v3,
            read_verified_torrserver_file=self.current._ts,
            locate_owner_pinned_files=self.locate_owner_pinned_files,
        )


def compose_owner_redmi_status(*,
    p4_gateway: PairedActivation,
    paired_device_secret: bytes,
    torrserver_reader: OwnerTorrServerReader,
    owner_root: Path,
    private_media_root: Path,
    owner_auto_allowed: Callable[[], bool],
    media_rights_allowed: Callable[[str, str, int], bool],
    verified_local_vi_state: Callable[[str, str, int], str],
    locate_owner_pinned_files: Callable[[str, str, int, str], OwnerPinnedFiles | None],
) -> OwnerP3StatusComposition:
    """Returns handler and one existing-worker factory. Never binds a port."""
    if (not isinstance(p4_gateway, PairedActivation)
            or not isinstance(torrserver_reader, OwnerTorrServerReader)
            or not isinstance(owner_root, Path) or not owner_root.is_absolute()
            or not isinstance(private_media_root, Path)
            or not private_media_root.is_absolute()
            or not private_media_root.is_dir()
            or private_media_root.is_symlink()
            or not callable(locate_owner_pinned_files)):
        raise ValueError("P3_OWNER_REAL_SOURCE_AND_PRIVATE_ROOT_REQUIRED")
    # A different key than the P4-paired TV results in rejected signed data;
    # the explicitly approved runtime must provide its original pairing key.
    # The real owner composition MUST persist replay data; no optional
    # memory-only fallback may be used by this entrypoint.
    replay = OwnerReplayJournal(owner_root)
    cache = SignedRedmiStateCache(paired_device_secret, journal=replay)
    current = OwnerCurrentRedmiReader(
        state_cache=cache, torrserver=torrserver_reader,
        owner_auto_allowed=owner_auto_allowed,
        media_rights_allowed=media_rights_allowed,
        verified_local_vi_state=verified_local_vi_state,
    )
    p3_signal = SignedP3ToOwner(
        verifier=SignedPlaybackVerifier(paired_device_secret, journal=replay),
        owner_root=owner_root,
        read_verified_current_selection=current.read_playback,
    )
    handler = make_p3_p4_handler(p4_gateway, p3_signal, cache)
    return OwnerP3StatusComposition(
        handler=handler, cache=cache, current=current, signal=p3_signal,
        private_media_root=private_media_root,
        locate_owner_pinned_files=locate_owner_pinned_files,
    )
