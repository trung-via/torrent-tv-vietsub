"""Trusted OMP accepted-playback policy -> owner-private automatic Vietsub event.

This is the single event ADAPTER joining P3-TRIGGER (#142) with the already
implemented owner-session process (#143) and D2/P2 auto pipeline (#140).
No second worker/queue, no network listener, no API key, no TV media key.

Security: this function does NOT accept a JSON event from GitHub, WAN or a
public HTTP endpoint. It calls a REQUIRED trusted local provider function
that must authenticate the OMP PlayRequest, verify live session + exact
TorrServer hash/fileIndex, and resolve the selected filename itself.
The source P3 policy's 'attested=True' is NOT a cryptographic proof.
"""
from __future__ import annotations

from pathlib import Path
import sys
from typing import Callable

# Source-pinned sister policy directory from Draft #142.
_TRIGGER = (Path(__file__).resolve().parent.parent / "p3-vietsub-trigger").resolve()
if str(_TRIGGER) not in sys.path:
    sys.path.insert(0, str(_TRIGGER))

from activation_gate import ActivationDeduplicator, PlaybackSelected, TriggerDecision
from owner_session_bridge import enqueue_selected_media


class TrustedPlaybackToOwner:
    """Use only inside the authenticated owner-controlled OMP bridge.

    The source MUST snapshot a current verified TV PlayRequest and the
    identical selected TorrServer file. No request body/remote boolean may
    substitute for a trusted provider. Incomplete snapshots HOLD with no
    subtitle search, download, quota or event.
    """

    def __init__(
        self, *,
        read_verified_current_playback: Callable[[], PlaybackSelected],
        owner_root: Path,
        emit: Callable[[str], object] | None = None,
    ):
        if not callable(read_verified_current_playback):
            raise ValueError("OWNER_PLAYBACK_TRUSTED_SOURCE_REQUIRED")
        if not isinstance(owner_root, Path) or not owner_root.is_absolute():
            raise ValueError("OWNER_PLAYBACK_PRIVATE_ROOT_REQUIRED")
        self.read_current = read_verified_current_playback
        self.owner_root = owner_root
        self.emit = emit or (lambda _: None)
        self.gate = ActivationDeduplicator()

    def on_current_selection_accepted(self) -> TriggerDecision:
        """ONE callback when the TV truly accepts a playback selection.

        No raw caller-supplied event argument: fetch fresh trusted state now.
        The existing queue/agent handles private work asynchronously.
        """
        event = self.read_current()
        decision = self.gate.consider(event)
        if decision.status != "DISPATCH":
            self.emit("OWNER_PLAYBACK_" + decision.status)
            return decision
        try:
            enqueue_selected_media(
                event.video_name, owner_root=self.owner_root,
                source_fingerprint=decision.local_fingerprint)
        except Exception:
            # In-memory dedup MUST NOT swallow an event if private enqueue
            # failed before the owner agent received it. Never leak paths.
            self.gate.on_session_closed()
            raise ValueError("OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED") from None
        self.emit("OWNER_PLAYBACK_PRIVATE_ENQUEUED")
        return decision

    def on_session_closed(self) -> None:
        self.gate.on_session_closed()
