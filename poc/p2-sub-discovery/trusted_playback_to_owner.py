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
from p3_signed_playback_signal import AuthenticatedSelectionSignal
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

    def on_current_selection_accepted(
        self, verified_viewer_request: AuthenticatedSelectionSignal | None = None,
    ) -> TriggerDecision:
        """Enqueue ONLY after the signed per-film on-TV viewer tap.

        A bare native Play/Next/ON snapshot is never authorization. The
        authenticated event can originate only from the already-paired
        SignedPlaybackVerifier in the HTTPS P3 adapter; no untrusted JSON,
        caller-supplied bool or title is accepted by this owner enqueue seam.
        """
        if (not isinstance(verified_viewer_request, AuthenticatedSelectionSignal)
                or verified_viewer_request.kind != "VIEWER_VIETSUB_REQUESTED"):
            return TriggerDecision("SKIP", "NO_VERIFIED_VIEWER_REQUEST")
        try:
            event = self.read_current()
        except Exception:
            # The trusted source may have been disconnected; do not leak
            # private OMP/TorrServer details or invent an active session.
            self.emit("OWNER_PLAYBACK_HOLD")
            return TriggerDecision("HOLD", "TRUSTED_SOURCE_UNAVAILABLE")
        if not isinstance(event, PlaybackSelected):
            self.emit("OWNER_PLAYBACK_HOLD")
            return TriggerDecision("HOLD", "MALFORMED_EVENT")
        if (event.kind not in ("PLAY_REQUEST_ACCEPTED", "NEXT_QUEUE_ITEM_ACCEPTED")
                or event.attested is not True or event.active is not True
                or event.subtitle_choice != "REQUESTED"
                or event.tv_session_id != verified_viewer_request.tv_session_id
                or event.torrent_hash.lower() != verified_viewer_request.torrent_hash
                or event.file_index != verified_viewer_request.file_index):
            return TriggerDecision("HOLD", "VIEWER_REQUEST_SOURCE_CHANGED")
        decision = self.gate.consider(event)
        if decision.status != "DISPATCH":
            self.emit("OWNER_PLAYBACK_" + decision.status)
            return decision
        try:
            enqueue_selected_media(
                event.video_name, owner_root=self.owner_root,
                source_fingerprint=decision.local_fingerprint,
                tv_session_id=event.tv_session_id)
        except Exception:
            # In-memory dedup MUST NOT swallow an event if private enqueue
            # failed before the owner agent received it. Never leak paths.
            self.gate.on_session_closed()
            raise ValueError("OWNER_PLAYBACK_PRIVATE_ENQUEUE_FAILED") from None
        self.emit("OWNER_PLAYBACK_PRIVATE_ENQUEUED")
        return decision

    def on_session_closed(self) -> None:
        self.gate.on_session_closed()
